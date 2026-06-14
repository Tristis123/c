# Power Control Server
# Reads web files from the .\web\ folder next to this script.

$port      = 8765
$webDir    = Join-Path $PSScriptRoot "web"
$tokenFile = Join-Path $PSScriptRoot "paired_devices.json"
$pairCode  = (Get-Random -Minimum 100000 -Maximum 999999).ToString()

# ── Token helpers ────────────────────────────────────────────────────────────
function Load-Tokens {
    if (Test-Path $tokenFile) {
        try { $t = Get-Content $tokenFile -Raw | ConvertFrom-Json; return @($t) } catch {}
    }
    return @()
}
function Save-Tokens($list) { $list | ConvertTo-Json | Set-Content $tokenFile }
function Valid-Token($t)    { return (Load-Tokens) -contains $t }
function Add-Token($t)      { Save-Tokens (@(Load-Tokens) + $t) }
function Remove-Token($t)   { Save-Tokens (@(Load-Tokens) | Where-Object { $_ -ne $t }) }

# ── Start listener ───────────────────────────────────────────────────────────
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:${port}/")
try { $listener.Start() } catch {
    Write-Host ""
    Write-Host "ERROR: Could not start on port $port." -ForegroundColor Red
    Write-Host "Right-click start.bat > Run as administrator." -ForegroundColor Yellow
    Write-Host ""
    pause; exit 1
}

# ── SSH tunnel via localhost.run ─────────────────────────────────────────────
$tunnelLog = Join-Path $env:TEMP "powercontrol_tunnel.txt"
if (Test-Path $tunnelLog) { Remove-Item $tunnelLog }

$sshCmd  = Get-Command ssh -ErrorAction SilentlyContinue
$sshPath = if ($sshCmd) { $sshCmd.Source } else { $null }

$sshProc   = $null
$publicUrl = $null

