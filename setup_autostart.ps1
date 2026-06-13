# Registers Power Control Server as a Windows startup task.
# Right-click > Run as Administrator.

$taskName  = "PowerControlServer"
$scriptPath = Join-Path $PSScriptRoot "shutdown_server.ps1"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host ""
    Write-Host "ERROR: Please right-click this script and choose 'Run as Administrator'." -ForegroundColor Red
    Write-Host ""
    pause; exit 1
}

# Remove any previous registration
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action   = New-ScheduledTaskAction `
    -Execute  "powershell.exe" `
    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -NonInteractive -File `"$scriptPath`""

$trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 2) `
    -StartWhenAvailable

$principal = New-ScheduledTaskPrincipal `
    -UserId   $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName  $taskName `
    -Action    $action `
    -Trigger   $trigger `
    -Settings  $settings `
    -Principal $principal `
    -Force | Out-Null

Write-Host ""
Write-Host "Power Control Server will now start automatically at every login." -ForegroundColor Green
Write-Host ""
Write-Host "  Task   : $taskName" -ForegroundColor Cyan
Write-Host "  Script : $scriptPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "To start it right now (without rebooting), run:" -ForegroundColor Yellow
Write-Host "  Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor White
Write-Host ""
Write-Host "To pair a new device: check pair_code.txt in this folder" -ForegroundColor DarkGray
Write-Host "(it is written fresh each time the server starts)." -ForegroundColor DarkGray
Write-Host ""
Write-Host "To remove auto-start: run remove_autostart.ps1 as Administrator." -ForegroundColor DarkGray
Write-Host ""
pause
