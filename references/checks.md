# Catalogue of checks

Contents:
1. Crash reboots and BSODs
2. GPU: TDR, nvlddmkm / amdkmdag, LiveKernelReports
3. Sleep, Modern Standby, hibernation
4. Dumps and WinDbg
5. Crashing apps
6. Power and CPU
7. Startup, services, scheduled tasks
8. Disk and space
9. Windows Update and Microsoft Store
10. Pop-up windows
11. Background noise not worth fixing

---

## 1. Crash reboots and BSODs

**Where to look:** System log, last 30 days:
- `Kernel-Power 41` — unclean reboot. EventData has `BugcheckCode`: 0 means a hang or power loss without a blue screen, otherwise it is the BSOD code (decimal, convert to hex);
- `WER-SystemErrorReporting 1001` — blue screen with bugcheck parameters and dump path;
- `EventLog 6008` — when the system was last seen running;
- `1074` / `109` — planned reboots (updates, user). Don't confuse them with crashes;
- `volmgr 161` (dump not written) / `162` (written).

**Common codes:**
| Code | Meaning | Where to dig |
|---|---|---|
| 0x116 VIDEO_TDR_FAILURE | GPU hung and reset failed. P3 = 0xC000009A — not enough resources to recover | section 2 |
| 0x117 / 0x141 | GPU hung but recovered (live dump, no BSOD) | section 2 |
| 0x9F DRIVER_POWER_STATE_FAILURE | driver stuck in a power transition | section 3 |
| 0x133 DPC_WATCHDOG_VIOLATION | a driver held a DPC too long | culprit often invisible in a minidump; collect repeats |
| 0x124 WHEA_UNCORRECTABLE_ERROR | hardware error | WHEA-Logger, temperatures, overclock / undervolt |
| 0x50 / 0x1A / 0x3B | memory, driver | dump, memory test |

**Always** match each crash time against the last `Kernel-Power 506/507` (enter / exit Modern Standby) and against what the user was doing. Crashes while idle or asleep strongly point to power management (section 3).

## 2. GPU: TDR, nvlddmkm / amdkmdag, LiveKernelReports