if ($sshPath) {
    $sshArgs = "-o StrictHostKeyChecking=no -o ServerAliveInterval=20 -o LogLevel=QUIET -R 80:localhost:${port} nokey@localhost.run"
    $cmdArgs = "/c ssh $sshArgs > `"$tunnelLog`" 2>&1"
    $sshProc = Start-Process cmd -ArgumentList $cmdArgs -NoNewWindow -PassThru

    Write-Host "Connecting tunnel..." -ForegroundColor Gray
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline -and -not $publicUrl) {
        Start-Sleep -Milliseconds 400
        if (Test-Path $tunnelLog) {
            $txt = Get-Content $tunnelLog -Raw -ErrorAction SilentlyContinue
            if ($txt -match 'https?://[a-z0-9\-]+\.lhr\.life') { $publicUrl = $Matches[0] }
        }
    }
    if (-not $publicUrl) {
        Write-Host "Tunnel timed out. Using local WiFi only." -ForegroundColor Yellow
    }
} else {
    Write-Host "ssh not found. Using local WiFi only." -ForegroundColor Yellow
}

# ── Local IP ─────────────────────────────────────────────────────────────────
$localIp = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notmatch "^(127\.|169\.254\.)" } |
    Select-Object -First 1).IPAddress

# ── Print info ───────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "+-----------------------------------------+" -ForegroundColor Magenta
Write-Host "|      POWER CONTROL  --  PAIR CODE       |" -ForegroundColor Magenta
Write-Host "|                                         |" -ForegroundColor Magenta
Write-Host ("|              " + $pairCode + "                      |") -ForegroundColor White
Write-Host "|                                         |" -ForegroundColor Magenta
Write-Host "+-----------------------------------------+" -ForegroundColor Magenta
Write-Host ""
if ($publicUrl) { Write-Host "  Internet : $publicUrl" -ForegroundColor Cyan }
Write-Host "  Local    : http://${localIp}:${port}" -ForegroundColor Gray
Write-Host "  Ctrl+C to stop." -ForegroundColor DarkGray
Write-Host ""

$openUrl = if ($publicUrl) { $publicUrl } else { "http://${localIp}:${port}" }
Start-Process $openUrl

# ── System stats (comprehensive) ─────────────────────────────────────────────
$script:prevNetDown = 0; $script:prevNetUp = 0; $script:prevNetTime = (Get-Date)

function Get-SystemStats {
    $s = @{}

    # ── CPU load + clock + throttle ──────────────────────────────────────────
    try {
        $cpus = Get-WmiObject -Query "SELECT LoadPercentage,CurrentClockSpeed,MaxClockSpeed,Name,NumberOfCores FROM Win32_Processor"
        $s.cpu         = [math]::Round(($cpus | Measure-Object -Property LoadPercentage -Average).Average)
        $first         = $cpus | Select-Object -First 1
        $s.cpuName     = $first.Name.Trim() -replace '\s{2,}', ' '
        $s.cpuCores    = $first.NumberOfCores
        $s.cpuClockMhz = $first.CurrentClockSpeed
        $s.cpuMaxMhz   = $first.MaxClockSpeed
        # Only flag throttle when CPU is actually under load — SpeedStep/power-saving
        # legitimately drops clocks at idle, which would be a false positive otherwise
        $s.cpuThrottle = ($s.cpu -gt 20 -and $s.cpuClockMhz -lt [int]($s.cpuMaxMhz * 0.88))
    } catch { $s.cpu = 0 }

    # ── CPU temperature ───────────────────────────────────────────────────────
    # Windows does not expose CPU core temps via safe built-in APIs.
    # All tools that read them (HWiNFO, LHWM, etc.) require a kernel driver.
    # We try ACPI thermal zones as a best-effort — works on a minority of boards.
    try {
        $tzs = Get-WmiObject -Namespace root/wmi -Class MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
        if ($tzs) {
            $temps = @($tzs | ForEach-Object { [math]::Round($_.CurrentTemperature / 10 - 273.15) } |
                      Where-Object { $_ -gt 0 -and $_ -lt 120 })
            if ($temps.Count -gt 0) {
                $s.cpuTemp = ($temps | Measure-Object -Maximum).Maximum
                $s.cpuTemps = $temps
            }
        }
    } catch {}
    # cpuTemp stays $null if unavailable — UI shows "Not available"

    # ── RAM + pagefile ────────────────────────────────────────────────────────
    try {
        $os = Get-WmiObject Win32_OperatingSystem
        $s.ramTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $s.ramFreeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $s.ramUsedGB  = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
        $s.ram        = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100)

        $pf = Get-WmiObject Win32_PageFileUsage -ErrorAction SilentlyContinue
        if ($pf) {
            $s.swapUsedMB  = ($pf | Measure-Object -Property CurrentUsage -Sum).Sum
            $s.swapTotalMB = ($pf | Measure-Object -Property AllocatedBaseSize -Sum).Sum
            $s.swapPct     = if ($s.swapTotalMB -gt 0) { [math]::Round($s.swapUsedMB / $s.swapTotalMB * 100) } else { 0 }
        }

        $s.uptime = [math]::Round(((Get-Date) - ($os.ConvertToDateTime($os.LastBootUpTime))).TotalSeconds)
    } catch {}

    # ── GPU (NVIDIA via nvidia-smi) ───────────────────────────────────────────
    $nvSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($nvSmi) {
        try {
            # Query individual throttle reasons so we can distinguish real issues
            # from benign idle/power-saving clock reduction
            $raw = & nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total,clocks.current.graphics,clocks.current.memory,power.draw,power.limit,clocks_throttle_reasons.hw_slowdown,clocks_throttle_reasons.hw_thermal_slowdown,clocks_throttle_reasons.sw_thermal_slowdown,clocks_throttle_reasons.hw_power_brake_slowdown --format=csv,noheader,nounits 2>$null
            $gpus = @()
            foreach ($line in ($raw -split "`n" | Where-Object { $_.Trim() })) {
                $f = $line -split ',\s*'
                if ($f.Count -lt 10) { continue }
                $vramUsedMB  = [int]($f[4] -replace '[^\d]','')
                $vramTotalMB = [int]($f[5] -replace '[^\d]','')
                # Throttling = only true if a real thermal/power issue is active
                # (NOT idle state or application-chosen clock reduction)
                $realThrottle = $false
                if ($f.Count -ge 14) {
                    $realThrottle = ($f[10].Trim() -eq 'Active') -or  # HW slowdown
                                    ($f[11].Trim() -eq 'Active') -or  # HW thermal
                                    ($f[12].Trim() -eq 'Active') -or  # SW thermal
                                    ($f[13].Trim() -eq 'Active')      # Power brake
                }
                $gpus += @{
                    index        = [int]($f[0] -replace '[^\d]','')
                    name         = $f[1].Trim()
                    temp         = [int]($f[2] -replace '[^\d]','')
                    load         = [int]($f[3] -replace '[^\d]','')
                    vramUsedMB   = $vramUsedMB
                    vramTotalMB  = $vramTotalMB
                    vramUsedGB   = [math]::Round($vramUsedMB / 1024, 1)
                    vramTotalGB  = [math]::Round($vramTotalMB / 1024, 1)
                    vramPct      = if ($vramTotalMB -gt 0) { [math]::Round($vramUsedMB / $vramTotalMB * 100) } else { 0 }
                    clockMhz     = [int]($f[6] -replace '[^\d]','')
                    memClockMhz  = [int]($f[7] -replace '[^\d]','')
                    powerDraw    = if ($f[8] -match '[\d.]+') { [math]::Round([float]($f[8] -replace '[^\d.]',''), 1) } else { $null }
                    powerLimit   = if ($f[9] -match '[\d.]+') { [math]::Round([float]($f[9] -replace '[^\d.]',''), 1) } else { $null }
                    throttling   = $realThrottle
                    tempOk       = [int]($f[2] -replace '[^\d]','') -lt 85
                    vendor       = 'NVIDIA'
                }
            }
            $s.gpus       = $gpus
            $s.gpuVendor  = 'NVIDIA'
            $s.gpuThrottle = (@($gpus | Where-Object { $_.throttling }).Count -gt 0)
        } catch {}
    }

    # ── GPU fallback (AMD / Intel via Win32_VideoController) ─────────────────
    if (-not $s.gpus) {
        try {
            $vcs = Get-WmiObject Win32_VideoController -ErrorAction SilentlyContinue |
                   Where-Object { $_.AdapterRAM -gt 0 -and $_.PNPDeviceID -notmatch 'ROOT' }
            if ($vcs) {
                $gpus = @(); $i = 0
                foreach ($vc in $vcs) {
                    $gpus += @{
                        index       = $i; name = $vc.Caption.Trim()
                        temp        = $null; load = $null; throttling = $false; tempOk = $true
                        vramTotalGB = [math]::Round($vc.AdapterRAM / 1GB, 1)
                        vramUsedGB  = $null; vramPct = $null
                        clockMhz    = $null; memClockMhz = $null
                        powerDraw   = $null; powerLimit  = $null
                        vendor      = if ($vc.Caption -match 'AMD|Radeon') { 'AMD' } elseif ($vc.Caption -match 'Intel') { 'Intel' } else { 'GPU' }
                    }
                    $i++
                }
                $s.gpus = $gpus
            }
        } catch {}
    }

    # ── Network (real KB/s via performance counters) ──────────────────────────
    try {
        $nets = Get-WmiObject -Query "SELECT BytesReceivedPersec,BytesSentPersec FROM Win32_PerfFormattedData_Tcpip_NetworkInterface WHERE Name NOT LIKE '%Loopback%' AND Name NOT LIKE '%Teredo%'" -ErrorAction SilentlyContinue
        if ($nets) {
            $s.netDown = [math]::Round(($nets | Measure-Object -Property BytesReceivedPersec -Sum).Sum / 1024, 1)
            $s.netUp   = [math]::Round(($nets | Measure-Object -Property BytesSentPersec   -Sum).Sum / 1024, 1)
        } else { $s.netDown = 0; $s.netUp = 0 }
    } catch { $s.netDown = 0; $s.netUp = 0 }

    # ── Processes ─────────────────────────────────────────────────────────────
    try { $s.procs = @(Get-Process -ErrorAction SilentlyContinue).Count } catch { $s.procs = 0 }

    # ── Overall throttle alert ─────────────────────────────────────────────────
    $s.anyThrottle = ($s.cpuThrottle -or $s.gpuThrottle)

    return $s
}

