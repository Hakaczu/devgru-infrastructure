#Requires -RunAsAdministrator
<#
.SYNOPSIS
    One-time bootstrap: creates the service account used by Ansible for Hyper-V provisioning.

.DESCRIPTION
    Run this script ONCE on the Hyper-V host (locally or via RDP) before the first
    ansible-playbook run. After this, use provisioning/ansible/hyperv/playbooks/host_prep.yml
    for all further configuration.

.EXAMPLE
    # Run in an elevated PowerShell on the Hyper-V host:
    .\bootstrap-ansible-user.ps1

    # Override defaults:
    .\bootstrap-ansible-user.ps1 -UserName "AnsibleUser" -Port 5986
#>
param(
    [string] $UserName    = "AnsibleUser",
    [string] $Description = "Service account for Ansible / Hyper-V automation",
    [int]    $Port        = 5986
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Msg) Write-Host "`n=== $Msg ===" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "    OK  $Msg"  -ForegroundColor Green }
function Write-Skip { param([string]$Msg) Write-Host "    --  $Msg (skipped, already done)" -ForegroundColor Yellow }

# ── 1. Create user ────────────────────────────────────────────────────────────
Write-Step "Creating local user: $UserName"

if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {
    Write-Skip "User $UserName already exists"
} else {
    $Password = Read-Host -Prompt "Set password for $UserName" -AsSecureString
    New-LocalUser `
        -Name             $UserName `
        -Password         $Password `
        -Description      $Description `
        -PasswordNeverExpires `
        -UserMayNotChangePassword | Out-Null
    Write-Ok "User $UserName created"
}

# ── 2. Group membership (SID-based, locale-safe) ──────────────────────────────
Write-Step "Adding $UserName to required groups"

$Groups = @(
    @{ SID = 'S-1-5-32-544'; Label = 'Administrators' },        # needed for WinRM bootstrap
    @{ SID = 'S-1-5-32-578'; Label = 'Hyper-V Administrators' },
    @{ SID = 'S-1-5-32-580'; Label = 'Remote Management Users' }
)

foreach ($g in $Groups) {
    $Group = Get-LocalGroup | Where-Object { $_.SID.Value -eq $g.SID }
    if (-not $Group) {
        Write-Host "    !!  Group $($g.Label) not found (SID $($g.SID)) - is the feature installed?" -ForegroundColor Red
        continue
    }
    $Members = Get-LocalGroupMember -Group $Group.Name -ErrorAction SilentlyContinue |
               Select-Object -ExpandProperty Name
    $Principal = "$env:COMPUTERNAME\$UserName"
    if ($Members -contains $Principal -or $Members -contains $UserName) {
        Write-Skip "$UserName already in $($Group.Name)"
    } else {
        Add-LocalGroupMember -Group $Group.Name -Member $UserName
        Write-Ok "Added $UserName to $($Group.Name)"
    }
}

# ── 3. Ensure WinRM HTTPS listener ────────────────────────────────────────────
Write-Step "Configuring WinRM HTTPS listener on port $Port"

Enable-PSRemoting -Force | Out-Null
winrm quickconfig -quiet | Out-Null

$Subject = "CN=$env:COMPUTERNAME"
$Cert    = Get-ChildItem Cert:\LocalMachine\My |
           Where-Object { $_.Subject -eq $Subject } |
           Select-Object -First 1

if (-not $Cert) {
    $Cert = New-SelfSignedCertificate `
        -DnsName            $env:COMPUTERNAME `
        -CertStoreLocation  Cert:\LocalMachine\My `
        -KeyExportPolicy    Exportable `
        -KeySpec            KeyExchange
    Write-Ok "Self-signed certificate created: $($Cert.Thumbprint)"
} else {
    Write-Skip "Certificate already exists: $($Cert.Thumbprint)"
}

$Listener = $null
try {
    $Listener = Get-WSManInstance -ResourceURI winrm/config/Listener `
        -SelectorSet @{ Address = '*'; Transport = 'HTTPS' } -ErrorAction Stop
} catch { $Listener = $null }

if ($Listener) {
    Write-Skip "HTTPS listener already exists"
} else {
    New-WSManInstance -ResourceURI winrm/config/Listener `
        -SelectorSet @{ Address = '*'; Transport = 'HTTPS' } `
        -ValueSet    @{ Hostname = $env:COMPUTERNAME; CertificateThumbprint = $Cert.Thumbprint } | Out-Null
    Write-Ok "WinRM HTTPS listener created on port $Port"
}

Set-Item -Path 'WSMan:\localhost\Service\Auth\Basic'    -Value $true -Force
Set-Item -Path 'WSMan:\localhost\Service\Auth\Negotiate' -Value $true -Force

# ── 4. Firewall ───────────────────────────────────────────────────────────────
Write-Step "Opening firewall port $Port (WinRM HTTPS)"

$RuleName = "WINRM-HTTPS-In-TCP"
if (Get-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue) {
    Enable-NetFirewallRule -Name $RuleName
    Write-Skip "Firewall rule $RuleName already exists (ensured enabled)"
} else {
    New-NetFirewallRule `
        -Name        $RuleName `
        -DisplayName "WinRM HTTPS Ansible" `
        -Direction   Inbound `
        -LocalPort   $Port `
        -Protocol    TCP `
        -Action      Allow | Out-Null
    Write-Ok "Firewall rule created for port $Port"
}

Restart-Service winrm
Write-Ok "WinRM service restarted"

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "Host is ready for Ansible connection."
Write-Host ""
Write-Host "Next steps on the control node:"
Write-Host "  1. Copy inventory sample:"
Write-Host "     cp provisioning/ansible/hyperv/inventory/sample.ini provisioning/ansible/hyperv/inventory/production.ini"
Write-Host ""
Write-Host "  2. Set the password in group_vars and encrypt:"
Write-Host "     cp provisioning/ansible/hyperv/group_vars/hyperv_hosts/secrets.example.yml \"
Write-Host "        provisioning/ansible/hyperv/group_vars/hyperv_hosts/secrets.yml"
Write-Host "     # edit secrets.yml: ansible_password: '<password you just set>'"
Write-Host "     ansible-vault encrypt provisioning/ansible/hyperv/group_vars/hyperv_hosts/secrets.yml"
Write-Host ""
Write-Host "  3. Test connection:"
Write-Host "     cd provisioning/ansible/hyperv"
Write-Host "     ansible hyperv_hosts -m ansible.windows.win_ping --vault-password-file ~/.ansible/vault_pass.txt"
Write-Host ""
Write-Host "  4. Run full host preparation:"
Write-Host "     ansible-playbook playbooks/host_prep.yml --vault-password-file ~/.ansible/vault_pass.txt"
