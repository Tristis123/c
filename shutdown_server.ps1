# WiFi / Internet Power Control Server
# Uses localhost.run SSH tunnel (free, no account needed, built into Windows 10+)

$port      = 8765
$tokenFile = Join-Path $PSScriptRoot "paired_devices.json"

# ── Pairing code (new each session) ────────────────────────────────────────
$pairCode = (Get-Random -Minimum 100000 -Maximum 999999).ToString()

# ── Load saved tokens ───────────────────────────────────────────────────────
function Load-Tokens {
    if (Test-Path $tokenFile) {
        try { return (Get-Content $tokenFile -Raw | ConvertFrom-Json) } catch {}
    }
    return @()
}
function Save-Tokens($list) {
    $list | ConvertTo-Json | Set-Content $tokenFile
}
function Is-ValidToken($tok) {
    $tokens = Load-Tokens
    return ($tokens -contains $tok)
}
function Add-Token($tok) {
    $tokens = @(Load-Tokens) + $tok
    Save-Tokens $tokens
}

# ── Start HTTP listener ─────────────────────────────────────────────────────
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:${port}/")
try { $listener.Start() } catch {
    Write-Host "`nERROR: Cannot start on port $port." -ForegroundColor Red
    Write-Host "Right-click start.bat > Run as administrator." -ForegroundColor Yellow
    pause; exit 1
}

# ── SSH tunnel via localhost.run ────────────────────────────────────────────
$tunnelLog = "$env:TEMP\powercontrol_tunnel.txt"
if (Test-Path $tunnelLog) { Remove-Item $tunnelLog }

# Check SSH available
$sshCmd  = Get-Command ssh -ErrorAction SilentlyContinue
$sshPath = if ($sshCmd) { $sshCmd.Source } else { $null }
if (-not $sshPath) {
    Write-Host "`nWARNING: ssh not found. Install OpenSSH or use on same WiFi only." -ForegroundColor Yellow
    $publicUrl = $null
} else {
    $sshArgs = "-o StrictHostKeyChecking=no -o ServerAliveInterval=20 " +
               "-o LogLevel=QUIET -R 80:localhost:${port} nokey@localhost.run"
    $sshProc = Start-Process ssh -ArgumentList $sshArgs `
        -RedirectStandardOutput $tunnelLog -RedirectStandardError $tunnelLog `
        -NoNewWindow -PassThru

    Write-Host "`nConnecting tunnel..." -ForegroundColor Gray
    $publicUrl = $null
    $deadline  = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline -and -not $publicUrl) {
        Start-Sleep -Milliseconds 400
        if (Test-Path $tunnelLog) {
            $txt = Get-Content $tunnelLog -Raw -ErrorAction SilentlyContinue
            if ($txt -match 'https?://[a-z0-9\-]+\.lhr\.life') {
                $publicUrl = $Matches[0]
            }
        }
    }
    if (-not $publicUrl) {
        Write-Host "Tunnel timed out — falling back to local WiFi only." -ForegroundColor Yellow
    }
}

# ── Print startup info ──────────────────────────────────────────────────────
$localIp = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
    Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║        POWER CONTROL  —  PAIR CODE       ║" -ForegroundColor Magenta
Write-Host "║                                          ║" -ForegroundColor Magenta
Write-Host ("║           " + $pairCode + "                       ║") -ForegroundColor White
Write-Host "║                                          ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""
if ($publicUrl) {
    Write-Host "  Internet URL : $publicUrl" -ForegroundColor Cyan
}
Write-Host "  Local URL    : http://${localIp}:${port}" -ForegroundColor Gray
Write-Host "  Press Ctrl+C to stop." -ForegroundColor DarkGray
Write-Host ""

$openUrl = if ($publicUrl) { $publicUrl } else { "http://${localIp}:${port}" }
Start-Process $openUrl

# ── HTML assets ────────────────────────────────────────────────────────────
$manifest = @'
{"name":"Power Control","short_name":"Power","start_url":"/","display":"standalone",
"background_color":"#0f0f1a","theme_color":"#7c3aed",
"icons":[{"src":"/icon.svg","sizes":"any","type":"image/svg+xml","purpose":"any maskable"}]}
'@

$sw = 'self.addEventListener("fetch",e=>e.respondWith(fetch(e.request)));'

$iconSvg = @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <rect width="512" height="512" rx="120" fill="#0f0f1a"/>
  <circle cx="256" cy="256" r="160" stroke="#7c3aed" stroke-width="28" fill="none"/>
  <line x1="256" y1="96" x2="256" y2="260" stroke="#a78bfa" stroke-width="32" stroke-linecap="round"/>
