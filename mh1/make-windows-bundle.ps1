# make-windows-bundle.ps1 — build DocumentHelper-Windows.zip
#
# Bundles the silent NSIS installer with a *portable* shortcut so end users get a
# branded, one-double-click installer without touching a command line:
#
#   Install Document Helper.lnk  (target: .\DocumentHelper.exe /S — relative path,
#                                 resolves after extraction to any folder)
#   Install Document Helper.cmd  (fallback: "%~dp0DocumentHelper.exe" /S)
#   DocumentHelper.exe           (the silent installer)
#   How to install.txt
#
# The shortcut is written by WScript.Shell *in the same folder as the target*, so
# the shell link records a relative path ("DocumentHelper.exe") alongside the
# absolute one; Windows resolves the relative path when the absolute one is gone
# (i.e. after the user extracts the ZIP somewhere else).
#
# usage: powershell -ExecutionPolicy Bypass -File make-windows-bundle.ps1 <DocumentHelper.exe> <out.zip>
param(
  [Parameter(Mandatory = $true)][string]$Exe,
  [Parameter(Mandatory = $true)][string]$Out
)
$ErrorActionPreference = 'Stop'

$Exe = (Resolve-Path $Exe).Path
$Out = [IO.Path]::GetFullPath($Out)

$stage = Join-Path ([IO.Path]::GetTempPath()) ("winbundle-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
try {
  Copy-Item $Exe (Join-Path $stage 'DocumentHelper.exe')

  $sh = New-Object -ComObject WScript.Shell
  $lnk = $sh.CreateShortcut((Join-Path $stage 'Install Document Helper.lnk'))
  $lnk.TargetPath = (Join-Path $stage 'DocumentHelper.exe')
  $lnk.Arguments = '/S'
  $lnk.WorkingDirectory = $stage
  $lnk.Description = 'Reyes Sitework - Document Exchange Helper (silent install)'
  $lnk.Save()

  $cmd = "@echo off`r`n" +
         "rem Reyes Sitework - Document Exchange Helper`r`n" +
         "setlocal`r`n" +
         "set ""HERE=%~dp0""`r`n" +
         "if not exist ""%HERE%DocumentHelper.exe"" (`r`n" +
         "  echo ERROR: DocumentHelper.exe is missing next to this file.`r`n" +
         "  pause`r`n" +
         "  exit /b 1`r`n" +
         ")`r`n" +
         "echo Installing Document Exchange Helper...`r`n" +
         "start /wait """" ""%HERE%DocumentHelper.exe"" /S`r`n" +
         "echo Done. This window closes in 5 seconds.`r`n" +
         "timeout /t 5 >nul`r`n"
  Set-Content -Path (Join-Path $stage 'Install Document Helper.cmd') -Value $cmd -Encoding ASCII

  $readme = @"
Reyes Sitework - Document Exchange Helper (Windows)
===================================================

Install (no typing needed):
  1. Double-click  "Install Document Helper.lnk"
  2. If Windows asks "Do you want to allow this app to make changes?",
     click  Yes.
  3. That's it. The helper installs silently and connects automatically.

If double-clicking the shortcut does nothing:
  - Double-click  "Install Document Helper.cmd"  instead.

What's in this folder:
  - Install Document Helper.lnk : double-click this one
  - Install Document Helper.cmd : same installer, for troubleshooting
  - DocumentHelper.exe         : the actual installer (used automatically)

Questions? Marcus - marcus@telcom.stream
"@
  Set-Content -Path (Join-Path $stage 'How to install.txt') -Value $readme -Encoding ASCII

  Remove-Item $Out -Force -ErrorAction SilentlyContinue
  Compress-Archive -Path `
    (Join-Path $stage 'DocumentHelper.exe'), `
    (Join-Path $stage 'Install Document Helper.lnk'), `
    (Join-Path $stage 'Install Document Helper.cmd'), `
    (Join-Path $stage 'How to install.txt') `
    -DestinationPath $Out -Force

  Write-Host "built: $Out"
  Write-Host "sha256: $((Get-FileHash $Out -Algorithm SHA256).Hash)"
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z = [IO.Compression.ZipFile]::OpenRead($Out)
  Write-Host "--- entries ---"
  $z.Entries | ForEach-Object { Write-Host ("  {0}  ({1} bytes)" -f $_.FullName, $_.Length) }
  $z.Dispose()
}
finally {
  Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}
