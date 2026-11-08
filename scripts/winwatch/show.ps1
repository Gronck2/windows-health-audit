# Show WinWatch entries around a time: .\show.ps1 14:15 [-Date 2026-01-31] [-Minutes 10]
# Without arguments: the last 40 entries of today.
param([string]$Time, [datetime]$Date = (Get-Date), [int]$Minutes = 10)
$file = Join-Path $env:LOCALAPPDATA ('WinWatch\logs\{0:yyyy-MM-dd}.log' -f $Date)
if (-not (Test-Path $file)) { "No log: $file"; exit }
$lines = Get-Content $file -Encoding utf8
if (-not $Time) { $lines | Select-Object -Last 40; exit }
$t = [datetime]::ParseExact($Time, 'H:mm', $null).TimeOfDay
$lines | Where-Object {
  $ts = [timespan]::Zero
  [timespan]::TryParse($_.Substring(0, [Math]::Min(8, $_.Length)), [ref]$ts) -and [Math]::Abs(($ts - $t).TotalMinutes) -le $Minutes
}
