# Remove WinWatch: stop it and delete the task. Logs stay in %LOCALAPPDATA%\WinWatch\logs.
Stop-ScheduledTask -TaskName 'WinWatch' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'WinWatch' -Confirm:$false -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -match 'winwatch\.ps1' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
"WinWatch removed."
