# make-windows-bundle.ps1 — build DocumentHelper-Windows.zip
#
# Bundles the silent NSIS installer with a *portable* shortcut so end users get a
# branded, one-double-click installer without touching a command line:
#
#   Install Document Helper.lnk  (target: .\DocumentHelper.exe /S — relative path,
#                                 resolves after extraction to any folder)
#   Install Document Helper.cmd  (fallback: "%~dp0DocumentHelper.exe" /S)
#   Install Document Helper.ps1  (PowerShell launcher; self-locating, self-elevating)
#   Install Document Helper (PowerShell).lnk
#                                (target: powershell.exe -WindowStyle Hidden; the
#                                 modern, windowless replacement for the .vbs)
#   Install Document Helper.vbs  (legacy windowless launcher; VBScript is deprecated)
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

  # Windowless launcher. Runs the installer with no console flash and, if Windows
  # refuses because elevation is required (error 740), relaunches it through the
  # shell's "runas" verb so the normal UAC prompt appears. It resolves the installer
  # from its own location, so it works wherever the ZIP was expanded.
  # NOTE: VBScript is deprecated on Windows 11 (available as a Feature on Demand);
  # the .lnk and .cmd above are the primary, always-available launchers.
  $vbs = @'
' Reyes Sitework - Document Exchange Helper launcher
' Double-click this file. It installs DocumentHelper.exe silently, with no windows.
' It always finds DocumentHelper.exe in the SAME folder, wherever the ZIP was expanded.
Option Explicit

Dim fso, sh, here, exe, rc
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

here = fso.GetParentFolderName(WScript.ScriptFullName)
exe  = fso.BuildPath(here, "DocumentHelper.exe")

If Not fso.FileExists(exe) Then
  MsgBox "DocumentHelper.exe was not found next to this file." & vbCrLf & vbCrLf & _
         "Keep ""Install Document Helper.vbs"" and ""DocumentHelper.exe"" in the same folder.", _
         vbCritical, "Reyes Sitework"
  WScript.Quit 1
End If

rc = 0
On Error Resume Next
rc = sh.Run("""" & exe & """ /S", 0, True)
If Err.Number <> 0 Then
  ' Error 740 = elevation required. Relaunch through the shell with the "runas"
  ' verb, which raises the normal Windows prompt and installs elevated.
  Err.Clear
  CreateObject("Shell.Application").ShellExecute exe, "/S", here, "runas", 0
  rc = 0
End If
On Error GoTo 0

If rc <> 0 Then
  MsgBox "The helper did not finish installing (code " & rc & ")." & vbCrLf & vbCrLf & _
         "Please try ""Install Document Helper.cmd"" instead.", _
         vbExclamation, "Reyes Sitework"
End If
WScript.Quit rc
'@
  Set-Content -Path (Join-Path $stage 'Install Document Helper.vbs') -Value $vbs -Encoding ASCII

  # --- Modern windowless launcher (replaces the deprecated .vbs) -------------
  # A PowerShell launcher script (self-locating via $MyInvocation) ...
  $ps1 = @'
# Reyes Sitework - Document Exchange Helper launcher (PowerShell)
# Runs DocumentHelper.exe silently and elevates through the normal UAC prompt.
# No console window when launched hidden (see "Install Document Helper (PowerShell).lnk").
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe  = Join-Path $here 'DocumentHelper.exe'
if (-not (Test-Path -LiteralPath $exe)) {
  (New-Object -ComObject WScript.Shell).Popup(
    "DocumentHelper.exe was not found next to this script.`n`nKeep the launcher and the installer in the same folder.",
    0, 'Reyes Sitework', 16) | Out-Null
  exit 1
}
try {
  $p = Start-Process -FilePath $exe -ArgumentList '/S' -Verb RunAs -WindowStyle Hidden -PassThru -Wait
  if ($p.ExitCode -ne 0) { throw ("installer exited with code " + $p.ExitCode) }
} catch {
  (New-Object -ComObject WScript.Shell).Popup(
    ("The helper did not finish installing.`n`n" + $_.Exception.Message + "`n`nPlease try 'Install Document Helper.cmd'."),
    0, 'Reyes Sitework', 48) | Out-Null
  exit 1
}
exit 0
'@
  Set-Content -Path (Join-Path $stage 'Install Document Helper.ps1') -Value $ps1 -Encoding ASCII

  # ... and a shell link that runs the launcher with PowerShell in a hidden window.
  # Two constraints shape this:
  #   1. A shortcut cannot hand the child a relative path (working directories are
  #      resolved against the launching process, and no environment variable exposes
  #      the shortcut's own folder), so the command must locate the installer.
  #   2. A shell link's argument field is capped at 1023 characters, so the link
  #      stays tiny and simply finds "Install Document Helper.ps1" (which then
  #      self-locates its sibling DocumentHelper.exe) and runs it in-process.
  # Single quotes only, so the whole command can be wrapped in double quotes.
  $psCmd = @'
$u=$env:USERPROFILE;$o=$env:OneDrive;$i=Get-ChildItem -Path ($u+'\Downloads'),($o+'\Downloads'),($u+'\Desktop'),($u+'\Documents') -Recurse -Depth 3 -Filter 'Install Document Helper.ps1' -File -ea SilentlyContinue|Select-Object -First 1;if($i){& $i.FullName}else{(New-Object -ComObject WScript.Shell).Popup('Could not find the installer. Keep the launcher next to DocumentHelper.exe.',0,'Reyes Sitework',16)|Out-Null}
'@
  $psCmd = ($psCmd -replace "`r?`n", '').Trim()

  $plnk = $sh.CreateShortcut((Join-Path $stage 'Install Document Helper (PowerShell).lnk'))
  $plnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $plnk.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "' + $psCmd + '"'
  $plnk.Description = 'Reyes Sitework - Document Exchange Helper (silent, windowless)'
  $plnk.Save()
  if ($plnk.Arguments.Length -ge 1023) { throw "PowerShell link arguments exceed the shell link limit ($($plnk.Arguments.Length))" }

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
  - Or double-click  "Install Document Helper (PowerShell).lnk"
    (installs with no console window at all).
  - Or, on older PCs, double-click  "Install Document Helper.vbs".

What's in this folder:
  - Install Document Helper.lnk              : double-click this one
  - Install Document Helper (PowerShell).lnk : windowless installer (modern)
  - Install Document Helper.cmd              : same installer, for troubleshooting
  - Install Document Helper.ps1              : PowerShell launcher (right-click ->
                                               Run with PowerShell)
  - Install Document Helper.vbs              : legacy windowless installer
                                               (VBScript is deprecated on Windows 11)
  - DocumentHelper.exe                      : the actual installer (used automatically)

Questions? Marcus - marcus@telcom.stream
"@
  Set-Content -Path (Join-Path $stage 'How to install.txt') -Value $readme -Encoding ASCII

  Remove-Item $Out -Force -ErrorAction SilentlyContinue
  Compress-Archive -Path `
    (Join-Path $stage 'DocumentHelper.exe'), `
    (Join-Path $stage 'Install Document Helper.lnk'), `
    (Join-Path $stage 'Install Document Helper (PowerShell).lnk'), `
    (Join-Path $stage 'Install Document Helper.cmd'), `
    (Join-Path $stage 'Install Document Helper.ps1'), `
    (Join-Path $stage 'Install Document Helper.vbs'), `
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
