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
$tunnelErr = Join-Path $env:TEMP "powercontrol_tunnel_err.txt"
if (Test-Path $tunnelLog) { Remove-Item $tunnelLog }
if (Test-Path $tunnelErr) { Remove-Item $tunnelErr }

$sshCmd  = Get-Command ssh -ErrorAction SilentlyContinue
$sshPath = if ($sshCmd) { $sshCmd.Source } else { $null }

$sshProc   = $null
$publicUrl = $null

if ($sshPath) {
    $sshArgs = "-o StrictHostKeyChecking=no -o ServerAliveInterval=20 -o LogLevel=QUIET -R 80:localhost:${port} nokey@localhost.run"
    $sshProc = Start-Process ssh -ArgumentList $sshArgs `
        -RedirectStandardOutput $tunnelLog -RedirectStandardError $tunnelErr `
        -NoNewWindow -PassThru

    Write-Host "Connecting tunnel..." -ForegroundColor Gray
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline -and -not $publicUrl) {
        Start-Sleep -Milliseconds 400
        $txt = ""
        if (Test-Path $tunnelLog) { $txt += (Get-Content $tunnelLog -Raw -ErrorAction SilentlyContinue) }
        if (Test-Path $tunnelErr) { $txt += (Get-Content $tunnelErr -Raw -ErrorAction SilentlyContinue) }
        if ($txt -match 'https?://[a-z0-9\-]+\.lhr\.life') { $publicUrl = $Matches[0] }
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

    # Unpair
    } elseif ($method -eq "POST" -and $path -eq "/unpair") {
        Remove-Token (Get-XToken $req)
        Write-Host "Device unpaired." -ForegroundColor Yellow
        Send-Json $resp @{ ok = $true }

    # Control page (requires token)
    } elseif ($method -eq "GET" -and $path -eq "/") {
        if (Valid-Token (Get-XToken $req)) {
            Send-File $resp (Join-Path $webDir "index.html") "text/html; charset=utf-8"
        } else {
            $resp.StatusCode = 302
            $resp.Headers.Add("Location", "/pair")
            $resp.Close()
        }

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
