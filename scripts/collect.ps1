# Read-only Windows audit data collection, no admin rights needed. Locale-independent parsing.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File collect.ps1 -OutFile C:\path\audit.txt [-Days 30]
param([Parameter(Mandatory)] [string]$OutFile, [int]$Days = 30)
$ErrorActionPreference = 'SilentlyContinue'
$since = (Get-Date).AddDays(-$Days)
$sb = New-Object System.Text.StringBuilder
function W($s = '') { [void]$sb.AppendLine([string]$s) }
function Section($s) { W; W "==================== $s ====================" }
function T($obj) { W (($obj | Format-Table -AutoSize -Wrap | Out-String -Width 220).TrimEnd()) }
function Short($s, $n = 160) { $s = ($s -replace '\s+', ' ').Trim(); if ($s.Length -gt $n) { $s.Substring(0, $n) } else { $s } }
function FolderGB($p) { (Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1GB }

Section 'System'
$cs = Get-CimInstance Win32_ComputerSystem; $os = Get-CimInstance Win32_OperatingSystem; $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
W ("{0} {1} | {2} | RAM {3:N1} GB, free {4:N1} GB" -f $cs.Manufacturer, $cs.Model, $cpu.Name.Trim(), ($os.TotalVisibleMemorySize/1MB), ($os.FreePhysicalMemory/1MB))
W ("{0} build {1} | locale {2} | last boot: {3}" -f $os.Caption, $os.BuildNumber, (Get-Culture).Name, $os.LastBootUpTime)
T (Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate)

Section "Unclean reboots (Kernel-Power 41) and sleep state before them, $Days days"
foreach ($e in Get-WinEvent -FilterHashtable @{LogName='System'; Id=41; StartTime=$since}) {
  $d = @{}; ([xml]$e.ToXml()).Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }
  $ms = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=506,507; StartTime=$e.TimeCreated.AddDays(-2); EndTime=$e.TimeCreated.AddSeconds(-15)} -MaxEvents 1
  $st = if ($ms.Id -eq 506) { 'ASLEEP (Modern Standby)' } elseif ($ms) { 'awake' } else { '?' }
  W ("{0:yyyy-MM-dd HH:mm}  bugcheck=0x{1:X}  last transition: {2} {3:MM-dd HH:mm:ss} -> {4}" -f $e.TimeCreated, [int64]$d.BugcheckCode, $ms.Id, $ms.TimeCreated, $st)
}

Section 'BSOD (WER 1001), planned reboots (1074), 6008, dump status (volmgr 161/162)'
Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001,1074,6008; StartTime=$since} | ForEach-Object { W ("{0:yyyy-MM-dd HH:mm} {1,-5} {2}" -f $_.TimeCreated, $_.Id, (Short $_.Message 200)) }
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='volmgr'; StartTime=$since} | Group-Object Id | ForEach-Object { W ("volmgr {0}: {1} times" -f $_.Name, $_.Count) }

Section 'GPU: nvlddmkm / amdkmdag / Display (TDR)'
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='nvlddmkm','Display','amdkmdag'; StartTime=$since} | Select-Object -First 40 | ForEach-Object {
  W ("{0:yyyy-MM-dd HH:mm:ss} {1} {2} {3}" -f $_.TimeCreated, $_.ProviderName, $_.Id, (Short (($_.Properties | ForEach-Object { $_.Value }) -join ' | ') 160)) }
$gd = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
W ("HwSchMode(HAGS)={0}  TdrDelay={1}" -f $gd.HwSchMode, $gd.TdrDelay)

Section 'Hardware errors (WHEA) and problem devices'
$whea = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$since}
W ("WHEA events: {0}" -f @($whea).Count); $whea | Select-Object -First 5 | ForEach-Object { W ("{0:yyyy-MM-dd HH:mm} {1}" -f $_.TimeCreated, (Short $_.Message)) }
T (Get-PnpDevice -PresentOnly | Where-Object Status -ne 'OK' | Select-Object Status, Class, FriendlyName)

