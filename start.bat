@echo off
:: Add firewall rule for port 8765 (silently, only if not already present)
netsh advfirewall firewall show rule name="RemoteShutdown" >nul 2>&1
if %errorlevel% neq 0 (
    netsh advfirewall firewall add rule name="RemoteShutdown" dir=in action=allow protocol=TCP localport=8765 >nul
    echo Firewall rule added for port 8765.
)
powershell -ExecutionPolicy Bypass -File "%~dp0shutdown_server.ps1"
