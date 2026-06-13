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
Write-Host "  Local    : http://${localIp}:${port}" -ForegroundColor Cyan
Write-Host "  Ctrl+C to stop." -ForegroundColor DarkGray
Write-Host ""

$pairCode | Set-Content (Join-Path $PSScriptRoot "pair_code.txt")
if ((Load-Tokens).Count -eq 0) { Start-Process "http://${localIp}:${port}/qr" }

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
    Send-Text $resp ($obj | ConvertTo-Json -Compress -Depth 5) "application/json" $code
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

    } elseif ($method -eq "GET" -and $path -eq "/qrcode.min.js") {
        Send-File $resp (Join-Path $webDir "qrcode.min.js") "application/javascript"

    } elseif ($method -eq "GET" -and $path -eq "/qr") {
        Send-File $resp (Join-Path $webDir "qr.html") "text/html; charset=utf-8"

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

    # Live stats
    } elseif ($method -eq "GET" -and $path -eq "/stats") {
        if (Valid-Token (Get-XToken $req)) {
            $cpu        = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average)
            $os         = Get-CimInstance Win32_OperatingSystem
            $ramTotalKB = [double]$os.TotalVisibleMemorySize
            $ramFreeKB  = [double]$os.FreePhysicalMemory
            $ramUsedKB  = $ramTotalKB - $ramFreeKB
            $ramPct     = [math]::Round($ramUsedKB / $ramTotalKB * 100)
            $ramUsedGB  = [math]::Round($ramUsedKB  / 1048576, 1)
            $ramTotalGB = [math]::Round($ramTotalKB / 1048576, 1)
            $disk       = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
            $diskTotalGB = [math]::Round([double]$disk.Size      / 1073741824, 1)
            $diskFreeGB  = [math]::Round([double]$disk.FreeSpace / 1073741824, 1)
            $diskUsedGB  = [math]::Round($diskTotalGB - $diskFreeGB, 1)
            $diskPct     = if ($diskTotalGB -gt 0) { [math]::Round($diskUsedGB / $diskTotalGB * 100) } else { 0 }
            $uptime      = (Get-Date) - $os.LastBootUpTime
            $uptimeStr   = "{0}d {1:00}h {2:00}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
            $skip        = @('ApplicationFrameHost','TextInputHost','SystemSettings','SearchUI',
                             'ShellExperienceHost','StartMenuExperienceHost','LockApp','dllhost',
                             'WindowsInternal.ComposableShell.Experiences.TextInput.InputApp')
            $apps        = @(Get-Process |
                Where-Object { $_.MainWindowTitle -ne '' -and $_.ProcessName -notin $skip } |
                Sort-Object CPU -Descending |
                Select-Object -First 15 |
                ForEach-Object { @{ name = $_.ProcessName; title = $_.MainWindowTitle } })
            $netRxKBps = 0; $netTxKBps = 0
            try {
                $ni = Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface |
                    Where-Object { $_.Name -notmatch 'Loopback|isatap|Teredo' }
                $netRxKBps = [math]::Round(($ni | Measure-Object -Property BytesReceivedPerSec -Sum).Sum / 1024, 1)
                $netTxKBps = [math]::Round(($ni | Measure-Object -Property BytesSentPerSec    -Sum).Sum / 1024, 1)
            } catch {}
            $procCount = (Get-Process).Count
            Send-Json $resp @{
                cpu    = $cpu
                ram    = @{ pct = $ramPct;  used = $ramUsedGB;  total = $ramTotalGB }
                disk   = @{ pct = $diskPct; used = $diskUsedGB; total = $diskTotalGB; free = $diskFreeGB }
                uptime = $uptimeStr
                net    = @{ dlKBps = $netRxKBps; ulKBps = $netTxKBps }
                procs  = $procCount
                apps   = $apps
            }
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
        Send-File $resp (Join-Path $webDir "index.html") "text/html; charset=utf-8"

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
