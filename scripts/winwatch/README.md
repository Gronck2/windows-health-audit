# WinWatch

Catches a mystery pop-up window: logs every new visible window and every new console together with whoever launched it.

- `install.ps1` — start at logon (scheduled task `WinWatch`, windowless via `conhost --headless`) and start now
- `uninstall.ps1` — stop and remove the autostart (logs are kept)
- `show.ps1 14:15` — entries ±10 min around a time today; `show.ps1 14:15 -Date 2026-01-31 -Minutes 5`; no arguments — last 40 lines
- Logs: `%LOCALAPPDATA%\WinWatch\logs\yyyy-MM-dd.log`, kept for 30 days

Log lines:
- `WINDOW  <process> (<path>) title='...' class=... size=...` — a new visible window appeared
- `CONSOLE <program> pid= cmd=...  <- launched by: <parent> cmd=...` — a console opened (catches instant flashes too)

**Ignore list:** `%LOCALAPPDATA%\WinWatch\ignore.txt`, one process name (with or without `.exe`) or regex per line, `#` for comments. Windows of these processes, and consoles they launch, are not logged. Read at start; restart WinWatch after editing (`uninstall.ps1` + `install.ps1`). Consoles spawned by Claude Code sessions are always skipped.
