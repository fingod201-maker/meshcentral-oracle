# MeshCentral runbook

This runbook maps the rdp.sh guide to the scripts in this project and records
the recovery steps you are likely to need.

## File locations

| Item | Path |
|---|---|
| Install directory | `/opt/meshcentral` |
| MeshCentral data | `/opt/meshcentral/meshcentral-data` |
| Config | `/opt/meshcentral/meshcentral-data/config.json` |
| Auto-backups | `/opt/meshcentral/meshcentral-backups` |
| Manual backups | `/var/backups/meshcentral` |
| systemd unit | `/etc/systemd/system/meshcentral.service` |
| Service logs | `journalctl -u meshcentral` |

The only data you must keep is `meshcentral-data`. The auto-backup directory is
a second copy; keep both off-site.

## Step 1: DNS

Create an A record for the hostname and point it at the VM's public IPv4. Add
an AAAA record only if IPv6 is configured end to end.

```bash
dig +short mesh.example.com
```

`scripts/preflight.sh` compares the resolved address with the VM's public IPv4
(from `api.ipify.org`) and refuses to continue on a mismatch. Use
`--skip-dns` only when you are deliberately deploying before DNS is ready.

## Step 2: Node.js

The guide installs the NodeSource LTS repository:

```bash
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo dnf install -y nodejs
node --version
npm --version
```

`scripts/install-node.sh` does the same and accepts `--major 22` or `--major 24`
if you want a supported runtime instead of the guide's Node 20.

## Step 3: Dedicated user and MeshCentral

```bash
sudo useradd -r -m -d /opt/meshcentral -s /sbin/nologin meshcentral
cd /opt/meshcentral
sudo npm install meshcentral
sudo chown -R meshcentral:meshcentral /opt/meshcentral
```

`scripts/install-meshcentral.sh` implements this. The first start creates
`meshcentral-data`, but this project writes the config before the first start.
That avoids the guide's manual run as the unprivileged user, which cannot bind
443, and lets systemd start the full configuration on the first boot.

## Step 4: Config and TLS

The guide's first-run config:

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

`scripts/configure.sh` renders this from
`config/config.json.template`. Keep `production: false` for the first start so
Let's Encrypt uses staging. A misconfigured production request can hit the
rate limit and lock the hostname out for a week.

On a redeploy, the renderer preserves `newAccounts: false`, the password and
2FA policy, auto-backup, and a production certificate from the existing
`config.json`. It will not reopen registration or downgrade TLS by accident.

Once the staging certificate and DNS are confirmed, switch to a trusted
certificate:

```bash
sudo bash ~/meshcentral-oracle/scripts/promote-le.sh --domain mesh.example.com --yes
```

## Step 5: systemd

The unit is exactly the guide's:

```ini
[Unit]
Description=MeshCentral Server
After=network.target

[Service]
Type=simple
User=meshcentral
Group=meshcentral
WorkingDirectory=/opt/meshcentral
ExecStart=/usr/bin/node /opt/meshcentral/node_modules/meshcentral
Restart=always
RestartSec=5
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

`scripts/install-service.sh` installs it, enables it, restarts it, waits for
port 443, and prints the first log lines.

## Step 6: Firewall

```bash
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

`scripts/firewall.sh` enables firewalld and adds SSH, HTTP, and HTTPS
services permanently.

Remember the OCI VCN security list. firewalld alone is not enough. See
[oracle-vm.md](oracle-vm.md).

## Step 7: First administrator

Browse to `https://mesh.example.com`. Accept the staging certificate warning,
then create the first account. The first account on a fresh server becomes the
site administrator.

Create it immediately. While `newAccounts` is true, the first person to sign up
gets admin.

Optional headless equivalent:

```bash
sudo bash ~/meshcentral-oracle/scripts/create-admin.sh --user admin --email you@example.com
```

This uses MeshCentral's `--createaccount` and `--adminaccount` CLI commands.
The password is prompted for, but it is still passed to the CLI and may briefly
appear in the process list. The browser flow avoids that.

## Step 8: Close registration

After the admin account exists:

```bash
sudo bash ~/meshcentral-oracle/scripts/finalize.sh --yes
```

This sets:

```json
"domains": {
  "": {
    "newAccounts": false
  }
}
```

To add a teammate later, use **My Users → Add User**, or an invite link tied to
a device group. Do not re-enable open registration.

## Step 9: Add a device

In the web console:

1. **My Devices → Add Device Group**
2. Name it, for example, `Servers`, and choose **Manage with software agent**
3. Open the group and click **Add Agent**

The agent makes an outbound connection to the server, so the managed machine
needs no inbound ports and no public IP.

Linux one-liner from the Add Agent dialog:

```bash
wget -q "https://mesh.example.com/meshagents?script=1" -O meshinstall.sh
sudo bash meshinstall.sh https://mesh.example.com 'GROUPIDHASH'
```

Use the exact command from the dialog; the group hash is unique. Windows uses
the downloaded executable installer, run as administrator.

## Step 10: Two-factor authentication

Click your account name → **Account Security**, then add a TOTP authenticator
(Aegis, Google Authenticator, 1Password) or a hardware security key.

`finalize.sh` adds:

```json
"twoFactorCookieDurationDays": 7,
"passwordRequirements": {
  "min": 12,
  "force2factor": true
}
```

`force2factor` is the current MeshCentral key. The blog's `twofactor` key is
stale and is ignored by current releases.

## Step 11: Backups

`finalize.sh` adds:

