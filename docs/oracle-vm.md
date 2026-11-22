# Oracle Cloud VM setup

This is the Oracle-specific part that the rdp.sh guide does not cover. Do this
before running the deployment scripts.

## 1. Create the instance

In the OCI Console:

1. **Compute → Instances → Create instance**
2. **Image:** Oracle Linux 8 or 9 (Oracle Autonomous Linux is supported)
3. **Shape:** `VM.Standard.E2.1.Micro` (1 GB, free tier) is the minimum. An
   Ampere A1.Flex shape with 2 GB or more is more comfortable once you manage
   several devices.
4. **Networking:** use a VCN with a public subnet and assign a public IPv4
   address.
5. **SSH keys:** upload your public key. The default user is `opc`.
6. **Boot volume:** the default is usually large enough. MeshCentral's npm
   package is several hundred MB; keep at least 5 GB free.

If you use the free tier and the instance is stopped and started later, the
ephemeral public IP can change. Reserve a public IP if the DNS record must stay
stable.

## 2. Open ports in the VCN security list

The default OCI security list allows only SSH. Add ingress rules for HTTP and
HTTPS.

**Networking → Virtual Cloud Networks → your VCN → Security Lists → Default
Security List → Add Ingress Rules**

| Stateless | Source | IP Protocol | Source Port Range | Destination Port Range |
|---|---|---|---|---|
| No | `0.0.0.0/0` | TCP | All | `80` |
| No | `0.0.0.0/0` | TCP | All | `443` |
| No | your admin IP | TCP | All | `22` |

If you use a Network Security Group (NSG) on the instance, add the same rules
there instead. The effective rule set is the union of the security list and any
NSGs.

For IPv6, add `::/0` rules for 80 and 443 and create an AAAA record.

## 3. Point DNS at the VM

At your DNS provider:

```text
mesh.example.com.  A     203.0.113.10
mesh.example.com.  AAAA  2001:db8::10      # only if you use IPv6
```

Verify before deploying, because Let's Encrypt validates over this hostname:

```bash
dig +short mesh.example.com
```

On Windows:

```powershell
Resolve-DnsName mesh.example.com -Type A
```

The result must include the VM's public IPv4. Keep the record DNS-only; a
proxied record (for example, an orange-cloud Cloudflare record) will break the
Let's Encrypt HTTP-01 challenge unless you add special handling.

## 4. Check SSH and sudo

```bash
ssh -i ~/.ssh/oracle.key opc@203.0.113.10
sudo -n true && echo "passwordless sudo works"
```

On Windows, use the full key path, for example
`ssh -i C:\Users\you\.ssh\oracle.key opc@203.0.113.10`.

The deploy scripts use `BatchMode=yes`, so key-based SSH is required and the
key must not prompt for a passphrase (use an unencrypted key or load it into
`ssh-agent`). The default Oracle `opc` user has passwordless sudo.

## 5. Open the instance firewall (firewalld)

Oracle Linux uses `firewalld`. `scripts/firewall.sh` enables and configures it:

```bash
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

Oracle Linux images also ship with iptables rules managed by firewalld. The
script enables firewalld and adds the required services. If you prefer raw
iptables, add the rules directly and persist them:

```bash
sudo iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 2 -p tcp --dport 443 -j ACCEPT
sudo iptables-save > /etc/sysconfig/iptables
```

`scripts/firewall.sh` uses firewalld. Do not run both approaches at the same
time.

## 6. Swap on a 1 GB instance

`npm install meshcentral` is memory-hungry. The bootstrap checks for less than
1.5 GB of RAM and, if no swap is active, adds 2 GB automatically before the
npm install. You can force it with `--add-swap` or disable it with `--no-swap`.

To do it manually before deploying, copy the project to the VM and run:

```bash
sudo bash ~/meshcentral-oracle/scripts/add-swap.sh
```

This creates `/swapfile`, enables it now, adds it to `/etc/fstab`, and sets
`vm.swappiness=10`.

## 7. Deploy

From Windows:

```powershell
.\deploy\deploy.ps1 -VmHost 203.0.113.10 -Domain mesh.example.com -Email admin@example.com
```

From Linux/macOS:

```bash
./deploy/deploy.sh --host 203.0.113.10 --domain mesh.example.com --email admin@example.com
```

Or run the bootstrap directly on the VM:

```bash
sudo bash ~/meshcentral-oracle/scripts/bootstrap.sh \
  --domain mesh.example.com \
  --email admin@example.com
```

A new install starts with Let's Encrypt staging. The browser warning is
expected until you run `promote-le.sh`.

## 8. Verify from outside

On Windows:

```powershell
Test-NetConnection mesh.example.com -Port 80
Test-NetConnection mesh.example.com -Port 443
curl.exe -kI https://mesh.example.com
```

On Linux/macOS:

```bash
curl -I http://mesh.example.com
curl -kI https://mesh.example.com
```

`http://` should redirect to `https://`. With the staging certificate, use
`-k` until production TLS is enabled.

## Common Oracle gotchas

- **Security list vs. NSG:** both can apply. If a port is open in one but
  blocked by the other, traffic still fails.
- **firewalld vs. image iptables:** Oracle Linux images ship with firewalld
  and iptables rules that allow only SSH. The bootstrap enables firewalld and
  adds HTTP/HTTPS. If you keep the image rules, add 80/443 to iptables and
  persist them.
- **Ephemeral public IP:** stopping and starting an instance can change it.
  Reserve the IP if DNS must remain stable.
- **Free-tier shape:** 1 GB RAM is enough for a small fleet, but use swap and
  avoid running other services on the same VM.
- **Outbound access:** the VM needs outbound HTTPS for NodeSource, npm, and
  Let's Encrypt. A restrictive egress rule or proxy will break the install.
- **IPv6:** if you publish an AAAA record, make sure the VM actually has an
  IPv6 address and the security list allows `::/0` on 80/443.
- **Time sync:** 2FA depends on correct time. `timedatectl` should show
  `System clock synchronized: yes`.
