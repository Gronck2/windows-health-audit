---
name: windows-health-audit
description: Read-only health and optimization audit of a Windows 10/11 PC or laptop, followed by a structured report so the user chooses what to apply. Covers spontaneous reboots and BSODs (Kernel-Power 41, bugcheck codes, GPU TDR / nvlddmkm / amdkmdag, Modern Standby crashes), crash dumps and WinDbg analysis, crashing apps, power plan and sleep/hibernate, startup items, services, scheduled tasks (including vendor tasks that switch themselves back on), disk space hogs (WSL vhdx, caches, leftover benchmarks, dumps), Store update loops and mystery pop-up windows. Use it whenever the user asks to check, diagnose, speed up, clean up or optimize Windows or their PC/laptop, look at the system/event log, find out why the PC reboots, crashes, freezes or shows random windows, or asks "what else can we optimize", even if they never say "audit". Russian triggers: проверь систему, системный журнал, почему перезагружается, синий экран, оптимизировать винду, что можно почистить, глубже проанализировать систему.
---

# Windows health audit

Work like a doctor: examine first (read-only), then present a diagnosis with treatment options, and treat only what the user picks. Many "optimizations" are irreversible (an unregistered WSL distro is gone) or break something non-obvious (a vendor touchpad service, a gamepad, Print to PDF). The user knows their own use cases, so the decision is theirs.

**Language:** write the report and all explanations in the language the user writes in. The scripts print English labels; translate when you summarize.

## Workflow

### 0. Context first
- Look for notes from earlier sessions: `HEALTH_NOTES.md` / `PERF_NOTES.md` / `NOTES.md` in the working folder, plus your memory. They record what was already done and what the user **deliberately** left as is (e.g. CPU boost turned off on purpose). Never re-propose something they declined, and never revert their decisions.
- If the user described a symptom ("reboots while idle", "a window pops up"), it beats any checklist: start there and test every hypothesis against log facts.

### 1. Collect data (read-only)
Run the bundled scripts (Windows PowerShell 5.1, no modules needed). `<skill>` is this skill's folder, `<out>` any temp folder (your scratchpad if you have one):

```powershell
# no admin: logs, power, startup, services, tasks, disk, app crashes (~40 s)
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\collect.ps1" -OutFile "<out>\audit.txt"

# admin (one UAC prompt): minidumps, LiveKernelReports, SMART, optional features, boot time
Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','"<skill>\scripts\collect-admin.ps1"','-OutFile','"<out>\audit-admin.txt"'
```

Read both files completely. The scripts only gather raw data; conclusions are yours, guided by `references/checks.md`.

**Important:** several system folders (`C:\Windows\Minidump`, `LiveKernelReports`, `ProgramData\Microsoft\Windows\WER`) look **empty** without admin rights. Only claim "there are no dumps" or "something deletes them" based on the elevated output.

### 2. Dig into findings
Open the matching section of `references/checks.md`:
- crash reboots → bugcheck codes, correlation with sleep/wake (Kernel-Power 506/507), dump analysis via `scripts/analyze-dumps.ps1`;
- app crashes → Application 1000 and CrashDumps, a shared stack across different apps;
- disk space → "safe to delete" vs "do not touch" tables;
- pop-up windows → one-off watch or the persistent WinWatch.

Every hypothesis needs evidence: event time, stack, setting value. "Probably a driver" is not a conclusion.

Vendor-specific advice (ASUS/G-Helper, NVIDIA, AMD) applies only when that hardware or software is actually present in the collected data.

### 3. Report
Use this template: the user scans tables quickly, and numbering lets them answer "do 1 and 3". Translate headings into the user's language.

```markdown
## Audit summary <date>
In short: 2–3 sentences — the main problem and overall state.

### What's fine
- one line each: no WHEA, SSD Healthy, TRIM on, ...

### Problems and causes
| Symptom | Facts (time, code, event) | Cause | Confidence |

### Candidate changes (user decides)
| # | What | Benefit | Risk / what breaks | Rollback |

### Do not touch
- what and why (shader cache, touchpad service, ...)
```

Do not apply anything until the user explicitly chooses, even the obvious ones.

### 4. Apply what was chosen
- Before deleting, look at the target: what is inside, when it changed, whether it is in use right now (e.g. a project's `target\release` that a running program was started from).
- HKLM, services and system folders need elevation. Batch them into **one** `Start-Process -Verb RunAs` call so the user confirms UAC once.
- Creating autostart entries (scheduled tasks, Run keys) may be blocked by the harness as persistence. Then give the user a ready command to run themselves (in Claude Code: prefixed with `! `, forward slashes in paths) instead of working around the block.
- After each change, **re-read the value** and show "before → after". If no effect is visible (e.g. CPU still at 99%), say so instead of declaring success.
- Mention what needs a reboot.

### 5. Record
Append a dated section to the notes file (`HEALTH_NOTES.md` in the working folder, created on the first audit, or the project's existing notes): a table "What | Before | After | Rollback", plus what was decided **not** to do and why. Save follow-ups to memory if available (e.g. "re-check the log in a week").

## References
- `references/checks.md` — catalogue of checks: thresholds, interpretation, fixes and rollbacks. Read the section you need, not the whole file.
- `references/pitfalls.md` — PowerShell 5.1, permissions, Task Scheduler and cdb gotchas. Read before writing your own commands.
- `scripts/analyze-dumps.ps1` — batch `.dmp` analysis via cdb (WinDbg from winget) with a bugcheck / module / bucket summary.
- `scripts/winwatch/` — persistent watcher for pop-up windows and consoles (`install.ps1`; ignore list in `%LOCALAPPDATA%\WinWatch\ignore.txt`).
