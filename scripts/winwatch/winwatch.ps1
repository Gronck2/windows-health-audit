# WinWatch: logs new visible windows and new consoles (conhost) together with their source.
# Logs: %LOCALAPPDATA%\WinWatch\logs\yyyy-MM-dd.log (kept 30 days). Ignore list: %LOCALAPPDATA%\WinWatch\ignore.txt
$ErrorActionPreference = 'SilentlyContinue'

$mutex = New-Object System.Threading.Mutex($false, 'Local\WinWatch')
if (-not $mutex.WaitOne(0)) { exit }   # already running

Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class WW {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int L, T, R, B; }
  public static List<string> List() {
    var res = new List<string>();
    EnumWindows((h, l) => {
      if (!IsWindowVisible(h)) return true;
      RECT r; GetWindowRect(h, out r); if (r.R - r.L < 50 || r.B - r.T < 30) return true;
      var t = new StringBuilder(256); GetWindowText(h, t, 256);
      var c = new StringBuilder(256); GetClassName(h, c, 256);
      uint pid; GetWindowThreadProcessId(h, out pid);
      res.Add(h.ToInt64() + "|" + pid + "|" + c + "|" + t + "|" + (r.R - r.L) + "x" + (r.B - r.T));
      return true; }, IntPtr.Zero);
    return res; } }
"@

$baseDir = Join-Path $env:LOCALAPPDATA 'WinWatch'
$logDir = Join-Path $baseDir 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
Get-ChildItem $logDir -Filter *.log | Where-Object LastWriteTime -lt (Get-Date).AddDays(-30) | Remove-Item -Force

function Log($msg) {
  $now = Get-Date
  "{0:HH:mm:ss} {1}" -f $now, $msg | Out-File (Join-Path $logDir ('{0:yyyy-MM-dd}.log' -f $now)) -Append -Encoding utf8
}

# Cache pid -> process (Name, ParentProcessId, CommandLine): remember every new process right away,
# so we still know who it was even if it exited before being logged.
$procs = @{}
function Remember {
  $new = Get-Process | Where-Object { -not $procs.ContainsKey($_.Id) } | ForEach-Object Id
  if (-not $new) { return }
  $filter = ($new | ForEach-Object { "ProcessId=$_" }) -join ' OR '
  foreach ($w in Get-CimInstance Win32_Process -Filter $filter) { $procs[[int]$w.ProcessId] = $w }
  foreach ($id in $new) { if (-not $procs.ContainsKey($id)) { $procs[$id] = $null } }
}

function Describe($procId) {
  $w = $procs[[int]$procId]
  if (-not $w) { $w = Get-CimInstance Win32_Process -Filter "ProcessId=$procId" }
  if (-not $w) { return "pid=$procId (unknown)" }
  $cmd = "$($w.CommandLine)"; if ($cmd.Length -gt 250) { $cmd = $cmd.Substring(0, 250) }
  "{0} pid={1} cmd={2}" -f $w.Name, $procId, $cmd
}

# Known noisy sources: one process name (with or without .exe) or regex per line, '#' starts a comment.
$ignoreFile = Join-Path $baseDir 'ignore.txt'
if (-not (Test-Path $ignoreFile)) { '# One process name (with or without .exe) or regex per line. Restart WinWatch after editing.' | Out-File $ignoreFile -Encoding utf8 }
$names = Get-Content $ignoreFile -Encoding utf8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $_ -replace '\.exe$', '' }
$ignore = if ($names) { '^(' + ($names -join '|') + ')(\.exe)?$' } else { '^$' }

Log "=== start (pid $PID), ignore: $ignore ==="
Remember
$myConsole = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
$seenWin = @{}; foreach ($x in [WW]::List()) { $seenWin[$x.Split('|')[0]] = 1 }
$seenCon = @{}; foreach ($p in Get-Process conhost) { $seenCon[$p.Id] = 1 }
$seenCon[[int]$myConsole] = 1

while ($true) {
  Remember
  foreach ($x in [WW]::List()) {
    $f = $x.Split('|')
    if (-not $seenWin.ContainsKey($f[0])) {
      $seenWin[$f[0]] = 1
      $p = Get-Process -Id ([int]$f[1])
      if ($p.ProcessName -match $ignore) { continue }
      Log ("WINDOW  {0} ({1}) title='{2}' class={3} size={4}" -f $p.ProcessName, $p.Path, $f[3], $f[2], $f[4])
    }
  }
  foreach ($p in Get-Process conhost) {
    if (-not $seenCon.ContainsKey($p.Id)) {
      $seenCon[$p.Id] = 1
      # conhost's parent is the console program; its parent is whoever launched it
      $c = $procs[$p.Id]
      if (-not $c) { continue }
      $app = $procs[[int]$c.ParentProcessId]
      if ($app.Name -in 'bash.exe','claude.exe') { continue }   # noise from Claude Code sessions
      $who = if ($app) { Describe $app.ParentProcessId } else { '?' }
      if ($who -match 'CLAUDE_CODE' -or $procs[[int]$app.ParentProcessId].Name -eq 'claude.exe') { continue }
      if ($app.Name -match $ignore -or $procs[[int]$app.ParentProcessId].Name -match $ignore) { continue }
      Log ("CONSOLE {0}  <- launched by: {1}" -f (Describe $c.ParentProcessId), $who)
    }
  }
  if ($seenWin.Count -gt 5000) { $seenWin.Clear(); foreach ($x in [WW]::List()) { $seenWin[$x.Split('|')[0]] = 1 } }
  if ($seenCon.Count -gt 5000) { $seenCon.Clear(); foreach ($p in Get-Process conhost) { $seenCon[$p.Id] = 1 } }
  if ($procs.Count -gt 5000) {
    $alive = @{}; foreach ($p in Get-Process) { $alive[$p.Id] = 1 }
    foreach ($id in @($procs.Keys)) { if (-not $alive.ContainsKey($id)) { $procs.Remove($id) } }
  }
  Start-Sleep -Milliseconds 250
}