Section 'System log errors by source (14 days)'
T (Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-14)} | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 20 Count, Name, @{n='Example';e={Short $_.Group[0].Message 110}})

Section 'App crashes (Application 1000) and CrashDumps'
Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=$since} | ForEach-Object { $p = $_.Properties
  [pscustomobject]@{App=$p[0].Value; Ver=$p[1].Value; Module=$p[3].Value; Exc="0x$($p[6].Value)"; Offset="0x$($p[7].Value)"; Time=$_.TimeCreated} } |
  Group-Object App, Module, Exc | Sort-Object Count -Descending | ForEach-Object { W ("{0,3}x {1}  last {2:yyyy-MM-dd HH:mm}, version {3}, offset {4}" -f $_.Count, $_.Name, $_.Group[0].Time, $_.Group[0].Ver, $_.Group[0].Offset) }
T (Get-ChildItem "$env:LOCALAPPDATA\CrashDumps" -Filter *.dmp | Select-Object Name, @{n='MB';e={[int]($_.Length/1MB)}}, LastWriteTime)

Section 'Power'
W (powercfg /getactivescheme)
W ((powercfg /a) -join "`n")
# The last two hex numbers in "powercfg /q" output are the current AC and DC values (labels are localized, numbers are not).
function PQ($sub, $set) {
  $v = [regex]::Matches((powercfg /q SCHEME_CURRENT $sub $set | Out-String), '0x[0-9a-fA-F]{8}') | ForEach-Object { [Convert]::ToInt64($_.Value, 16) }
  if (@($v).Count -ge 2) { @{AC=$v[-2]; DC=$v[-1]} } }
function Fmt($r, $unit) { if (-not $r) { 'hidden in scheme' } elseif ($unit -eq 'min') { 'AC {0} min, DC {1} min (0 = never)' -f ($r.AC/60), ($r.DC/60) } else { "AC $($r.AC)$unit, DC $($r.DC)$unit" } }
W ("Sleep after:      " + (Fmt (PQ SUB_SLEEP STANDBYIDLE) 'min'))
W ("Hibernate after:  " + (Fmt (PQ SUB_SLEEP HIBERNATEIDLE) 'min'))
W ("Display off:      " + (Fmt (PQ SUB_VIDEO VIDEOIDLE) 'min'))
W ("Min CPU state:    " + (Fmt (PQ SUB_PROCESSOR PROCTHROTTLEMIN) '%'))
W ("Max CPU state:    " + (Fmt (PQ SUB_PROCESSOR PROCTHROTTLEMAX) '%'))
$bm = PQ SUB_PROCESSOR PERFBOOSTMODE; W ("Boost mode:       " + $(if ($bm) { "AC $($bm.AC), DC $($bm.DC) (0 off, 1 on, 2 aggressive)" } else { 'hidden in scheme (usually managed by a vendor tool)' }))
$btn = '4f971e89-eebd-4455-a8de-9e59040e7347'
$buttons = [ordered]@{Lid='5ca83367-6e45-459f-a27b-476b1d01c936'; PowerButton='7648efa3-dd9c-4e3e-b566-50f929386280'; SleepButton='96996bc0-ad50-47ec-923b-6f41874dd9eb'}
foreach ($k in $buttons.GetEnumerator()) {
  $r = PQ $btn $k.Value; W ("{0,-17} {1}" -f "$($k.Key):", $(if ($r) { "AC $($r.AC), DC $($r.DC) (0 nothing, 1 sleep, 2 hibernate, 3 shut down)" } else { 'hidden in scheme' })) }
