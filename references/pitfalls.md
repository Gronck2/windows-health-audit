# Gotchas

Each item here is a real mistake that broke a result or wasted time.

## Permissions and visibility
- `C:\Windows\Minidump`, `LiveKernelReports`, `ProgramData\Microsoft\Windows\WER`, `Get-MMAgent`, `Get-WindowsOptionalFeature`, `Get-AppxPackage -AllUsers`, `vssadmin` and the Diagnostics-Performance log are either empty or Access denied without admin. "Folder is empty" ≠ "there are no files".
- A folder's `LastWriteTime` changes when a file is deleted from it. If it equals the write time of the newest dump, nothing was deleted.
- Elevation: `Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile','-Command',$cmd`. The elevated process's output does not come back — write it to a file (`*> 'path'`) and read it afterwards.

## Locale
- Windows output is localized: `powercfg /q` labels ("Current AC Power Setting Index"), event `Message` text, `Get-Counter` paths (`\Processor Information(...)` has a different name on non-English systems). Parse values, not labels: hex numbers in powercfg output (the last two are AC and DC), event `.Properties` / XML, CIM classes such as `Win32_PerfFormattedData_Counters_ProcessorInformation`.

## PowerShell 5.1
- A `.ps1` with non-ASCII text and no BOM is read as ANSI → garbled. Save with UTF-8 BOM: `[IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding $true))`.
- No `&&`, `||`, `??`, `?:`.
- `2>&1` on native programs turns stderr into ErrorRecords and sets a failure status even on success.
- `h` is a built-in alias of `Get-History` and shadows a function named `H`.
- `Get-WinEvent` → `.Properties[i].Value` is often a string (exception code `0000087a`); don't cast with `[uint32]`.
- `wsl.exe` output contains NUL characters: `-replace "`0",""`.
- `Select-Object` with numeric property names (`01`, `2048` in StorageSense) fails — read via `.PSObject.Properties`.

## Network
- `Set-NetAdapterAdvancedProperty -DisplayValue '<text>'` is fragile on localized drivers: strings differ in small details (`5ГГц` vs `5 ГГц`), and table output wraps lines and hides spaces. Set values with `-RegistryValue` (indexes from `ValidRegistryValues`).
- `netsh wlan show interfaces` doesn't show channel/signal without Windows location services on and admin rights. Use `Get-NetAdapter` → `LinkSpeed` instead.
- `Get-NetAdapterPowerManagement` on MT7922 fails with "A device attached to the system is not functioning" (Win32 error 31) — that does not mean the adapter is broken.

## Git Bash next to PowerShell
- `sed` with `C:\test` in the replacement turns `\t` into a tab. Use an editor tool or forward slashes for paths.
- Commands the user runs via `! ` in Claude Code go through bash: give paths with forward slashes (`"C:/path/..."`), otherwise backslashes may be lost. Question marks instead of non-Latin text in `!` output are a console encoding issue, not an error.

## Task Scheduler and background processes
- A task like `conhost.exe --headless powershell -File x.ps1`: `Stop-ScheduledTask` kills only conhost, the child powershell **keeps running**. Stop by command line (`Win32_Process` → `CommandLine -match 'x\.ps1'` → `Stop-Process`), then `Start-ScheduledTask`, and verify exactly one instance runs.
- A singleton script with a mutex: if the old instance is alive, the new one exits silently. The task shows Ready while the old version keeps writing the log.
- `RestartCount` in a task: a killed process counts as a failure, and the task may restart a minute later. Use `Stop-ScheduledTask` to stop and `Unregister-ScheduledTask` to remove.
- Creating autostart (Register-ScheduledTask, Run keys) may be blocked by the agent harness as persistence. Don't work around it — give the user a command to run.

## cdb / WinDbg
- cdb output redirected with `*>` is UTF-16LE. Convert before grep: `iconv -f UTF-16LE -t UTF-8`, or read with PowerShell `Get-Content`.
- `.ecxr; kc` may print nothing in batch mode. `!analyze -v` and parsing the `STACK_TEXT:` block is more reliable.
- First run downloads symbols (minutes). Cache: `srv*C:\Symbols*https://msdl.microsoft.com/download/symbols`; for the user's own Rust/C++ projects add the folder with their PDBs.

## Counters and verifying effect
- `% Processor Performance` on AMD with boost disabled sits near 99% even at idle. Don't claim an effect from it — check power draw and temperature.
- `Get-Item C:\hiberfil.sys` / `pagefile.sys` without admin reports 0 bytes.

## Laptop vendor tools
- If the user replaced Armoury Crate with G-Helper, don't re-enable ASUS services (`ArmouryCrate*`, `AsusAppService`, etc.). ASUS installers (System Control Interface) may turn them back on — recheck.
- Vendor touchpad services (`AsusPTPService` and similar) — don't touch.
- Switching the GPU mode on MUX laptops (Eco/Standard/Ultimate) needs a reboot; don't offer fixes that require frequent mode switching as the main solution.
