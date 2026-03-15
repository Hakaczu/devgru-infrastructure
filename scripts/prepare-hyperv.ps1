# --- CONFIGURATION ---
$UserName = "TerraformUser"
$Description = "Service account for Terraform automation"

# 1. Create or retrieve local user
if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {
    Write-Host "User $UserName already exists. Skipping creation and password change." -ForegroundColor Yellow
} else {
    Write-Host "Setting password for user $UserName..." -ForegroundColor Cyan
    $Password = Read-Host -Prompt "Enter a secure password" -AsSecureString
    # Added -PasswordNeverExpires flag so Terraform won't stop working after e.g., 42 days
    New-LocalUser -Name $UserName -Password $Password -Description $Description -FullName "Terraform Service Account" -PasswordNeverExpires
    Write-Host "User $UserName has been created." -ForegroundColor Green
}

# 2. Add to Hyper-V and Remote Management groups
Write-Host "Granting permissions..." -ForegroundColor Cyan
$Groups = @("Hyper-V Administrators", "Remote Management Users")

foreach ($Group in $Groups) {
    $GroupMembers = Get-LocalGroupMember -Group $Group -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    $UserPrincipal = "$env:COMPUTERNAME\$UserName"
    
    if ($GroupMembers -contains $UserPrincipal -or $GroupMembers -contains $UserName) {
        Write-Host "User $UserName is already in group $Group." -ForegroundColor Yellow
    } else {
        Add-LocalGroupMember -Group $Group -Member $UserName -ErrorAction Stop
        Write-Host "Added $UserName to group $Group." -ForegroundColor Green
    }
}

# 3. Configure WinRM (Windows Remote Management)
Write-Host "Configuring WinRM service..." -ForegroundColor Cyan
Enable-PSRemoting -Force
winrm quickconfig -quiet

# Increase memory limit for WinRM sessions (Terraform can process a lot of data and throw OOM in WinRM)
Set-Item -Path "WSMan:\localhost\Plugin\Microsoft.PowerShell\Quotas\MaxMemoryPerShellMB" -Value 1024 -Force

# Change authorization
# NOTE: Basic auth and Unencrypted are a security risk. 
# Considering the use of Tailscale network, this might be acceptable (traffic is already encrypted by WireGuard).
Set-Item -Path "WSMan:\localhost\Service\Auth\Basic" -Value $true -Force
Set-Item -Path "WSMan:\localhost\Service\AllowUnencrypted" -Value $true -Force

# 4. Open ports in Firewall
Write-Host "Configuring firewall (WinRM HTTP ports)..." -ForegroundColor Cyan
if (-not (Get-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "WinRM HTTP Terraform" -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow
} else {
    Enable-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -ErrorAction SilentlyContinue
}

Write-Host "`n--- DONE! ---" -ForegroundColor Cyan
Write-Host "Hyper-V host is ready for connection."
Write-Host "Use user: $UserName"