```json
"autoBackup": {
  "backupIntervalHours": 24,
  "keepLastDaysBackup": 30,
  "backupPath": "/opt/meshcentral/meshcentral-backups"
}
```

Manual backup:

```bash
sudo bash ~/meshcentral-oracle/scripts/backup-now.sh
```

Off-site copy with rclone (after configuring a remote named `remote`):

```cron
30 3 * * * root tar -czf /tmp/mesh-$(date +\%F).tar.gz -C /opt/meshcentral meshcentral-data meshcentral-backups 2>/dev/null && rclone copy /tmp/mesh-$(date +\%F).tar.gz remote:mesh-backups
```

## Verification

```bash
sudo bash ~/meshcentral-oracle/scripts/verify.sh --domain mesh.example.com
```

It checks:

- service active
- ports 80 and 443 listening
- firewalld status
- config values
- DNS
- local HTTPS response
- certificate issuer and dates
- recent warnings

Expected production issuer: a Let's Encrypt intermediate such as `R11`.
Staging issuers contain `STAGING` or `Fake`.

## Upgrade MeshCentral

```bash
sudo bash ~/meshcentral-oracle/scripts/upgrade.sh
```

The script creates a manual backup, stops the service, runs
`npm install meshcentral@latest`, fixes ownership, starts the service, and
prints the new version.

## Restore from backup

```bash
sudo systemctl stop meshcentral
sudo tar -xzf /var/backups/meshcentral/meshcentral-data-YYYYMMDDTHHMMSSZ.tar.gz \
  -C /opt/meshcentral
sudo chown -R meshcentral:meshcentral /opt/meshcentral/meshcentral-data
sudo systemctl start meshcentral
```

If you restore an older `config.json`, re-check `newAccounts`,
`force2factor`, and the Let's Encrypt mode before exposing the server again.

## Recover an admin account or 2FA

On the VM:

```bash
sudo systemctl stop meshcentral
sudo -u meshcentral bash -c 'cd /opt/meshcentral && /usr/bin/node node_modules/meshcentral --showusers'
sudo -u meshcentral bash -c 'read -r -s -p "New password: " P; echo; cd /opt/meshcentral && /usr/bin/node node_modules/meshcentral --resetaccount USERNAME --pass "$P"'
sudo -u meshcentral bash -c 'cd /opt/meshcentral && /usr/bin/node node_modules/meshcentral --adminaccount USERNAME'
sudo systemctl start meshcentral
```

`--resetaccount` unlocks the account, removes its 2FA, and sets the new
password you are prompted for. `--adminaccount` promotes it to site
administrator.

If you only locked yourself out by disabling registration, temporarily set
`newAccounts` back to `true`, restart, create the account, then run
`finalize.sh` again.

## Troubleshooting

### Self-signed certificate

Let's Encrypt has not issued yet, or staging is still active.

```bash
sudo journalctl -u meshcentral -n 100 --no-pager
sudo bash ~/meshcentral-oracle/scripts/verify.sh --domain mesh.example.com
```

Common causes:

- DNS does not resolve to this VM
- port 80 is blocked by firewalld or the OCI security list
- `letsencrypt.production` is still `false`
- Let's Encrypt is rate-limited

### Rate-limit errors

Switch back to staging:

```bash
sudo systemctl stop meshcentral
sudo node ~/meshcentral-oracle/scripts/patch-config.js \
  /opt/meshcentral/meshcentral-data/config.json --staging
sudo chown meshcentral:meshcentral /opt/meshcentral/meshcentral-data/config.json
sudo systemctl start meshcentral
```

Fix the underlying DNS or port issue, verify staging, then run
`promote-le.sh` again.

### Agent installs but stays offline

- Confirm the managed machine can reach `https://mesh.example.com` outbound.
- Confirm the `cert` value in `config.json` exactly matches the URL used to
  download the agent.
- Check the server log for the agent's connection attempt.

### Service cannot bind 443

```bash
systemctl cat meshcentral | grep -E 'AmbientCapabilities|User|ExecStart'
sudo systemctl daemon-reload
sudo systemctl restart meshcentral
```

The unit must contain `AmbientCapabilities=CAP_NET_BIND_SERVICE` and run as
`meshcentral`, not root.

### OCI ports still blocked

Check both layers:

```bash
sudo firewall-cmd --list-all
sudo iptables -L INPUT -n -v --line-numbers
```

Then check the VCN security list and any NSG in the OCI Console. See
[oracle-vm.md](oracle-vm.md).

Also check SELinux: `getenforce`. If it shows `Enforcing`, the bootstrap
sets it to `Permissive` automatically. If you changed it back, MeshCentral
may be blocked from binding ports or writing files.

### npm install out of memory

```bash
sudo bash ~/meshcentral-oracle/scripts/add-swap.sh
```

Then rerun the bootstrap or deploy command. It is safe to rerun: Node and
MeshCentral installs are skipped if already present, and an existing config is
preserved.

### Time drift breaks 2FA

```bash
timedatectl
sudo systemctl restart systemd-timesyncd
```

## Security checklist

- [ ] SSH is key-only; port 22 is restricted to your admin IP if possible.
- [ ] The first admin account was created immediately.
- [ ] `newAccounts` is false.
- [ ] 2FA is required for all accounts.
- [ ] Production TLS is active.
- [ ] Auto-backup is enabled and a manual backup is stored off-site.
- [ ] The VM is patched monthly.
- [ ] The OCI security list exposes only 22, 80, and 443.
- [ ] You have tested restoring `meshcentral-data` on a throwaway VM.
