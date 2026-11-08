# Batch analysis of .dmp files with cdb from Microsoft WinDbg: !analyze -v for each, summary of key fields and stack.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File analyze-dumps.ps1 -DumpDir <dir> -OutDir <dir> [-ExtraSymbols "C:\proj\target\release"]
# Needs WinDbg: winget install Microsoft.WinDbg. The first run downloads symbols into C:\Symbols (minutes).
param([Parameter(Mandatory)] [string]$DumpDir, [Parameter(Mandatory)] [string]$OutDir, [string]$ExtraSymbols = '', [string]$SymbolCache = 'C:\Symbols')
$pkg = Get-AppxPackage Microsoft.WinDbg
$cdb = if ($pkg) { Join-Path $pkg.InstallLocation 'amd64\cdb.exe' } else { "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\cdb.exe" }
if (-not (Test-Path $cdb)) { 'cdb not found. Install it: winget install Microsoft.WinDbg'; exit 1 }
$env:_NT_SYMBOL_PATH = "srv*$SymbolCache*https://msdl.microsoft.com/download/symbols" + $(if ($ExtraSymbols) { ";$ExtraSymbols" })
New-Item -ItemType Directory -Force $OutDir | Out-Null
$fields = '^(BUGCHECK_CODE|BUGCHECK_P[1-4]|EXCEPTION_CODE_STR|PROCESS_NAME|MODULE_NAME|IMAGE_NAME|SYMBOL_NAME|FAILURE_BUCKET_ID|IMAGE_VERSION|DPC_TIMEOUT_TYPE):'
$summary = foreach ($d in Get-ChildItem $DumpDir -Recurse -Filter *.dmp | Sort-Object LastWriteTime) {
  $txt = Join-Path $OutDir ($d.BaseName + '.txt')
  $out = & $cdb -z $d.FullName -c '!analyze -v; q' 2>&1 | Out-String
  [IO.File]::WriteAllText($txt, $out, (New-Object Text.UTF8Encoding $true))
  $lines = $out -split "`r?`n"
  $i = [array]::IndexOf($lines, ($lines | Where-Object { $_ -match '^STACK_TEXT:' } | Select-Object -First 1))
  $stack = if ($i -ge 0) { $lines[($i + 1)..($i + 16)] | Where-Object { $_.Trim() -and $_ -notmatch '^[A-Z_]+:' } | ForEach-Object { '    ' + ($_ -split ' : ')[-1].Trim() } } else { @() }
  @("===== $($d.Name)  ($($d.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))") + ($lines | Where-Object { $_ -match $fields } | ForEach-Object { '  ' + $_.Trim() }) + '  STACK:' + $stack
}
$sumFile = Join-Path $OutDir '_summary.txt'
[IO.File]::WriteAllText($sumFile, ($summary -join "`r`n"), (New-Object Text.UTF8Encoding $true))
$summary
"`nFull reports: $OutDir ; summary: $sumFile"