# ── Response helpers ─────────────────────────────────────────────────────────
function Send-Bytes($resp, $bytes, $type, $code = 200) {
    $resp.StatusCode = $code
    $resp.ContentType = $type
    $resp.ContentLength64 = $bytes.Length
    $resp.OutputStream.Write($bytes, 0, $bytes.Length)
    $resp.Close()
}
function Send-File($resp, $file, $type) {
    if (Test-Path $file) {
        $bytes = [System.IO.File]::ReadAllBytes($file)
        Send-Bytes $resp $bytes $type
    } else {
        $resp.StatusCode = 404; $resp.Close()
    }
}
function Send-Text($resp, $text, $type, $code = 200) {
    Send-Bytes $resp ([System.Text.Encoding]::UTF8.GetBytes($text)) $type $code
}
function Send-Html($resp, $text, $code = 200) {
    Send-Text $resp $text "text/html; charset=utf-8" $code
}
function Send-Json($resp, $obj, $code = 200) {
    Send-Text $resp ($obj | ConvertTo-Json -Compress) "application/json" $code
}
function Read-Body($req) {
    $r = New-Object System.IO.StreamReader($req.InputStream)
    return $r.ReadToEnd()
}
function Parse-Form($raw) {
    $map = @{}
    foreach ($p in $raw.Split("&")) {
        $kv = $p.Split("=", 2)
        if ($kv.Count -eq 2) { $map[$kv[0]] = [uri]::UnescapeDataString($kv[1]) }
    }
    return $map
}
function Get-XToken($req) { return $req.Headers["X-Token"] }

