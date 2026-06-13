#!/usr/bin/env python3
"""
WiFi Shutdown Server
Run this on the computer you want to shut down.
Access http://<your-ip>:8765 from any device on the same network.
"""

import http.server
import os
import platform
import socket
import sys

PORT = 8765
TOKEN = "shutdown"  # Change this to something secret if desired

HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Remote Shutdown</title>
  <style>
    body {{
      font-family: sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      margin: 0;
      background: #1a1a2e;
      color: #eee;
    }}
    h1 {{ font-size: 1.5rem; margin-bottom: 2rem; }}
    button {{
      padding: 1rem 2.5rem;
      font-size: 1.2rem;
      border: none;
      border-radius: 8px;
      cursor: pointer;
      margin: 0.5rem;
    }}
    .shutdown {{ background: #e63946; color: white; }}
    .reboot   {{ background: #457b9d; color: white; }}
    button:active {{ opacity: 0.8; }}
    .host {{ font-size: 0.85rem; opacity: 0.5; margin-top: 2rem; }}
  </style>
</head>
<body>
  <h1>&#128187; Remote Power Control</h1>
  <form method="POST" action="/action"
        onsubmit="return confirm('Are you sure?')">
    <input type="hidden" name="token" value="{token}">
    <button class="shutdown" name="cmd" value="shutdown">&#x23FB; Shut Down</button><br><br>
    <button class="reboot"   name="cmd" value="reboot">&#x21BA; Reboot</button>
  </form>
  <p class="host">Connected to {host}</p>
</body>
</html>
"""

DONE_HTML = """<!DOCTYPE html>
<html><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>body{{font-family:sans-serif;text-align:center;padding:3rem;
background:#1a1a2e;color:#eee;}}</style></head>
<body><h1>{msg}</h1><p>Command sent.</p></body></html>"""


def shutdown_command():
    system = platform.system()
    if system == "Windows":
        return "shutdown /s /t 3"
    elif system == "Darwin":
        return "sudo shutdown -h +0"
    else:
        return "sudo shutdown -h now"


def reboot_command():
    system = platform.system()
    if system == "Windows":
        return "shutdown /r /t 3"
    elif system == "Darwin":
        return "sudo shutdown -r +0"
    else:
        return "sudo reboot"


def local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[{self.client_address[0]}] {fmt % args}")

    def do_GET(self):
        if self.path != "/":
            self.send_response(404)
            self.end_headers()
            return
        body = HTML.format(token=TOKEN, host=socket.gethostname()).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/action":
            self.send_response(404)
            self.end_headers()
            return

        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length).decode()
        params = {}
        for part in raw.split("&"):
            if "=" in part:
                k, v = part.split("=", 1)
                params[k] = v

        if params.get("token") != TOKEN:
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"Forbidden")
            return

        cmd_key = params.get("cmd")
        if cmd_key == "shutdown":
            msg = "Shutting down..."
            cmd = shutdown_command()
        elif cmd_key == "reboot":
            msg = "Rebooting..."
            cmd = reboot_command()
        else:
            self.send_response(400)
            self.end_headers()
            return

        body = DONE_HTML.format(msg=msg).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)
        self.wfile.flush()

        print(f"Executing: {cmd}")
        os.system(cmd)


if __name__ == "__main__":
    ip = local_ip()
    print(f"Starting shutdown server on port {PORT}")
    print(f"Open this on your phone/tablet: http://{ip}:{PORT}")
    print("Press Ctrl+C to stop.\n")
    try:
        server = http.server.HTTPServer(("0.0.0.0", PORT), Handler)
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
        sys.exit(0)
