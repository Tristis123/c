# WiFi Shutdown Server - PowerShell (no dependencies)
$port = 8765

# Get local IP
$ip = (Get-NetIPAddress -AddressFamily IPv4 |
       Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
       Select-Object -First 1).IPAddress

$url = "http://${ip}:${port}/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:${port}/")

try {
    $listener.Start()
} catch {
    Write-Host ""
    Write-Host "ERROR: Could not start listener on port $port." -ForegroundColor Red
    Write-Host "Try running this script as Administrator (right-click > Run as administrator)." -ForegroundColor Yellow
    Write-Host ""
    pause
    exit 1
}

Write-Host ""
Write-Host "Shutdown server running!" -ForegroundColor Green
Write-Host "Open this on your phone: $url" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop." -ForegroundColor Gray
Write-Host ""

# Auto-open in browser
Start-Process $url

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Remote Shutdown</title>
  <style>
    body { font-family: sans-serif; display: flex; flex-direction: column;
           align-items: center; justify-content: center; min-height: 100vh;
           margin: 0; background: #1a1a2e; color: #eee; }
    h1 { font-size: 1.5rem; margin-bottom: 2rem; }
    button { padding: 1rem 2.5rem; font-size: 1.2rem; border: none;
             border-radius: 8px; cursor: pointer; margin: 0.5rem; }
    .shutdown { background: #e63946; color: white; }
    .reboot   { background: #457b9d; color: white; }
    .host { font-size: 0.85rem; opacity: 0.5; margin-top: 2rem; }
  </style>
</head>
<body>
  <h1>&#128187; Remote Power Control</h1>
  <form method="POST" action="/action" onsubmit="return confirm('Are you sure?')">
    <button class="shutdown" name="cmd" value="shutdown">&#x23FB; Shut Down</button><br><br>
    <button class="reboot"   name="cmd" value="reboot">&#x21BA; Reboot</button>
  </form>
  <p class="host">$env:COMPUTERNAME</p>
</body>
</html>
"@

$doneHtml = @"
<!DOCTYPE html><html><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>body{font-family:sans-serif;text-align:center;padding:3rem;
background:#1a1a2e;color:#eee;}</style></head>
<body><h1>{0}</h1><p>Command sent.</p></body></html>
"@

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $req  = $context.Request
    $resp = $context.Response

    if ($req.HttpMethod -eq "GET" -and $req.Url.LocalPath -eq "/") {
        $buf = [System.Text.Encoding]::UTF8.GetBytes($html)
        $resp.ContentType = "text/html; charset=utf-8"
        $resp.ContentLength64 = $buf.Length
        $resp.OutputStream.Write($buf, 0, $buf.Length)

    } elseif ($req.HttpMethod -eq "POST" -and $req.Url.LocalPath -eq "/action") {
        $reader = New-Object System.IO.StreamReader($req.InputStream)
        $body   = $reader.ReadToEnd()
        $params = @{}
        foreach ($pair in $body.Split("&")) {
            $kv = $pair.Split("=", 2)
            if ($kv.Count -eq 2) { $params[$kv[0]] = [uri]::UnescapeDataString($kv[1]) }
        }

        $cmd = $params["cmd"]
        if ($cmd -eq "shutdown") {
            $msg = "Shutting down..."
            $action = { shutdown /s /t 3 }
        } elseif ($cmd -eq "reboot") {
            $msg = "Rebooting..."
            $action = { shutdown /r /t 3 }
        } else {
            $resp.StatusCode = 400
            $resp.Close()
            continue
        }

        $out = [System.Text.Encoding]::UTF8.GetBytes(($doneHtml -f $msg))
        $resp.ContentType = "text/html; charset=utf-8"
        $resp.ContentLength64 = $out.Length
        $resp.OutputStream.Write($out, 0, $out.Length)
        $resp.Close()

        Write-Host "Command: $cmd" -ForegroundColor Yellow
        & $action
        break
    } else {
        $resp.StatusCode = 404
    }

    $resp.Close()
}

$listener.Stop()