</svg>
'@

# ── Pair page ───────────────────────────────────────────────────────────────
$pairPage = @'
<!DOCTYPE html><html lang="en"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<meta name="theme-color" content="#7c3aed">
<meta name="apple-mobile-web-app-capable" content="yes">
<link rel="manifest" href="/manifest.json">
<title>Pair Device — Power Control</title>
<style>
  *,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
  :root{--bg:#0f0f1a;--surface:#1a1a2e;--border:#2a2a45;--purple:#7c3aed;--purple2:#a78bfa;--text:#f1f5f9;--muted:#64748b}
  body{background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
    min-height:100dvh;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:2rem;gap:2rem}
  body::before{content:"";position:fixed;top:-20%;left:50%;transform:translateX(-50%);
    width:500px;height:500px;background:radial-gradient(circle,#7c3aed22 0%,transparent 70%);pointer-events:none}
  .ring{width:72px;height:72px;border-radius:50%;border:3px solid var(--purple);display:flex;align-items:center;
    justify-content:center;box-shadow:0 0 24px #7c3aed55;animation:pulse 3s ease-in-out infinite}
  @keyframes pulse{0%,100%{box-shadow:0 0 24px #7c3aed55}50%{box-shadow:0 0 44px #7c3aed99}}
  .ring svg{width:36px;height:36px}
  h1{font-size:1.4rem;font-weight:700}
  p{color:var(--muted);font-size:.88rem;text-align:center;max-width:260px}
  .card{background:var(--surface);border:1.5px solid var(--border);border-radius:20px;
    padding:1.8rem 1.5rem;display:flex;flex-direction:column;gap:1.2rem;align-items:center;width:100%;max-width:320px}
  label{font-size:.8rem;color:var(--muted);letter-spacing:.08em;text-transform:uppercase;align-self:flex-start}
  .digits{display:flex;gap:.5rem;justify-content:center}
  .digits input{width:46px;height:58px;text-align:center;font-size:1.6rem;font-weight:700;
    background:#0f0f1a;color:var(--text);border:1.5px solid var(--border);border-radius:12px;
    outline:none;caret-color:var(--purple2);transition:border-color .2s}
  .digits input:focus{border-color:var(--purple)}
  .err{color:#f87171;font-size:.82rem;min-height:1.1em}
  button{width:100%;padding:.9rem;border-radius:14px;border:none;background:var(--purple);
    color:#fff;font-size:1rem;font-weight:700;cursor:pointer;transition:opacity .15s}
  button:active{opacity:.8}
</style></head><body>
<div class="ring">
  <svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round">
    <path d="M12 2v10" stroke="#a78bfa"/>
    <path d="M18.4 6.6a9 9 0 1 1-12.8 0" stroke="#7c3aed"/>
  </svg>
</div>
<h1>Pair This Device</h1>
<p>Enter the 6-digit code shown on your PC to get access.</p>
<div class="card">
  <label>Pairing Code</label>
  <div class="digits" id="digits">
    <input maxlength="1" inputmode="numeric" pattern="[0-9]">
    <input maxlength="1" inputmode="numeric" pattern="[0-9]">
    <input maxlength="1" inputmode="numeric" pattern="[0-9]">
    <input maxlength="1" inputmode="numeric" pattern="[0-9]">
    <input maxlength="1" inputmode="numeric" pattern="[0-9]">
    <input maxlength="1" inputmode="numeric" pattern="[0-9]">
  </div>
  <p class="err" id="err"></p>
  <button onclick="submit()">Pair Device</button>
</div>
<script>
  const inputs = [...document.querySelectorAll('.digits input')];
  inputs[0].focus();
  inputs.forEach((inp,i)=>{
    inp.addEventListener('input',()=>{
      inp.value = inp.value.replace(/\D/g,'').slice(-1);
      if(inp.value && i<5) inputs[i+1].focus();
    });
    inp.addEventListener('keydown',e=>{
      if(e.key==='Backspace'&&!inp.value&&i>0) inputs[i-1].focus();
    });
    inp.addEventListener('paste',e=>{
      e.preventDefault();
      const d=(e.clipboardData.getData('text').replace(/\D/g,'')).slice(0,6);
      d.split('').forEach((c,j)=>{ if(inputs[j]) inputs[j].value=c; });
      if(d.length<6) inputs[Math.min(d.length,5)].focus();
    });
  });
  async function submit(){
    const code=inputs.map(i=>i.value).join('');
    if(code.length<6){document.getElementById('err').textContent='Enter all 6 digits.';return;}
    const r=await fetch('/pair',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'code='+code});
    const j=await r.json();
    if(j.ok){localStorage.setItem('pc_token',j.token);location.href='/';}
    else{document.getElementById('err').textContent='Wrong code. Try again.';inputs.forEach(i=>i.value='');inputs[0].focus();}
  }
</script></body></html>
'@

# ── Control page ─────────────────────────────────────────────────────────────
$controlPage = @"
<!DOCTYPE html><html lang="en"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<meta name="theme-color" content="#7c3aed">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Power Control">
<link rel="manifest" href="/manifest.json">
<link rel="apple-touch-icon" href="/icon.svg">
<title>Power Control</title>
<style>
  *,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
  :root{--bg:#0f0f1a;--surface:#1a1a2e;--border:#2a2a45;--purple:#7c3aed;--purple2:#a78bfa;
        --red:#dc2626;--red2:#f87171;--blue:#2563eb;--blue2:#60a5fa;--amber:#d97706;--amber2:#fbbf24;
        --text:#f1f5f9;--muted:#64748b}
  body{background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
    min-height:100dvh;display:flex;flex-direction:column;align-items:center;justify-content:center;
    padding:2rem 1.5rem;gap:2.5rem}
  body::before{content:"";position:fixed;top:-20%;left:50%;transform:translateX(-50%);
    width:600px;height:600px;background:radial-gradient(circle,#7c3aed22 0%,transparent 70%);pointer-events:none}
  header{display:flex;flex-direction:column;align-items:center;gap:.75rem;text-align:center}
  .ring{width:72px;height:72px;border-radius:50%;border:3px solid var(--purple);display:flex;align-items:center;
    justify-content:center;box-shadow:0 0 24px #7c3aed55,inset 0 0 12px #7c3aed22;animation:pulse 3s ease-in-out infinite}
  @keyframes pulse{0%,100%{box-shadow:0 0 24px #7c3aed55,inset 0 0 12px #7c3aed22}50%{box-shadow:0 0 44px #7c3aed99,inset 0 0 20px #7c3aed44}}
  .ring svg{width:36px;height:36px}
  h1{font-size:1.4rem;font-weight:700;letter-spacing:-.02em}
  .host{font-size:.8rem;color:var(--muted);letter-spacing:.05em;text-transform:uppercase}
  .grid{display:grid;grid-template-columns:1fr 1fr;gap:1rem;width:100%;max-width:340px}
  .wide{grid-column:1/-1}
  .btn{display:flex;flex-direction:column;align-items:center;gap:.5rem;padding:1.4rem 1rem;
    border:1.5px solid var(--border);border-radius:18px;background:var(--surface);color:var(--text);
    font-size:.9rem;font-weight:600;cursor:pointer;transition:transform .12s,box-shadow .2s,border-color .2s,background .2s;
    -webkit-tap-highlight-color:transparent;user-select:none}
  .btn:active{transform:scale(.94)}
  .btn svg{width:32px;height:32px}
  .btn-shutdown{--c:var(--red);--c2:var(--red2)}
  .btn-sleep{--c:var(--amber);--c2:var(--amber2)}
  .btn-reboot{--c:var(--blue);--c2:var(--blue2)}
  .btn-shutdown,.btn-sleep,.btn-reboot{border-color:color-mix(in srgb,var(--c) 40%,transparent)}
  .btn-shutdown:hover,.btn-sleep:hover,.btn-reboot:hover{
    background:color-mix(in srgb,var(--c) 12%,var(--surface));border-color:var(--c);
    box-shadow:0 0 18px color-mix(in srgb,var(--c) 30%,transparent)}
  .btn svg path,.btn svg circle,.btn svg polyline,.btn svg line{stroke:var(--c2)}
  footer{font-size:.75rem;color:var(--muted);display:flex;gap:1rem;align-items:center}
  .unpair{background:none;border:none;color:var(--muted);font-size:.75rem;cursor:pointer;text-decoration:underline}
  .modal{display:none;position:fixed;inset:0;background:#000a;backdrop-filter:blur(6px);
    align-items:center;justify-content:center;z-index:10}
  .modal.open{display:flex}
  .modal-box{background:var(--surface);border:1.5px solid var(--border);border-radius:20px;
    padding:2rem 1.5rem;max-width:300px;width:90%;text-align:center;display:flex;flex-direction:column;gap:1.2rem}
  .modal-box h2{font-size:1.1rem}
  .modal-box p{font-size:.88rem;color:var(--muted)}
  .modal-actions{display:flex;gap:.75rem}
  .modal-actions button{flex:1;padding:.75rem;border-radius:12px;border:1.5px solid var(--border);
    font-size:.9rem;font-weight:600;cursor:pointer;background:var(--bg);color:var(--text)}
  .modal-actions .confirm{background:var(--confirm-c,var(--purple));border-color:var(--confirm-c,var(--purple));color:#fff}
</style></head><body>
<header>
  <div class="ring">
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
    </svg>Shut Down
  </button>
  <button class="btn btn-sleep" onclick="ask('sleep','Sleep','Put the PC to sleep?','#d97706')">
    <svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>
    </svg>Sleep
  </button>
  <button class="btn btn-reboot" onclick="ask('reboot','Reboot','Really reboot?','#2563eb')">
    <svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <polyline points="23 4 23 10 17 10"/>
      <path d="M20.5 15a9 9 0 1 1-2.1-9.4L23 10"/>
    </svg>Reboot
  </button>
</div>
<footer>
  <span>Connected via Internet</span>
  <button class="unpair" onclick="unpair()">Unpair this device</button>
</footer>
<div class="modal" id="modal">
  <div class="modal-box">
    <h2 id="modal-title"></h2><p id="modal-body"></p>
    <div class="modal-actions">
      <button onclick="closeModal()">Cancel</button>
      <button class="confirm" id="modal-confirm" onclick="doAction()">Confirm</button>
    </div>
  </div>
</div>
<script>
  // Send stored token with every request
  const token = localStorage.getItem('pc_token') || '';
  let pendingCmd = null;

  // Verify token on load
  fetch('/auth', {headers:{'X-Token':token}}).then(r=>{
    if(!r.ok){localStorage.removeItem('pc_token');location.reload();}
  });

  function ask(cmd,title,body,color){
    pendingCmd=cmd;
    document.getElementById('modal-title').textContent=title;
    document.getElementById('modal-body').textContent=body;
    document.getElementById('modal-confirm').style.cssText='background:'+color+';border-color:'+color+';color:#fff';
    document.getElementById('modal').classList.add('open');
  }
  function closeModal(){document.getElementById('modal').classList.remove('open');pendingCmd=null;}
  function doAction(){
    if(!pendingCmd)return;
    const cmd=pendingCmd; closeModal();
    fetch('/action',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded','X-Token':token},
      body:'cmd='+cmd}).then(r=>{if(r.status===403){localStorage.removeItem('pc_token');location.reload();}});
  }
  function unpair(){
    if(!confirm('Unpair this device?'))return;
    fetch('/unpair',{method:'POST',headers:{'X-Token':token}}).then(()=>{
      localStorage.removeItem('pc_token');location.reload();
    });
  }
  document.getElementById('modal').addEventListener('click',e=>{if(e.target===e.currentTarget)closeModal();});
  if('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(()=>{});
</script></body></html>
"@

$doneHtml = @'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#7c3aed">
<link rel="manifest" href="/manifest.json">
<title>Power Control</title>
<style>body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#0f0f1a;
color:#f1f5f9;display:flex;flex-direction:column;align-items:center;justify-content:center;
min-height:100dvh;gap:1rem;padding:2rem;}h1{font-size:1.6rem;}p{color:#64748b;font-size:.9rem;}</style>
</head><body><h1>{0}</h1><p>Command sent to your PC.</p></body></html>
'@

# ── Helpers ─────────────────────────────────────────────────────────────────
function Get-Token($req) {
    return $req.Headers["X-Token"]
}
function New-Token {
    return [System.Guid]::NewGuid().ToString("N")
}
function Send-Html($resp, $body, $code = 200) {
    $resp.StatusCode = $code
    $buf = [System.Text.Encoding]::UTF8.GetBytes($body)
    $resp.ContentType = "text/html; charset=utf-8"
    $resp.ContentLength64 = $buf.Length
    $resp.OutputStream.Write($buf, 0, $buf.Length)
    $resp.Close()
}
function Send-Json($resp, $obj, $code = 200) {
    $resp.StatusCode = $code
    $json = $obj | ConvertTo-Json -Compress
    $buf  = [System.Text.Encoding]::UTF8.GetBytes($json)
    $resp.ContentType = "application/json"
    $resp.ContentLength64 = $buf.Length
    $resp.OutputStream.Write($buf, 0, $buf.Length)
    $resp.Close()
}
function Send-Raw($resp, $body, $type, $code = 200) {
    $resp.StatusCode = $code
    $buf = [System.Text.Encoding]::UTF8.GetBytes($body)
    $resp.ContentType = $type
    $resp.ContentLength64 = $buf.Length
    $resp.OutputStream.Write($buf, 0, $buf.Length)
    $resp.Close()
}

# ── Request loop ─────────────────────────────────────────────────────────────
# NOTE: avoid continue/break inside switch-inside-while (PS 5.1 bug) — use
# a $stopServer flag and plain if/elseif blocks instead.
$stopServer = $false
while ($listener.IsListening -and -not $stopServer) {
    $context = $listener.GetContext()
    $req    = $context.Request
    $resp   = $context.Response
    $path   = $req.Url.LocalPath
    $method = $req.HttpMethod

    # ── Static assets (no auth) ──────────────────────────────────────────
    if ($method -eq "GET" -and $path -eq "/manifest.json") {
        Send-Raw $resp $manifest "application/manifest+json"

    } elseif ($method -eq "GET" -and $path -eq "/icon.svg") {
        Send-Raw $resp $iconSvg "image/svg+xml"

    } elseif ($method -eq "GET" -and $path -eq "/sw.js") {
        Send-Raw $resp $sw "application/javascript"

    } elseif ($method -eq "GET" -and $path -eq "/pair") {
        Send-Html $resp $pairPage

    # ── Pairing ──────────────────────────────────────────────────────────
    } elseif ($method -eq "POST" -and $path -eq "/pair") {
        $reader = New-Object System.IO.StreamReader($req.InputStream)
        $body   = $reader.ReadToEnd()
        $params = @{}
        foreach ($p in $body.Split("&")) {
            $kv = $p.Split("=", 2)
            if ($kv.Count -eq 2) { $params[$kv[0]] = [uri]::UnescapeDataString($kv[1]) }
        }
        if ($params["code"] -eq $pairCode) {
            $tok = New-Token
            Add-Token $tok
            Write-Host "Device paired  token=$($tok.Substring(0,8))..." -ForegroundColor Green
            Send-Json $resp @{ ok = $true; token = $tok }
        } else {
            Send-Json $resp @{ ok = $false } 403
        }

    # ── Auth check ───────────────────────────────────────────────────────
    } elseif ($method -eq "GET" -and $path -eq "/auth") {
        if (Is-ValidToken (Get-Token $req)) { Send-Json $resp @{ ok = $true } }
        else                                { Send-Json $resp @{ ok = $false } 403 }

    # ── Unpair ───────────────────────────────────────────────────────────
    } elseif ($method -eq "POST" -and $path -eq "/unpair") {
        $tok    = Get-Token $req
        $tokens = @(Load-Tokens) | Where-Object { $_ -ne $tok }
        Save-Tokens $tokens
        Write-Host "Device unpaired." -ForegroundColor Yellow
        Send-Json $resp @{ ok = $true }

    } else {
        # ── Require valid token for everything below ──────────────────────
        $tok = Get-Token $req
        if (-not (Is-ValidToken $tok)) {
            if ($method -eq "GET" -and $path -eq "/") {
                $resp.StatusCode = 302
                $resp.Headers.Add("Location", "/pair")
                $resp.Close()
            } else {
                Send-Html $resp "Forbidden" 403
            }

        } elseif ($method -eq "GET" -and $path -eq "/") {
            Send-Html $resp $controlPage

        } elseif ($method -eq "POST" -and $path -eq "/action") {
            $reader = New-Object System.IO.StreamReader($req.InputStream)
            $body   = $reader.ReadToEnd()
            $params = @{}
            foreach ($p in $body.Split("&")) {
                $kv = $p.Split("=", 2)
                if ($kv.Count -eq 2) { $params[$kv[0]] = [uri]::UnescapeDataString($kv[1]) }
            }
            $cmd = $params["cmd"]
            if ($cmd -eq "shutdown") {
                Send-Html $resp ($doneHtml -f "Shutting down...")
                Write-Host "CMD: shutdown" -ForegroundColor Red
                shutdown /s /t 3
                $stopServer = $true
            } elseif ($cmd -eq "sleep") {
                Send-Html $resp ($doneHtml -f "Going to sleep...")
                Write-Host "CMD: sleep" -ForegroundColor Yellow
                rundll32.exe powrprof.dll,SetSuspendState 0,1,0
            } elseif ($cmd -eq "reboot") {
                Send-Html $resp ($doneHtml -f "Rebooting...")
                Write-Host "CMD: reboot" -ForegroundColor Blue
                shutdown /r /t 3
                $stopServer = $true
            } else {
                $resp.StatusCode = 400; $resp.Close()
            }

        } else {
            $resp.StatusCode = 404; $resp.Close()
        }
    }
}

$listener.Stop()
if ($sshProc -and -not $sshProc.HasExited) { $sshProc.Kill() }