# ── Request loop ─────────────────────────────────────────────────────────────
$stop = $false
while ($listener.IsListening -and -not $stop) {
    $ctx    = $listener.GetContext()
    $req    = $ctx.Request
    $resp   = $ctx.Response
    $method = $req.HttpMethod
    $path   = $req.Url.LocalPath

    # Static assets
    if ($method -eq "GET" -and $path -eq "/manifest.json") {
        Send-File $resp (Join-Path $webDir "manifest.json") "application/manifest+json"

    } elseif ($method -eq "GET" -and $path -eq "/icon.svg") {
        Send-File $resp (Join-Path $webDir "icon.svg") "image/svg+xml"

    } elseif ($method -eq "GET" -and $path -eq "/sw.js") {
        Send-File $resp (Join-Path $webDir "sw.js") "application/javascript"

    # Pair page
    } elseif ($method -eq "GET" -and $path -eq "/pair") {
        Send-File $resp (Join-Path $webDir "pair.html") "text/html; charset=utf-8"

    # Pair action
    } elseif ($method -eq "POST" -and $path -eq "/pair") {
        $form = Parse-Form (Read-Body $req)
        if ($form["code"] -eq $pairCode) {
            $tok = [System.Guid]::NewGuid().ToString("N")
            Add-Token $tok
            Write-Host "Device paired." -ForegroundColor Green
            Send-Json $resp @{ ok = $true; token = $tok }
        } else {
            Send-Json $resp @{ ok = $false } 403
        }

    # Info (returns hostname for the control page)
    } elseif ($method -eq "GET" -and $path -eq "/info") {
        if (Valid-Token (Get-XToken $req)) {
            Send-Json $resp @{ host = $env:COMPUTERNAME }
        } else {
            Send-Json $resp @{ error = "forbidden" } 403
        }

    # Stats (live system data)
    } elseif ($method -eq "GET" -and $path -eq "/stats") {
        if (Valid-Token (Get-XToken $req)) {
            $statsCache = Get-SystemStats
            Send-Json $resp $statsCache
        } else {
            Send-Json $resp @{ error = "forbidden" } 403
        }

    # Unpair
    } elseif ($method -eq "POST" -and $path -eq "/unpair") {
        Remove-Token (Get-XToken $req)
        Write-Host "Device unpaired." -ForegroundColor Yellow
        Send-Json $resp @{ ok = $true }

    # Control page — served to all; JS checks token via /info and redirects if needed
    } elseif ($method -eq "GET" -and $path -eq "/") {
        Send-File $resp (Join-Path $webDir "control.html") "text/html; charset=utf-8"

    # Power action (requires token)
    } elseif ($method -eq "POST" -and $path -eq "/action") {
        if (-not (Valid-Token (Get-XToken $req))) {
            Send-Html $resp "Forbidden" 403
        } else {
            $form = Parse-Form (Read-Body $req)
            $cmd  = $form["cmd"]
            if ($cmd -eq "shutdown") {
                Send-Html $resp "<h1>Shutting down...</h1>"
                Write-Host "CMD: shutdown" -ForegroundColor Red
                shutdown /s /t 3
                $stop = $true
            } elseif ($cmd -eq "sleep") {
                Send-Html $resp "<h1>Going to sleep...</h1>"
                Write-Host "CMD: sleep" -ForegroundColor Yellow
                rundll32.exe powrprof.dll,SetSuspendState 0,1,0
            } elseif ($cmd -eq "reboot") {
                Send-Html $resp "<h1>Rebooting...</h1>"
                Write-Host "CMD: reboot" -ForegroundColor Blue
                shutdown /r /t 3
                $stop = $true
            } else {
                $resp.StatusCode = 400; $resp.Close()
            }
        }

    } else {
        $resp.StatusCode = 404; $resp.Close()
    }
}

$listener.Stop()
if ($sshProc -and -not $sshProc.HasExited) { $sshProc.Kill() }