W ("Fast Startup (HiberbootEnabled): " + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power').HiberbootEnabled)
$perf = 1..3 | ForEach-Object { Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'"; Start-Sleep -Milliseconds 700 }
W ("CPU now: % Processor Performance {0:N0}, % Processor Time {1:N0}, frequency {2:N0} MHz" -f ($perf | Measure-Object PercentProcessorPerformance -Average).Average, ($perf | Measure-Object PercentProcessorTime -Average).Average, ($perf | Measure-Object ProcessorFrequency -Average).Average)

Section 'Startup'
T (Get-CimInstance Win32_StartupCommand | Select-Object Name, @{n='Command';e={Short $_.Command 90}}, @{n='Location';e={$_.Location -replace 'SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\',''}})
W '-- StartupApproved\Run (HKCU): state and whether a Run entry exists'
$sa = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$run = foreach ($k in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'Registry::HKEY_USERS\S-1-5-18\SOFTWARE\Microsoft\Windows\CurrentVersion\Run') { (Get-ItemProperty $k).PSObject.Properties.Name }
foreach ($n in (Get-Item $sa).Property) { $v = (Get-ItemProperty $sa).$n
  W ("{0,-55} {1,-4} {2}" -f $n, $(if ($v[0] -in 2, 6) { 'ON' } else { 'off' }), $(if ($run -contains $n) { '' } else { '<- in no Run key (program removed, or autostart disabled inside the program)' })) }
W '-- Run entries pointing to a missing exe'
Get-CimInstance Win32_StartupCommand | ForEach-Object { if ($_.Command -match '^"?([A-Za-z]:\\[^"]+?\.exe)') { if (-not (Test-Path $Matches[1])) { W ("DEAD: {0} -> {1} ({2})" -f $_.Name, $Matches[1], $_.Location) } } }

Section 'Third-party services (Auto)'
T (Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' -and $_.PathName -notmatch '\\Windows\\system32\\svchost' -and $_.PathName -notmatch 'Microsoft' } | Sort-Object Name | Select-Object Name, State, @{n='Path';e={Short $_.PathName 90}})

Section 'Third-party scheduled tasks (enabled)'
Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notmatch '^\\Microsoft\\' } | ForEach-Object {
  $exe = ($_.Actions | Select-Object -First 1).Execute -replace '"', ''
  $miss = if ($exe -match '^[A-Za-z]:\\' -and -not (Test-Path ([Environment]::ExpandEnvironmentVariables($exe)))) { '  <- exe NOT FOUND' } else { '' }
  $flag = if ($_.TaskName -match '^(StartCN|StartDVR|AMDRyzenMasterSDKTask)$' -or $_.TaskPath -match '\\ASUS\\') { '  <- AMD/ASUS, often unwanted' } else { '' }
  W ("{0,-70} {1}{2}{3}" -f (Short ($_.TaskPath + $_.TaskName) 70), (Short $exe 70), $miss, $flag) }

Section 'Disk'
T (Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, HealthStatus, @{n='GB';e={[int]($_.Size/1GB)}})
T (Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter, FileSystemLabel, @{n='SizeGB';e={[int]($_.Size/1GB)}}, @{n='FreeGB';e={[int]($_.SizeRemaining/1GB)}})
W ((fsutil behavior query DisableDeleteNotify) -join "`n")

Section 'Large space consumers'
$cands = "$env:LOCALAPPDATA\wsl", "$env:LOCALAPPDATA\Docker", "$env:LOCALAPPDATA\NVIDIA", "$env:LOCALAPPDATA\AMD", "$env:LOCALAPPDATA\Claude-Data", "$env:LOCALAPPDATA\uv", "$env:APPDATA\Maxon",
         "$env:USERPROFILE\.cargo", "$env:LOCALAPPDATA\npm-cache", "$env:LOCALAPPDATA\pip", "$env:LOCALAPPDATA\CrashDumps", $env:TEMP, 'C:\Windows\Temp',
         'C:\Windows\SoftwareDistribution\Download', "$env:USERPROFILE\Downloads"
foreach ($p in $cands) { if (Test-Path $p) { $g = FolderGB $p; if ($g -gt 0.2) { W ("{0,-60} {1,7:N1} GB" -f $p, $g) } } }
W '-- AppData (Local/Roaming) folders > 1 GB'
foreach ($root in $env:LOCALAPPDATA, $env:APPDATA) { foreach ($d in Get-ChildItem $root -Directory -Force | Where-Object { $_.Attributes -notmatch 'ReparsePoint' }) { $g = FolderGB $d.FullName; if ($g -gt 1) { W ("{0,-60} {1,7:N1} GB" -f $d.FullName, $g) } } }
if (Get-Command wsl.exe) { W '-- WSL'; W (((wsl --list --verbose) 2>&1 | ForEach-Object { $_ -replace "`0", '' } | Where-Object { $_.Trim() }) -join "`n") }
Get-ChildItem "$env:LOCALAPPDATA\wsl", "$env:LOCALAPPDATA\Packages" -Recurse -Filter ext4.vhdx -Force | ForEach-Object { W ("{0}  {1:N1} GB  modified {2:yyyy-MM-dd}" -f $_.FullName, ($_.Length/1GB), $_.LastWriteTime) }
W '-- Downloads, top 15'
Get-ChildItem "$env:USERPROFILE\Downloads" -Force | ForEach-Object { [pscustomobject]@{Name=$_.Name; MB=[int]($(if ($_.PSIsContainer) { (FolderGB $_.FullName) * 1024 } else { $_.Length / 1MB })); Date=$_.LastWriteTime.ToString('yyyy-MM-dd')} } |
  Sort-Object MB -Descending | Select-Object -First 15 | ForEach-Object { W ("{0,7} MB  {1}  {2}" -f $_.MB, $_.Date, $_.Name) }

Section 'Memory: top processes'
T (Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 Name, Id, @{n='MB';e={[int]($_.WorkingSet64/1MB)}}, @{n='CPU_s';e={[int]$_.CPU}})
T (Get-CimInstance Win32_PageFileUsage | Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage)

Section 'Gaming and graphics, antivirus, background services'
$r = { param($p, $n) try { (Get-ItemProperty $p -Name $n -ErrorAction Stop).$n } catch { '<unset>' } }
W ("GameMode={0} GameDVR={1} Transparency={2} DXUserGlobal={3}" -f (& $r 'HKCU:\Software\Microsoft\GameBar' AutoGameModeEnabled), (& $r 'HKCU:\System\GameConfigStore' GameDVR_Enabled),
   (& $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' EnableTransparency), (& $r 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' DirectXUserGlobalSettings))
$dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard
W ("VBS status={0} services={1}" -f $dg.VirtualizationBasedSecurityStatus, ($dg.SecurityServicesRunning -join ','))
$mp = Get-MpComputerStatus; W ("Defender: {0}, RTP={1}" -f $mp.AMRunningMode, $mp.RealTimeProtectionEnabled)
W ("Antivirus products: " + ((Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct | ForEach-Object displayName) -join ', '))
foreach ($s in 'WSearch', 'SysMain', 'Spooler', 'XboxService', 'WSLService', 'DiagTrack') { $o = Get-Service $s; if ($o) { W ("{0,-12} {1,-8} {2}" -f $s, $o.Status, $o.StartType) } }

Section 'Windows Update / Store: repeated installs'
$h = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher(); $n = $h.GetTotalHistoryCount()
if ($n) { $h.QueryHistory(0, [Math]::Min($n, 500)) | Where-Object { $_.Date -gt $since } | Group-Object Title | Where-Object Count -gt 3 | Sort-Object Count -Descending |
  ForEach-Object { W ("{0,4}x  {1}" -f $_.Count, $_.Name) } }
W ("Reboot pending: " + (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'))
# AppX 735 "higher version already installed": Properties[0] = package, [1] = attempted version, [2] = installed version.
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-AppXDeploymentServer/Operational'; Id=735; StartTime=$since} | ForEach-Object { $p = $_.Properties; "{0} {1} < {2}" -f $p[0].Value, $p[1].Value, $p[2].Value } |
  Group-Object | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object { W ("AppX 735 {0,3}x {1}" -f $_.Count, $_.Name) }

[IO.File]::WriteAllText($OutFile, $sb.ToString(), (New-Object Text.UTF8Encoding $true))
"Done: $OutFile"
