# Part of the audit that needs admin rights. Read-only (except the optional dump copy).
# Run: Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','"collect-admin.ps1"','-OutFile','"C:\path\audit-admin.txt"'
# -CopyDumpsTo <dir>: copy minidumps and WATCHDOG dumps there and grant the user access (for analyze-dumps.ps1).
param([Parameter(Mandatory)] [string]$OutFile, [string]$CopyDumpsTo, [string]$User = $env:USERNAME)
$ErrorActionPreference = 'SilentlyContinue'
$sb = New-Object System.Text.StringBuilder
function W($s = '') { [void]$sb.AppendLine([string]$s) }
function Section($s) { W; W "==================== $s ====================" }
function T($obj) { W (($obj | Format-Table -AutoSize -Wrap | Out-String -Width 220).TrimEnd()) }
$win = $env:SystemRoot

Section "BSOD minidumps ($win\Minidump, admin only)"
$md = Get-Item "$win\Minidump" -Force
W ("Folder modified: {0}  (if equal to the newest dump time, nothing was deleted)" -f $md.LastWriteTime)
T (Get-ChildItem "$win\Minidump" -Force -File | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,1)}}, LastWriteTime)
T (Get-Item "$win\MEMORY.DMP" -Force | Select-Object Name, @{n='GB';e={[math]::Round($_.Length/1GB,1)}}, LastWriteTime)
T (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' | Select-Object CrashDumpEnabled, MinidumpDir, AutoReboot)

Section 'LiveKernelReports (GPU/driver hangs without BSOD)'
T (Get-ChildItem "$win\LiveKernelReports" -Recurse -Force -File | Select-Object @{n='File';e={$_.FullName.Replace("$win\LiveKernelReports\",'')}}, @{n='MB';e={[math]::Round($_.Length/1MB,1)}}, LastWriteTime)

Section 'WER (system reports with dumps)'
T (Get-ChildItem "$env:ProgramData\Microsoft\Windows\WER" -Recurse -Force -File | Where-Object Extension -match 'dmp' | Select-Object FullName, @{n='MB';e={[int]($_.Length/1MB)}}, LastWriteTime)

Section 'SMART / disk reliability'
T (Get-PhysicalDisk | Get-StorageReliabilityCounter | Select-Object DeviceId, Temperature, TemperatureMax, Wear, ReadErrorsTotal, WriteErrorsTotal, PowerOnHours)

Section 'Memory: compression, prefetch'
T (Get-MMAgent | Select-Object MemoryCompression, PageCombining, ApplicationPreLaunch, OperationAPI)

Section 'Enabled virtualization features'
Get-WindowsOptionalFeature -Online | Where-Object { $_.State -eq 'Enabled' -and $_.FeatureName -match 'Hyper|VirtualMachine|Subsystem|Sandbox|Containers' } | ForEach-Object { W $_.FeatureName }

Section 'Shadow copies'
W ((vssadmin list shadowstorage) -join "`n")

Section 'Boot time (Diagnostics-Performance 100) and slowdowns (101-110)'
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Diagnostics-Performance/Operational'; Id=100,101,102,103,106,109; StartTime=(Get-Date).AddDays(-30)} -MaxEvents 20 |
  ForEach-Object { $m = ($_.Message -replace '\s+', ' ').Trim(); W ("{0:yyyy-MM-dd HH:mm} id{1} {2}" -f $_.TimeCreated, $_.Id, $m.Substring(0, [Math]::Min(170, $m.Length))) }

if ($CopyDumpsTo) {
  Section "Copying dumps to $CopyDumpsTo"
  New-Item -ItemType Directory -Force "$CopyDumpsTo\Minidump", "$CopyDumpsTo\Watchdog" | Out-Null
  Copy-Item "$win\Minidump\*.dmp" "$CopyDumpsTo\Minidump" -Force
  Copy-Item "$win\LiveKernelReports\WATCHDOG\*.dmp" "$CopyDumpsTo\Watchdog" -Force
  icacls $CopyDumpsTo /grant "${User}:(OI)(CI)F" /T | Out-Null
  T (Get-ChildItem $CopyDumpsTo -Recurse -File | Select-Object FullName, @{n='MB';e={[math]::Round($_.Length/1MB,1)}})
}

[IO.File]::WriteAllText($OutFile, $sb.ToString(), (New-Object Text.UTF8Encoding $true))