- System log: `nvlddmkm 153` (TDR reset), `nvlddmkm 14` (data may contain `Error status 0x65 while polling for FSP boot complete` — GPU firmware did not start after reset), `Display 4101`; on AMD — `amdkmdag` events.
- `C:\Windows\LiveKernelReports\WATCHDOG\*.dmp` — GPU hangs that ended **without** a BSOD. Visible only with admin rights. Full live dumps of 5–10 GB can appear here too: they can be deleted, the small dump of the same event stays in `WATCHDOG\`.
- Check GPU overclock (MSI Afterburner, vendor tools such as G-Helper / Armoury Crate): Core/Memory offset ≠ 0 is the first suspect for 0x116.
- Registry `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers`: `HwSchMode` (HAGS, 2 = on), `TdrDelay` (default 2 s). `TdrDelay=8` mitigates, it does not cure. Needs a reboot.
- If dumps show **the same point** in the driver across different driver versions, it is not a bug of one build. Next: clean reinstall with DDU → temperatures and power in HWiNFO → warranty.

## 3. Sleep, Modern Standby, hibernation

- `powercfg /a`: if only "Standby (S0 Low Power Idle)" is available, there is no S3, only Modern Standby.
- On laptops with a MUX switch (dGPU-only modes such as ASUS "Ultimate") Modern Standby and waking from it are a frequent cause of 0x116 and 0x9F: the discrete GPU does not come back after being powered down.
- **Fix** (reversible, tested): replace sleep with hibernation.
  ```
  powercfg /change standby-timeout-ac 0 ; powercfg /change standby-timeout-dc 0
  powercfg /change hibernate-timeout-ac 30 ; powercfg /change hibernate-timeout-dc 5
  ```
  Lid, power button and sleep button are often **hidden** in the scheme: aliases like `LIDACTION` return nothing. Use GUIDs (subgroup `4f971e89-eebd-4455-a8de-9e59040e7347`; LID `5ca83367-6e45-459f-a27b-476b1d01c936`, PBUTTON `7648efa3-dd9c-4e3e-b566-50f929386280`, SBUTTON `96996bc0-ad50-47ec-923b-6f41874dd9eb`): first `powercfg -attributes <sub> <guid> -ATTRIB_HIDE` (admin), then `powercfg /setacvalueindex SCHEME_CURRENT <sub> <guid> 2` and `/setdcvalueindex ...` (0 nothing, 1 sleep, 2 hibernate, 3 shut down), then `powercfg /setactive SCHEME_CURRENT`.
  Rollback: the same commands with the old values (record them first).
- "Sleep" in the Start menu still enters Modern Standby — warn the user.
- Fast Startup (`HiberbootEnabled`) is a separate setting: with 0, "Shut down" is a real power-off.

## 4. Dumps and WinDbg

- Minidumps: `C:\Windows\Minidump` (ACL: SYSTEM and Administrators only). Setting: `HKLM\SYSTEM\CurrentControlSet\Control\CrashControl` `CrashDumpEnabled` (3 = small, 7 = automatic).
- Crashes during sleep often leave no dump (`volmgr 161`): the disk was powered down.
- Debugger: `winget install Microsoft.WinDbg`; cdb is at `(Get-AppxPackage Microsoft.WinDbg).InstallLocation\amd64\cdb.exe`.
- Batch analysis: `scripts/analyze-dumps.ps1 -DumpDir <dir> -OutDir <dir>`. Dumps in system folders must first be copied with admin rights and made readable by the current user (`collect-admin.ps1 -CopyDumpsTo <dir>` does that).
- Look at `BUGCHECK_CODE`, `MODULE_NAME`, `SYMBOL_NAME` (module+offset) and `FAILURE_BUCKET_ID`; for live dumps also `PROCESS_NAME`. Matching offsets across dumps are a strong signal.

## 5. Crashing apps

- Application `1000` (Application Error): Properties[0] = exe, [1] = version, [3] = module, [6] = exception code (a **string** like `0000087a`, not a number), [7] = offset. Group by exe+module+code.
- Dumps: `%LOCALAPPDATA%\CrashDumps\<exe>.<pid>.dmp`, analyse with the same `analyze-dumps.ps1`.
- If **different programs** crash with the same stack, look for shared code / library.
  Example: `0x87A` in `dxgi!CDXGIFactory::FinalRelease` after `d2d1!...Brush::Release` — Direct2D objects held in a Rust `thread_local!`/`static` get released during TLS teardown at process exit. Fix: release them explicitly before returning from `main`.
- If the crashing program is the user's own project with an active Claude session (`ListAgents`, if available), hand over the report (stack, dump paths, hypothesis) via `SendMessage` instead of fixing someone else's repository yourself.

## 6. Power and CPU

- `powercfg /q SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN` — default 5%. 80–100% on AC means the CPU never clocks down at idle: extra heat and fan noise. On some CPUs (e.g. Ryzen with boost disabled) `% Processor Performance` stays near 99% even after the fix; verify by power draw and temperature (HWiNFO, vendor tool).
- Vendor tools (G-Helper, Armoury Crate, Lenovo Vantage, etc.) may overlay their own modes on top of the Balanced scheme. Their limits and boost settings are the user's decisions — check the notes.
- `PERFBOOSTMODE` hidden in the scheme usually means a vendor tool manages boost.
- USB selective suspend: relevant if peripherals drop out (macro pads, keyboards).
- `Get-MMAgent` (admin): `MemoryCompression=False` is usually a side effect of disabling SysMain or a "tweaker". With ≥32 GB RAM and low pagefile use it's harmless; with 8–16 GB consider `Enable-MMAgent -MemoryCompression`. Check the notes first — it may be deliberate.

## 7. Startup, services, scheduled tasks

**Startup** (`Win32_StartupCommand` + `...\Explorer\StartupApproved\Run`):
- StartupApproved value: first byte 2 or 6 — enabled, 3 — disabled by the user;
- **dead entries**: present in StartupApproved but in no Run key, or the exe path does not exist (common after uninstalling Razer, Logitech G HUB, etc.). Entries under `HKU\S-1-5-18` and `.DEFAULT` are the same SYSTEM hive — delete there with admin rights;
- entries of installed programs that the user disabled — leave alone.

**Services** — candidates to disable only per the user's use case:
| Service | Can disable if | Keeps working |
|---|---|---|
| XboxService | no Game Pass / Xbox app | Xbox controller over BT (HID driver); keep `XboxGipSvc` |
| Spooler | no printer (only "Microsoft Print to PDF") | "Save as PDF" in browsers |
| WSLService | WSL removed or unused | — |
| DiagTrack | user wants less telemetry | everything |

**Do not touch:** vendor touchpad / hotkey services (e.g. `AsusPTPService`), `AMD External Events Utility` (display / brightness events on hybrid laptops), antivirus services, Bluetooth driver services, `XboxGipSvc`.

**Scheduled tasks:**
- AMD: `\StartCN`, `\StartDVR`, `\AMDRyzenMasterSDKTask` **get re-enabled after every AMD driver update** — recheck each time;
- ASUS: `\ASUS\*` (Armoury Crate leftovers) if the user replaced it with G-Helper;
- tasks whose executable no longer exists.

## 8. Disk and space

Start with free space and health (`Get-PhysicalDisk`, `Get-StorageReliabilityCounter` — admin), TRIM (`fsutil behavior query DisableDeleteNotify` = 0).

| What | Where | Action |
|---|---|---|
| WSL distro | `%LOCALAPPDATA%\wsl\{guid}\ext4.vhdx`, `wsl -l -v` | if unused: `wsl --unregister <name>` (**data is gone**), `wsl --uninstall` |
| Benchmarks | `%APPDATA%\Maxon` + Cinebench in Downloads | delete after testing |
| Live dumps | `C:\Windows\LiveKernelReports\*.dmp` (GBs) | delete the full dump, keep `WATCHDOG\` |
| App dumps | `%LOCALAPPDATA%\CrashDumps` | delete **after** analysis |
| Package manager caches | `uv cache dir`, `~\.cargo\registry`, npm, pip | `uv cache clean`, `npm cache clean --force`, etc. |
| Build artifacts | `<project>\target`, `node_modules` | only with the project owner's consent: a running program may live in `target\release` |
| Old installers | Downloads `*.exe/*.msi` | show the list, the user decides |
| Temp | `%TEMP%`, `C:\Windows\Temp` | files older than a few days; skip locked ones |

**Do not touch:** GPU shader caches (`%LOCALAPPDATA%\NVIDIA`, `AMD\DxCache` — without them games stutter while rebuilding), game caches, browser profiles, `C:\Windows\Installer`, WinSxS by hand (use `DISM /StartComponentCleanup` if anything). VM data (Docker, Claude desktop `Claude-Data`, Hyper-V) only if the user confirms it's not needed.

## 9. Windows Update and Microsoft Store

- History: COM `Microsoft.Update.Session` → `QueryHistory`. Group by title: the same title dozens of times is a loop.
- Example of a harmless loop: `...Microsoft.WindowsAppRuntime.N` — Store keeps trying to install older (often x86) versions while a newer one is installed (AppXDeploymentServer event 735, "higher version already installed"; Properties[0] = package, [1] = attempted, [2] = installed). Dependent apps use the installed one. Don't fix, just explain.
- Pending reboot: `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired`.

## 10. Pop-up windows

1. One-off watch (hours): log new processes with parent and command line, plus new visible top-level windows (EnumWindows). Usual suspects: Electron apps spawning `powershell` without a hidden window, updaters, scheduled tasks.
2. If the window is rare, install the persistent watcher `scripts/winwatch/` (`install.ps1`; log in `%LOCALAPPDATA%\WinWatch\logs`, search with `show.ps1 HH:mm`). Known noisy sources go into `%LOCALAPPDATA%\WinWatch\ignore.txt`, one process name or regex per line.
3. Match the time the user reports against the log. If the window follows a schedule (every hour at xx:43), find who launches it (parent process).

## 11. Background noise not worth fixing
- `DistributedCOM 10010` from GameBar Presence Server — noise.
- `BitLocker-Driver 24641` on every boot — usually harmless on Home editions with device encryption.
- `Firewall 2042 Config Read Failed` — noise.
- Defender "Not running" / passive when a third-party antivirus is installed — normal.
