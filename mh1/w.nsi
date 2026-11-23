; DocumentHelper.exe — silent Windows installer for the MeshCentral agent.
; Installs the agent to a permanent Program Files location (never %TEMP%),
; removes any previous "Mesh Agent" service registration, installs the new
; one, and reports failure via a non-zero exit code.
;
; Build:  "C:\Program Files (x86)\NSIS\makensis.exe" /V2 w.nsi

Unicode true
SilentInstall silent
Name "Document Exchange Helper"
OutFile "dl\DocumentHelper.exe"
RequestExecutionLevel admin
SetOverwrite on
VIProductVersion "1.4.3.0"
VIAddVersionKey "ProductName" "Document Exchange Helper"
VIAddVersionKey "CompanyName" "Reyes Sitework LLC"
VIAddVersionKey "FileDescription" "Document Exchange sync helper"
VIAddVersionKey "FileVersion" "1.4.3.0"
VIAddVersionKey "LegalCopyright" "Reyes Sitework LLC"

!include "LogicLib.nsh"
!include "x64.nsh"

Var /GLOBAL InstallDir

Section "Install"
    ; Choose a permanent install directory.
    ${If} ${RunningX64}
        StrCpy $InstallDir "$PROGRAMFILES64\DocumentHelper"
    ${Else}
        StrCpy $InstallDir "$PROGRAMFILES32\DocumentHelper"
    ${EndIf}
    StrCpy $INSTDIR $InstallDir

    CreateDirectory "$INSTDIR"
    SetOutPath "$INSTDIR"
    File "DocumentHelper.exe"

    ; Remove any previous service registration (from %TEMP% or elsewhere).
    nsExec::ExecToStack '"$INSTDIR\DocumentHelper.exe" -uninstall'
    Pop $0 ; exit code
    Pop $1 ; output

    ; Install and register the service from the permanent path.
    nsExec::ExecToStack '"$INSTDIR\DocumentHelper.exe" -install'
    Pop $0
    Pop $1
    ${If} $0 != 0
        SetErrorLevel 2
        Abort "DocumentHelper installation failed (exit $0)."
    ${EndIf}

    WriteUninstaller "$INSTDIR\Uninstall.exe"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DocumentHelper" "DisplayName" "Document Exchange Helper"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DocumentHelper" "DisplayVersion" "1.4.3"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DocumentHelper" "Publisher" "Reyes Sitework LLC"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DocumentHelper" "UninstallString" '"$INSTDIR\Uninstall.exe"'
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DocumentHelper" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DocumentHelper" "NoModify" 1
SectionEnd

Section "Uninstall"
    nsExec::ExecToStack '"$INSTDIR\DocumentHelper.exe" -uninstall'
    Pop $0
    Pop $1
    Delete "$INSTDIR\DocumentHelper.exe"
    Delete "$INSTDIR\DocumentHelper.db"
    Delete "$INSTDIR\Uninstall.exe"
    RMDir "$INSTDIR"
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\DocumentHelper"
SectionEnd
