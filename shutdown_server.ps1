# WiFi Power Control Server - PowerShell
$port = 8765

$ip = (Get-NetIPAddress -AddressFamily IPv4 |
       Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
       Select-Object -First 1).IPAddress

$url = "http://${ip}:${port}/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:${port}/")

try { $listener.Start() } catch {
    Write-Host "`nERROR: Could not start on port $port." -ForegroundColor Red
    Write-Host "Right-click start.bat > Run as administrator." -ForegroundColor Yellow
    pause; exit 1
}

Write-Host "`nPower Control running!" -ForegroundColor Green
Write-Host "Phone URL: $url" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop.`n" -ForegroundColor Gray
Start-Process $url

# ── SVG icon (base64 PNG would be ideal but inline SVG works for manifest) ──
$iconSvg = @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" fill="none">
  <rect width="512" height="512" rx="120" fill="#0f0f1a"/>
  <circle cx="256" cy="256" r="160" stroke="#7c3aed" stroke-width="28" fill="none"/>
  <line x1="256" y1="100" x2="256" y2="260" stroke="#a78bfa" stroke-width="32" stroke-linecap="round"/>
</svg>
'@

$manifest = @'
{
  "name": "Power Control",
  "short_name": "Power",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#0f0f1a",
  "theme_color": "#7c3aed",
  "icons": [
    { "src": "/icon.svg", "sizes": "any", "type": "image/svg+xml", "purpose": "any maskable" }
  ]
}
'@

$sw = @'
self.addEventListener("fetch", e => e.respondWith(fetch(e.request)));
'@

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
  <meta name="theme-color" content="#7c3aed">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="Power Control">
  <link rel="manifest" href="/manifest.json">
  <link rel="apple-touch-icon" href="/icon.svg">
  <title>Power Control</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    :root {
      --bg:      #0f0f1a;
      --surface: #1a1a2e;
      --border:  #2a2a45;
      --purple:  #7c3aed;
      --purple2: #a78bfa;
      --red:     #dc2626;
      --red2:    #f87171;
      --blue:    #2563eb;
      --blue2:   #60a5fa;
      --amber:   #d97706;
      --amber2:  #fbbf24;
      --text:    #f1f5f9;
      --muted:   #64748b;
    }

    body {
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      min-height: 100dvh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 2rem 1.5rem;
      gap: 2.5rem;
    }

    /* glow background blob */
    body::before {
      content: "";
      position: fixed;
      top: -20%;
      left: 50%;
      transform: translateX(-50%);
      width: 600px;
      height: 600px;
      background: radial-gradient(circle, #7c3aed22 0%, transparent 70%);
      pointer-events: none;
    }

    header {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 0.75rem;
      text-align: center;
    }

    .power-ring {
      width: 72px;
      height: 72px;
      border-radius: 50%;
      border: 3px solid var(--purple);
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 0 24px #7c3aed55, inset 0 0 12px #7c3aed22;
      animation: pulse 3s ease-in-out infinite;
    }
    @keyframes pulse {
      0%,100% { box-shadow: 0 0 24px #7c3aed55, inset 0 0 12px #7c3aed22; }
      50%      { box-shadow: 0 0 40px #7c3aed99, inset 0 0 20px #7c3aed44; }
    }
    .power-ring svg { width: 36px; height: 36px; }

    h1 { font-size: 1.4rem; font-weight: 700; letter-spacing: -0.02em; }
    .host { font-size: 0.8rem; color: var(--muted); letter-spacing: 0.05em; text-transform: uppercase; }

    .grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 1rem;
      width: 100%;
      max-width: 340px;
    }
    .grid .wide { grid-column: 1 / -1; }

    .btn {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 0.5rem;
      padding: 1.4rem 1rem;
      border: 1.5px solid var(--border);
      border-radius: 18px;
      background: var(--surface);
      color: var(--text);
      font-size: 0.9rem;
      font-weight: 600;
      cursor: pointer;
      transition: transform 0.12s, box-shadow 0.2s, border-color 0.2s, background 0.2s;
      -webkit-tap-highlight-color: transparent;
      user-select: none;
    }
    .btn:active { transform: scale(0.94); }
    .btn svg { width: 32px; height: 32px; }

    .btn-shutdown { --c: var(--red); --c2: var(--red2); }
    .btn-sleep    { --c: var(--amber); --c2: var(--amber2); }
    .btn-reboot   { --c: var(--blue); --c2: var(--blue2); }

    .btn-shutdown, .btn-sleep, .btn-reboot {
      border-color: color-mix(in srgb, var(--c) 40%, transparent);
    }
    .btn-shutdown:hover, .btn-sleep:hover, .btn-reboot:hover {
      background: color-mix(in srgb, var(--c) 12%, var(--surface));
      border-color: var(--c);
      box-shadow: 0 0 18px color-mix(in srgb, var(--c) 30%, transparent);
    }
    .btn svg path, .btn svg circle, .btn svg polyline, .btn svg line {
      stroke: var(--c2);
    }
    .label-icon { color: var(--c2); }

    footer { font-size: 0.75rem; color: var(--muted); }

    /* modal overlay */
    .modal {
      display: none;
      position: fixed; inset: 0;
      background: #000a;
      backdrop-filter: blur(6px);
      align-items: center;
      justify-content: center;
      z-index: 10;
    }
    .modal.open { display: flex; }
    .modal-box {
      background: var(--surface);
      border: 1.5px solid var(--border);
      border-radius: 20px;
      padding: 2rem 1.5rem;
      max-width: 300px;
      width: 90%;
      text-align: center;
      display: flex;
      flex-direction: column;
      gap: 1.2rem;
    }
    .modal-box h2 { font-size: 1.1rem; }
    .modal-box p  { font-size: 0.88rem; color: var(--muted); }
    .modal-actions { display: flex; gap: 0.75rem; }
    .modal-actions button {
      flex: 1;
      padding: 0.75rem;
      border-radius: 12px;
      border: 1.5px solid var(--border);
      font-size: 0.9rem;
      font-weight: 600;
      cursor: pointer;
      background: var(--bg);
      color: var(--text);
    }
    .modal-actions .confirm {
      background: var(--confirm-c, var(--purple));
      border-color: var(--confirm-c, var(--purple));
      color: #fff;
    }
  </style>
</head>
<body>

<header>
  <div class="power-ring">
    <svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round">
      <path d="M12 2v10" stroke="#a78bfa"/>
      <path d="M18.4 6.6a9 9 0 1 1-12.8 0" stroke="#7c3aed"/>
    </svg>
  </div>
  <h1>Power Control</h1>
  <span class="host">$env:COMPUTERNAME</span>
</header>

<div class="grid">
  <button class="btn btn-shutdown wide" onclick="ask('shutdown','Shut Down','Really shut down the PC?','#dc2626')">
    <svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round">
      <path d="M12 2v10"/><path d="M18.4 6.6a9 9 0 1 1-12.8 0"/>
    </svg>
    <span>Shut Down</span>
  </button>

  <button class="btn btn-sleep" onclick="ask('sleep','Sleep','Put the PC to sleep?','#d97706')">
    <svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>
    </svg>
    <span>Sleep</span>
  </button>

  <button class="btn btn-reboot" onclick="ask('reboot','Reboot','Really reboot the PC?','#2563eb')">
    <svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <polyline points="23 4 23 10 17 10"/>
      <path d="M20.5 15a9 9 0 1 1-2.1-9.4L23 10"/>
    </svg>
    <span>Reboot</span>
  </button>
</div>

<footer>Connected via WiFi</footer>

<!-- confirm modal -->
<div class="modal" id="modal">
  <div class="modal-box">
    <h2 id="modal-title"></h2>
    <p id="modal-body"></p>
    <div class="modal-actions">
      <button onclick="closeModal()">Cancel</button>
      <button class="confirm" id="modal-confirm" onclick="doAction()">Confirm</button>
    </div>
  </div>
</div>

<script>
  // PWA service worker
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js').catch(() => {});
  }

  let pendingCmd = null;

  function ask(cmd, title, body, color) {
    pendingCmd = cmd;
    document.getElementById('modal-title').textContent = title;
    document.getElementById('modal-body').textContent  = body;
    document.getElementById('modal-confirm').style.background   = color;
    document.getElementById('modal-confirm').style.borderColor  = color;
    document.getElementById('modal').classList.add('open');
  }

  function closeModal() {
    document.getElementById('modal').classList.remove('open');
    pendingCmd = null;
  }

  function doAction() {
    if (!pendingCmd) return;
    closeModal();
    const form = document.createElement('form');
    form.method = 'POST'; form.action = '/action';
    const inp = document.createElement('input');
    inp.type = 'hidden'; inp.name = 'cmd'; inp.value = pendingCmd;
    form.appendChild(inp);
    document.body.appendChild(form);
    form.submit();
  }

  document.getElementById('modal').addEventListener('click', e => {
    if (e.target === e.currentTarget) closeModal();
  });
</script>
</body>
</html>
"@

$doneHtml = @"
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#7c3aed">
<link rel="manifest" href="/manifest.json">
<title>Power Control</title>
<style>
  body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
  background:#0f0f1a;color:#f1f5f9;display:flex;flex-direction:column;
  align-items:center;justify-content:center;min-height:100dvh;gap:1rem;padding:2rem;}
  h1{font-size:1.6rem;} p{color:#64748b;font-size:0.9rem;}
</style></head>
<body><h1>{0}</h1><p>Command sent to your PC.</p></body></html>
"@

function Send-Response($resp, $body, $type = "text/html; charset=utf-8") {
    $buf = [System.Text.Encoding]::UTF8.GetBytes($body)
    $resp.ContentType = $type
    $resp.ContentLength64 = $buf.Length
    $resp.OutputStream.Write($buf, 0, $buf.Length)
    $resp.Close()
}

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $req  = $context.Request
    $resp = $context.Response
    $path = $req.Url.LocalPath

    if ($req.HttpMethod -eq "GET") {
        switch ($path) {
            "/"             { Send-Response $resp $html }
            "/manifest.json"{ Send-Response $resp $manifest "application/manifest+json" }
            "/icon.svg"     { Send-Response $resp $iconSvg "image/svg+xml" }
            "/sw.js"        { Send-Response $resp $sw "application/javascript" }
            default         { $resp.StatusCode = 404; $resp.Close() }
        }
    } elseif ($req.HttpMethod -eq "POST" -and $path -eq "/action") {
        $reader = New-Object System.IO.StreamReader($req.InputStream)
        $body   = $reader.ReadToEnd()
        $params = @{}
        foreach ($pair in $body.Split("&")) {
            $kv = $pair.Split("=", 2)
            if ($kv.Count -eq 2) { $params[$kv[0]] = [uri]::UnescapeDataString($kv[1]) }
        }

        $cmd = $params["cmd"]
        switch ($cmd) {
            "shutdown" { $msg = "Shutting down...";  $action = { shutdown /s /t 3 } }
            "sleep"    { $msg = "Going to sleep..."; $action = { rundll32.exe powrprof.dll,SetSuspendState 0,1,0 } }
            "reboot"   { $msg = "Rebooting...";      $action = { shutdown /r /t 3 } }
            default    { $resp.StatusCode = 400; $resp.Close(); continue }
        }

        Send-Response $resp ($doneHtml -f $msg)
        Write-Host "Command: $cmd" -ForegroundColor Yellow
        & $action
        if ($cmd -ne "sleep") { break }
    } else {
        $resp.StatusCode = 404; $resp.Close()
    }
}

$listener.Stop()
