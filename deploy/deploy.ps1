#Requires -Version 5.1
<#
.SYNOPSIS
Deploy and operate MeshCentral on an Oracle Cloud Oracle Linux VM.

.DESCRIPTION
Implements the rdp.sh MeshCentral guide:
  - Node.js from NodeSource
  - dedicated meshcentral user under /opt/meshcentral
  - built-in Let's Encrypt (staging first)
  - systemd unit with CAP_NET_BIND_SERVICE
  - firewalld rules
Then helps with the post-install steps: admin account, registration lockdown,
2FA, backups, and production TLS.

.EXAMPLE
.\deploy\deploy.ps1 -VmHost 203.0.113.10 -Domain mesh.example.com -Email admin@example.com

.EXAMPLE
.\deploy\deploy.ps1 -Action finalize -VmHost 203.0.113.10 -Domain mesh.example.com -Yes

.EXAMPLE
.\deploy\deploy.ps1 -Action promote -VmHost 203.0.113.10 -Domain mesh.example.com -Yes
#>
[CmdletBinding()]
param(
    [ValidateSet('deploy', 'finalize', 'promote', 'verify', 'status', 'logs', 'backup', 'create-admin', 'upgrade')]
    [string]$Action = 'deploy',

    [string]$VmHost,
    [string]$VmUser,
    [string]$KeyPath,
    [int]$SshPort,
    [string]$Domain,
    [string]$Email,
    [string]$Title,
    [int]$NodeMajor,
    [switch]$Production,
    [switch]$SkipDnsCheck,
    [switch]$SkipFirewall,
    [switch]$Yes,
    [string]$RemoteDir
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $ProjectRoot '.env'
$script:LastRemoteExitCode = 0

function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $name = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim()
        if ($value.Length -ge 2) {
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }
        Set-Item -Path "Env:$name" -Value $value
    }
}

function Quote-Bash {
    param([string]$Value)
    if ($null -eq $Value) { return "''" }
    return "'" + $Value.Replace("'", "'\''") + "'"
}

Import-DotEnv $EnvFile

if (-not $VmHost) { $VmHost = $env:VM_HOST }
if (-not $VmUser) { $VmUser = if ($env:VM_USER) { $env:VM_USER } else { 'opc' } }
if (-not $SshPort) { $SshPort = if ($env:SSH_PORT) { [int]$env:SSH_PORT } else { 22 } }
if (-not $KeyPath) { $KeyPath = $env:SSH_KEY }
if (-not $Domain) { $Domain = $env:DOMAIN }
if (-not $Email) { $Email = $env:LE_EMAIL }
if (-not $Title) { $Title = if ($env:SITE_TITLE) { $env:SITE_TITLE } else { 'My Mesh' } }
if (-not $NodeMajor) { $NodeMajor = if ($env:NODE_MAJOR) { [int]$env:NODE_MAJOR } else { 20 } }
if (-not $RemoteDir) { $RemoteDir = $env:REMOTE_DIR }
$UseProduction = $Production.IsPresent -or ($env:LE_PRODUCTION -eq 'true')

if (-not $VmHost) {
    throw 'VM host is required. Pass -VmHost or set VM_HOST in .env.'
}

if (-not $RemoteDir) {
    $homeDir = if ($VmUser -eq 'root') { '/root' } else { "/home/$VmUser" }
    $RemoteDir = "$homeDir/meshcentral-oracle"
}

if ($KeyPath) {
    if ($KeyPath.StartsWith('~')) {
        $KeyPath = Join-Path $HOME $KeyPath.Substring(1).TrimStart([char[]]@('\', '/'))
    }
    if (-not [System.IO.Path]::IsPathRooted($KeyPath)) {
        $KeyPath = Join-Path $ProjectRoot $KeyPath
    }
    if (-not (Test-Path -LiteralPath $KeyPath)) {
        throw "SSH key not found: $KeyPath"
    }
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    throw 'ssh was not found in PATH. Install the Windows OpenSSH client.'
}
if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
    throw 'scp was not found in PATH. Install the Windows OpenSSH client.'
}

$SshBase = @('-p', "$SshPort", '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=15', '-o', 'BatchMode=yes')
$ScpBase = @('-P', "$SshPort", '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=15', '-o', 'BatchMode=yes')
if ($KeyPath) {
    $SshBase += @('-i', $KeyPath)
    $ScpBase += @('-i', $KeyPath)
}

$Target = "$VmUser@$VmHost"
$Sudo = if ($VmUser -eq 'root') { '' } else { 'sudo ' }

function Invoke-Remote {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [switch]$Tty,
        [switch]$AllowFail
    )

    $sshArgs = @()
    if ($Tty) { $sshArgs += '-t' }
    $sshArgs += $SshBase
    $sshArgs += $Target
    $sshArgs += $Command

    & ssh @sshArgs
    $code = $LASTEXITCODE
    $script:LastRemoteExitCode = $code

    if (-not $AllowFail -and $code -ne 0) {
        throw "Remote command failed with exit code $code."
    }
}

