# Start WinWatch at logon (no window) and start it right now.
$script = Join-Path $PSScriptRoot 'winwatch.ps1'
$action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'WinWatch' -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName 'WinWatch'
"WinWatch installed and running. Logs: $env:LOCALAPPDATA\WinWatch\logs ; ignore list: $env:LOCALAPPDATA\WinWatch\ignore.txt"
