# MeshCentral on Oracle Cloud

A deployable project that implements the procedure from
[Self-Host MeshCentral on a VPS for Web-Based Remote Management](https://rdp.sh/blog/self-host-meshcentral-on-a-vps-for-web-based-remote-management)
on an Oracle Cloud Oracle Linux VM.

The guide's stack is preserved:

- Node.js from NodeSource
- a dedicated `meshcentral` system user
- MeshCentral installed under `/opt/meshcentral`
- built-in Let's Encrypt, with staging first and production second
- a systemd unit with `CAP_NET_BIND_SERVICE`
- firewalld for ports 22, 80, and 443
- registration closed and 2FA enforced after the first admin account
- daily auto-backup

Oracle-specific additions cover the VCN security list, the image's iptables
rules, and swap on 1 GB instances (the bootstrap adds it automatically when
needed). See [docs/oracle-vm.md](docs/oracle-vm.md).

## What is in this project

```
meshcentral-oracle/
├── .env.example                 # deployment settings
├── config/
│   └── config.json.template     # guide step 4 config
├── systemd/
│   └── meshcentral.service      # guide step 5 unit
├── scripts/
│   ├── bootstrap.sh             # runs steps 2-6
│   ├── preflight.sh             # OS, disk, RAM, ports, DNS
│   ├── install-node.sh          # step 2
│   ├── install-meshcentral.sh   # step 3
│   ├── configure.sh             # step 4
│   ├── install-service.sh       # step 5
│   ├── firewall.sh              # step 6
│   ├── create-admin.sh          # optional headless step 7
│   ├── finalize.sh              # steps 8, 10, 11
│   ├── promote-le.sh            # staging -> production certificate
│   ├── verify.sh                # health and certificate check
│   ├── backup-now.sh            # manual backup
│   ├── upgrade.sh               # npm update + restart
│   └── add-swap.sh              # optional for 1 GB VMs
├── deploy/
│   ├── deploy.ps1               # Windows deploy/operations wrapper
│   └── deploy.sh                # Linux/macOS deploy/operations wrapper
└── docs/
    ├── oracle-vm.md             # OCI instance and network setup
    └── runbook.md               # step-by-step guide mapping and recovery
```

## Requirements

- Oracle Cloud VM running Oracle Linux 8/9 (Oracle Autonomous Linux supported)
- 1 GB RAM minimum, 2 GB recommended
- At least 5 GB free disk (MeshCentral's npm package is large)
- Public IPv4 address
- A DNS name such as `mesh.example.com` with an A record pointing at the VM
- Ports 80 and 443 open in the OCI VCN security list / NSG
- SSH access with a key and passwordless sudo (the default `opc` user on Oracle Linux)
- The SSH key must work non-interactively: no passphrase, or loaded into
  `ssh-agent`. The wrappers use `BatchMode=yes`.
- Node.js 20 is the guide's baseline. Node 20 is EOL as of April 2026; the
  scripts default to 20 for fidelity, and accept `--node-major 22`.

## Quick start on Windows

1. Copy the environment file and fill it in:

   ```powershell
   Copy-Item .env.example .env
   notepad .env
   ```

   At minimum set `DOMAIN`, `LE_EMAIL`, `VM_HOST`, and `SSH_KEY`.

2. Deploy. The script copies the bundle to the VM and runs the bootstrap as
   root over SSH:

   ```powershell
   .\deploy\deploy.ps1 -VmHost 203.0.113.10 -Domain mesh.example.com -Email admin@example.com
   ```

   If PowerShell blocks local scripts, run it through a bypass for this one
   process:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\deploy\deploy.ps1 `
     -VmHost 203.0.113.10 -Domain mesh.example.com -Email admin@example.com
   ```

   The first start uses the Let's Encrypt **staging** service, exactly as the
   guide recommends. The browser will show an untrusted-certificate warning.
   That is expected.

3. Create the site administrator. Open `https://mesh.example.com`, accept the
   staging warning, and create the first account. The first account becomes the
   site administrator.

   For a headless deployment you can use the optional helper instead:

   ```powershell
   .\deploy\deploy.ps1 -Action create-admin -VmHost 203.0.113.10
   ```

4. Close registration, enforce 2FA, and enable auto-backup:

   ```powershell
   .\deploy\deploy.ps1 -Action finalize -VmHost 203.0.113.10 -Domain mesh.example.com -Yes
   ```

5. Switch Let's Encrypt to production:

   ```powershell
   .\deploy\deploy.ps1 -Action promote -VmHost 203.0.113.10 -Domain mesh.example.com -Yes
   ```

6. Log in at `https://mesh.example.com`, enroll a TOTP authenticator or
   security key, then add a device group and agent.

## Quick start on Linux or macOS

```bash
cp .env.example .env
$EDITOR .env

./deploy/deploy.sh --host 203.0.113.10 --domain mesh.example.com --email admin@example.com

# Create the first account in the browser, then:
./deploy/deploy.sh --action finalize --host 203.0.113.10 --domain mesh.example.com --yes
./deploy/deploy.sh --action promote  --host 203.0.113.10 --domain mesh.example.com --yes
```

## Manual install on the VM

If you prefer to work directly on the VM:

```bash
ssh opc@YOUR_VM_IP 'mkdir -p ~/meshcentral-oracle'
scp -r config scripts systemd opc@YOUR_VM_IP:~/meshcentral-oracle/

ssh opc@YOUR_VM_IP
sudo bash ~/meshcentral-oracle/scripts/bootstrap.sh \
  --domain mesh.example.com \
  --email admin@example.com
```

Then run the post-install steps:

```bash
sudo bash ~/meshcentral-oracle/scripts/finalize.sh --yes
sudo bash ~/meshcentral-oracle/scripts/promote-le.sh --domain mesh.example.com --yes
```

## What the bootstrap does

| Guide step | Script | Result |
|---|---|---|
| 2. Node.js | `install-node.sh` | NodeSource Node 20 (or chosen major) |
| 3. Dedicated user | `install-meshcentral.sh` | `meshcentral` user, `/opt/meshcentral`, `npm install meshcentral` |
| 4. TLS and domain | `configure.sh` | `config.json` with `cert`, `WANonly`, `port: 443`, `redirPort: 80`; staging first, existing hardening preserved on redeploy |
| 5. systemd | `install-service.sh` | `/etc/systemd/system/meshcentral.service` with `CAP_NET_BIND_SERVICE` |
| 6. Firewall | `firewall.sh` | firewalld allows SSH, HTTP, HTTPS |

The bootstrap does **not** create the admin account or close registration. That
is deliberate: the guide creates the first account in the browser, then closes
the door. Use `finalize.sh` after the admin exists.

Redeploying over an existing install is safe: `configure.sh` preserves
`newAccounts: false`, the password/2FA policy, auto-backup, and an existing
production certificate. It never reopens registration. To deliberately go back
to staging, run `patch-config.js --staging` as shown in the runbook.

## Post-install checklist

- [ ] `https://mesh.example.com` loads (staging warning is normal at first)
- [ ] First account created and it shows administrator rights
- [ ] `finalize.sh` has set `newAccounts: false`
- [ ] 2FA enrollment is required on the next login
- [ ] `promote-le.sh` reports a production Let's Encrypt issuer
- [ ] A device group exists and an agent checks in
- [ ] Auto-backup directory has a backup after the first 24 hours
- [ ] A manual backup has been copied off the VM
- [ ] OCI security list allows only the ports you need

## Day-2 commands

From Windows:

```powershell
.\deploy\deploy.ps1 -Action status  -VmHost 203.0.113.10
.\deploy\deploy.ps1 -Action logs    -VmHost 203.0.113.10
.\deploy\deploy.ps1 -Action verify  -VmHost 203.0.113.10 -Domain mesh.example.com
.\deploy\deploy.ps1 -Action backup  -VmHost 203.0.113.10
.\deploy\deploy.ps1 -Action upgrade -VmHost 203.0.113.10
```

From Linux or macOS, use the same actions with `./deploy/deploy.sh --action ...`.

On the VM:

```bash
sudo systemctl status meshcentral --no-pager
sudo journalctl -u meshcentral -f
sudo systemctl restart meshcentral
sudo bash ~/meshcentral-oracle/scripts/verify.sh --domain mesh.example.com
```

## Backups and restore

MeshCentral's built-in auto-backup is enabled by `finalize.sh`:

- every 24 hours
- keeps 30 days
- writes to `/opt/meshcentral/meshcentral-backups`

Manual backup:

```bash
sudo bash ~/meshcentral-oracle/scripts/backup-now.sh
```

The guide's off-site example uses rclone. After configuring an rclone remote
named `remote`, add a root cron job:

```cron
30 3 * * * root tar -czf /tmp/mesh-$(date +\%F).tar.gz -C /opt/meshcentral meshcentral-data meshcentral-backups 2>/dev/null && rclone copy /tmp/mesh-$(date +\%F).tar.gz remote:mesh-backups
```

Restore:

```bash
sudo systemctl stop meshcentral
sudo tar -xzf /var/backups/meshcentral/meshcentral-data-YYYYMMDDTHHMMSSZ.tar.gz -C /opt/meshcentral
sudo chown -R meshcentral:meshcentral /opt/meshcentral/meshcentral-data
sudo systemctl start meshcentral
```

Losing `meshcentral-data` means re-enrolling every agent. Treat it like the
keys to the fleet.

## Configuration

The initial config is rendered from `config/config.json.template`:

```json
{
  "settings": {
    "cert": "mesh.example.com",
    "WANonly": true,
    "port": 443,
    "redirPort": 80
  },
  "domains": {
    "": {
      "title": "My Mesh",
      "newAccounts": true
    }
  },
  "letsencrypt": {
    "email": "admin@example.com",
    "names": "mesh.example.com",
    "production": false
  }
}
```

After `finalize.sh`, the default domain gains:

```json
"newAccounts": false,
"twoFactorCookieDurationDays": 7,
"passwordRequirements": {
  "min": 12,
  "force2factor": true
}
```

and `settings` gains:

```json
"autoBackup": {
  "backupIntervalHours": 24,
  "keepLastDaysBackup": 30,
  "backupPath": "/opt/meshcentral/meshcentral-backups"
}
```

## Production reverse-proxy notes (mesh.telcom.stream)

The live instance runs MeshCentral on 8443 behind Nginx on 443. Agents must
connect through Nginx, and MeshCentral must accept the Nginx certificate. The
production configuration therefore adds, on top of the template above:

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

- `aliasPort: 443` makes generated agents use the public endpoint.
- `certUrl` loads the Nginx certificate so the agent-reported SHA-384 hash
  matches (otherwise agents are rejected with `Agent bad web cert hash`).
- `trustedProxy` records real client IPs.
- Do not set `ignoreAgentHashCheck`; it disables agent server authentication.

`scripts/verify-enrollment.sh` checks service health, the WebSocket upgrade,
the loaded certificate hash, and recent certificate-hash rejections.

## Troubleshooting

| Symptom | Check |
|---|---|
| Browser shows a self-signed certificate | Staging is still active, or Let's Encrypt has not issued yet. Run `journalctl -u meshcentral -f` and check DNS and port 80. The DNS record must be DNS-only (no Cloudflare proxy) for the HTTP-01 challenge. |
| Let's Encrypt rate-limit errors | Switch back to staging, fix DNS/ports, verify, then promote again. |
| Agent installs but stays offline | The client's outbound HTTPS is blocked, or `settings.cert` differs from the URL used to download the agent. They must match. |
| Service cannot bind port 443 | Confirm `AmbientCapabilities=CAP_NET_BIND_SERVICE` in the unit and run `systemctl daemon-reload`. |
| Locked out after disabling registration | Temporarily set `newAccounts` to `true`, restart, create the account, then set it back to `false`. |
| Lost admin or 2FA device | Follow [Recover an admin account or 2FA](docs/runbook.md#recover-an-admin-account-or-2fa). `--resetaccount` needs a new password and removes 2FA. |
| OCI ports still blocked | Open TCP 80/443 in the VCN security list **and** firewalld. Check SELinux (`getenforce`). See [docs/oracle-vm.md](docs/oracle-vm.md). |
| `npm install` runs out of memory | Add swap with `sudo bash ~/meshcentral-oracle/scripts/add-swap.sh` and rerun the bootstrap. |
| PowerShell blocks `deploy.ps1` | Use `powershell -ExecutionPolicy Bypass -File ...` or `Set-ExecutionPolicy -Scope Process Bypass`. |

More detail, including the exact guide-to-script mapping and recovery steps, is
in [docs/runbook.md](docs/runbook.md).

## Guide fidelity notes

The project follows the guide's order and commands. Four details needed a
working equivalent because the blog's snippets have drifted from current
MeshCentral or current Node.js:

1. **2FA key name.** The guide uses
   `"passwordRequirements": { "twofactor": true }`. Current MeshCentral uses
   `force2factor`. This project uses `force2factor` so enforcement actually
   works, and removes the stale `twofactor` key if it finds one.
2. **Auto-backup path.** The guide says archives land in
   `meshcentral-data/backups`. Current MeshCentral refuses a backup path inside
   `meshcentral-data` and defaults to a sibling `meshcentral-backups`
   directory. This project sets `/opt/meshcentral/meshcentral-backups`
   explicitly.
3. **Config generation.** The guide starts the server once to create a default
   config, then edits it. This project writes `config.json` directly before the
   first systemd start, which avoids binding 443 as an unprivileged user and
   produces the same config.
4. **Node 20.** The guide pins Node 20. Node 20 reached end-of-life in April
   2026. The default remains 20 for fidelity; use `--node-major 22` (or
   `NODE_MAJOR=22` in `.env`) for a supported runtime. MeshCentral 1.3.x
   requires Node >= 20.

Oracle-specific additions (VCN ingress rules, iptables fallback, firewalld,
SELinux, and swap) are documented separately so the guide's steps remain
recognizable.

## Security notes

- Create the first admin account immediately after the server is reachable.
  Until then, open registration is a race.
- Run `finalize.sh` as soon as the admin exists. It closes registration and
  forces 2FA.
- Keep SSH key-only. Do not expose port 22 to the whole internet if you can
  avoid it.
- Keep the VM patched: `sudo apt update && sudo apt upgrade`.
- Back up `meshcentral-data` and test a restore before you need it.
- The staging certificate is not trusted by browsers. Do not leave it in place
  for production use.
