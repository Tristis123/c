# Removes the Power Control Server startup task.
# Right-click > Run as Administrator.

$taskName = "PowerControlServer"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host ""
    Write-Host "ERROR: Please right-click this script and choose 'Run as Administrator'." -ForegroundColor Red
    Write-Host ""
    pause; exit 1
}

Stop-ScheduledTask  -TaskName $taskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item (Join-Path $PSScriptRoot "pair_code.txt") -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Auto-start removed. The server will no longer start at login." -ForegroundColor Yellow
Write-Host "You can still launch it manually with start.bat." -ForegroundColor DarkGray
Write-Host ""
pause
