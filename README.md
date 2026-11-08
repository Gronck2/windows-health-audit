# windows-health-audit

A [Claude Code](https://claude.com/claude-code) skill for a read-only health and optimization audit of a Windows 10/11 PC or laptop.

Claude collects data with bundled PowerShell scripts, finds causes (not just symptoms), and presents a report with numbered candidate changes — each with benefit, risk and rollback. Nothing is changed until you pick what to apply.

## What it checks

- Spontaneous reboots and BSODs: Kernel-Power 41, bugcheck codes, correlation with Modern Standby sleep/wake
- GPU hangs (TDR): nvlddmkm / amdkmdag events, LiveKernelReports, HAGS / TdrDelay
- Crash dumps: batch analysis with WinDbg (`cdb !analyze -v`)
- Crashing apps: Application 1000 events grouped by app / module / exception, CrashDumps
- Power: sleep vs hibernate, lid / button actions (including hidden settings), minimum CPU state, Fast Startup
- Startup entries (including dead ones), third-party services, scheduled tasks with missing executables, vendor tasks that re-enable themselves
- Disk: health, TRIM, space hogs (WSL vhdx, caches, dumps, benchmarks, Downloads)
- Windows Update / Microsoft Store install loops
- Mystery pop-up windows: optional persistent watcher (WinWatch) that logs every new window and console with the process that launched it

## Install

Clone into your personal skills folder (available in every project):

```powershell
git clone https://github.com/Gronck2/windows-health-audit "$env:USERPROFILE\.claude\skills\windows-health-audit"
```

or into a project: `<project>\.claude\skills\windows-health-audit`.

Then just ask Claude Code something like *"why does my PC reboot at night?"*, *"check the system log"* or *"what can we optimize in Windows?"* — the skill triggers on its own. Works in any language; the report follows yours.

## Requirements

- Windows 10 / 11, Windows PowerShell 5.1 (built in). Any Windows display language.
- Admin rights for part of the data (one UAC prompt): minidumps, LiveKernelReports, SMART.
- Optional: WinDbg for dump analysis — `winget install Microsoft.WinDbg`.
- Claude Code running on that Windows machine. The skill does not work on claude.ai web or on macOS / Linux, because the scripts must run locally.

## Scripts

| Script | What it does |
|---|---|
| `scripts/collect.ps1 -OutFile <file>` | Everything that doesn't need admin (~40 s) |
| `scripts/collect-admin.ps1 -OutFile <file> [-CopyDumpsTo <dir>]` | Admin-only data; optionally copies dumps for analysis |
| `scripts/analyze-dumps.ps1 -DumpDir <dir> -OutDir <dir>` | `!analyze -v` for each `.dmp` plus a summary |
| `scripts/winwatch/install.ps1` | Persistent pop-up watcher, see [its README](scripts/winwatch/README.md) |

The collection scripts are read-only and can be run by hand without Claude.

## Safety

- Collection is read-only. Changes are applied only after you choose them, with a rollback for each.
- Results are logged to `HEALTH_NOTES.md` in the working folder so later audits respect your earlier decisions.
- WinWatch installs a scheduled task for the current user; `uninstall.ps1` removes it.

## License

MIT