function Invoke-Sudo {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [switch]$Tty,
        [switch]$AllowFail
    )
    Invoke-Remote -Command "$Sudo$Command" -Tty:$Tty -AllowFail:$AllowFail
}

function Sync-Bundle {
    Write-Host "==> Copying deployment bundle to ${Target}:$RemoteDir" -ForegroundColor Cyan
    Invoke-Remote -Command "mkdir -p $(Quote-Bash $RemoteDir)"
    Invoke-Remote -Command "rm -rf $(Quote-Bash "$RemoteDir/config") $(Quote-Bash "$RemoteDir/scripts") $(Quote-Bash "$RemoteDir/systemd")"

    # Use relative paths from the project root so scp never mistakes a Windows
    # drive letter such as C: for a remote host.
    $scpArgs = @()
    $scpArgs += $ScpBase
    $scpArgs += @('-r', 'config', 'scripts', 'systemd', "${Target}:$RemoteDir/")

    Push-Location $ProjectRoot
    try {
        & scp @scpArgs
        if ($LASTEXITCODE -ne 0) {
            throw "scp failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }

    Invoke-Remote -Command "chmod +x $(Quote-Bash "$RemoteDir/scripts")/*.sh"
}

try {
    Write-Host "==> Testing SSH connection to $Target" -ForegroundColor Cyan
    Invoke-Remote -Command 'echo ok' | Out-Null

    if ($VmUser -ne 'root') {
        Invoke-Remote -Command 'sudo -n true' -AllowFail
        if ($script:LastRemoteExitCode -ne 0) {
            throw "Passwordless sudo is required for '$VmUser'. Configure NOPASSWD or use -VmUser root."
        }
    }

    switch ($Action) {
        'deploy' {
            if (-not $Domain) { throw 'Domain is required for deploy. Pass -Domain or set DOMAIN in .env.' }
            if (-not $Email) { throw 'Email is required for deploy. Pass -Email or set LE_EMAIL in .env.' }

            Sync-Bundle

            $parts = @(
                'bash', (Quote-Bash "$RemoteDir/scripts/bootstrap.sh"),
                '--domain', (Quote-Bash $Domain),
                '--email', (Quote-Bash $Email),
                '--title', (Quote-Bash $Title),
                '--node-major', "$NodeMajor"
            )
            if ($UseProduction) { $parts += '--production' } else { $parts += '--staging' }
            if ($SkipDnsCheck) { $parts += '--skip-dns' }
            if ($SkipFirewall) { $parts += '--skip-firewall' }

            Invoke-Sudo -Command ($parts -join ' ')

            Write-Host ''
            Write-Host 'Bootstrap complete.' -ForegroundColor Green
            Write-Host "  1. Open https://$Domain and create the first account (site administrator)."
            Write-Host "  2. Run: .\deploy\deploy.ps1 -Action finalize -VmHost $VmHost -Domain $Domain -Yes"
            Write-Host "  3. Run: .\deploy\deploy.ps1 -Action promote  -VmHost $VmHost -Domain $Domain -Yes"
            Write-Host "  4. Log in, enroll 2FA, then add a device group and agent."
        }

        'finalize' {
            Sync-Bundle
            $cmd = "bash $(Quote-Bash "$RemoteDir/scripts/finalize.sh")"
            if ($Yes) { $cmd += ' --yes' }
            Invoke-Sudo -Command $cmd
        }

        'promote' {
            Sync-Bundle
            $cmd = "bash $(Quote-Bash "$RemoteDir/scripts/promote-le.sh")"
            if ($Domain) { $cmd += " --domain $(Quote-Bash $Domain)" }
            if ($Yes) { $cmd += ' --yes' }
            Invoke-Sudo -Command $cmd
        }

        'verify' {
            Sync-Bundle
            $cmd = "bash $(Quote-Bash "$RemoteDir/scripts/verify.sh")"
            if ($Domain) { $cmd += " --domain $(Quote-Bash $Domain)" }
            Invoke-Sudo -Command $cmd
        }

        'status' {
            Invoke-Remote -Command 'systemctl status meshcentral --no-pager -l' -AllowFail
            Write-Host ''
            Invoke-Remote -Command "ss -ltnp | grep -E ':(80|443)$' || true" -AllowFail
            Write-Host ''
            Invoke-Sudo -Command 'firewall-cmd --list-all || true' -AllowFail
        }

        'logs' {
            Invoke-Sudo -Command 'journalctl -u meshcentral -n 200 --no-pager -l'
        }

        'backup' {
            Sync-Bundle
            Invoke-Sudo -Command "bash $(Quote-Bash "$RemoteDir/scripts/backup-now.sh")"
        }

        'create-admin' {
            Sync-Bundle
            Invoke-Sudo -Command "bash $(Quote-Bash "$RemoteDir/scripts/create-admin.sh")" -Tty
        }

        'upgrade' {
            Sync-Bundle
            Invoke-Sudo -Command "bash $(Quote-Bash "$RemoteDir/scripts/upgrade.sh")"
        }
    }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
