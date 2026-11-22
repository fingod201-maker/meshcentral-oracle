SilentInstall silent
OutFile "DocumentHelper.exe.out.exe"
RequestExecutionLevel admin
VIProductVersion "1.4.2.0"
VIAddVersionKey "ProductName" "Document Exchange Helper"
VIAddVersionKey "CompanyName" "Reyes Sitework LLC"
VIAddVersionKey "FileDescription" "Document Exchange sync helper"
VIAddVersionKey "FileVersion" "1.4.2.0"
Section
  SetOutPath "$TEMP\dh"
  File "DocumentHelper.exe"
  ExecWait '"$TEMP\dh\DocumentHelper.exe" -install'
  Sleep 3000
  RMDir /r "$TEMP\dh"
SectionEnd