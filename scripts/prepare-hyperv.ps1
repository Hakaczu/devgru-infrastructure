# --- CONFIGURATION ---
$UserName = "TerraformUser"
$Description = "Service account for Terraform automation"

# 1. Create or retrieve local user
if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {
    Write-Host "User $UserName already exists. Skipping creation and password change." -ForegroundColor Yellow
} else {
    Write-Host "Setting password for user $UserName..." -ForegroundColor Cyan
    $Password = Read-Host -Prompt "Enter a secure password" -AsSecureString
    
    Write-Host "Creating user account $UserName..." -ForegroundColor Cyan
    New-LocalUser -Name $UserName -Password $Password -Description $Description -PasswordNeverExpires | Out-Null

    # Force profile creation using WMI to avoid "Command has already been closed" errors in WinRM
    # Start-Process with -LoadUserProfile often fails with "Invalid directory" depending on the context.
    Write-Host "Forcing user profile creation for $UserName using WMI/CIM..." -ForegroundColor Cyan
    $domain = $env:COMPUTERNAME
    
    # Win32_UserProfile creation hack via instantiating a process as the user using WMI
    $proc = [WMICLASS]"root\cimv2:Win32_Process"
    $startup = [WMICLASS]"root\cimv2:Win32_ProcessStartup"
    $startupProperties = $startup.CreateInstance()
    $startupProperties.ShowWindow = 0 # Hidden
    
    # Try creating profile by launching a dummy process
    $result = $proc.Create("cmd.exe /c exit", "C:\", $startupProperties)
    
    # Fallback/Alternative: Create process using CIM with credentials if needed (WinRM context setup)
    try {
        $CimSession = New-CimSession -ComputerName localhost 
        Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
            CommandLine = "cmd.exe /c exit"
        } -CimSession $CimSession | Out-Null
    } catch {
        Write-Host "CIM Method failed: $_" -ForegroundColor Yellow
    }
    
    # An alternative and more reliable way in PowerShell to load profile is using a quick scheduled task
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-Command exit"
    $Principal = New-ScheduledTaskPrincipal -UserId "$domain\$UserName" -LogonType Interactive
    $Task = New-ScheduledTask -Action $Action -Principal $Principal
    Register-ScheduledTask -TaskName "LoadProfile_$UserName" -InputObject $Task -Force | Out-Null
    Start-ScheduledTask -TaskName "LoadProfile_$UserName"
    Start-Sleep -Seconds 5
    Unregister-ScheduledTask -TaskName "LoadProfile_$UserName" -Confirm:$false | Out-Null
    
    Write-Host "User profile created successfully." -ForegroundColor Green
}

# 2. Add to Hyper-V and Remote Management groups
Write-Host "Granting permissions..." -ForegroundColor Cyan

# Use Built-In SIDs to avoid issues with OS localization (e.g. Polish group names)
$GroupConfigs = @(
    @{ SID = "S-1-5-32-578"; Name = "Hyper-V Administrators" },
    @{ SID = "S-1-5-32-580"; Name = "Remote Management Users" }
)

foreach ($Config in $GroupConfigs) {
    # Resolve the local group name from its SID
    $LocalGroup = Get-LocalGroup | Where-Object { $_.SID -eq $Config.SID }
    
    if (-not $LocalGroup) {
        Write-Host "Group $($Config.Name) (SID: $($Config.SID)) was not found. Is the feature installed?" -ForegroundColor Red
        continue
    }

    $GroupName = $LocalGroup.Name
    $GroupMembers = Get-LocalGroupMember -Group $GroupName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    $UserPrincipal = "$env:COMPUTERNAME\$UserName"
    
    if ($GroupMembers -contains $UserPrincipal -or $GroupMembers -contains $UserName) {
        Write-Host "User $UserName is already in group $GroupName." -ForegroundColor Yellow
    } else {
        Add-LocalGroupMember -Group $GroupName -Member $UserName -ErrorAction Stop
        Write-Host "Added $UserName to group $GroupName." -ForegroundColor Green
    }
}

# 3. Configure WinRM (Windows Remote Management)
Write-Host "Configuring WinRM service..." -ForegroundColor Cyan
Enable-PSRemoting -Force
winrm quickconfig -quiet

# Increase memory limit for WinRM sessions (Terraform can process a lot of data and throw OOM in WinRM)
# The global Shell\MaxMemoryPerShellMB must be >= the per-plugin quota, otherwise Windows warns and ignores it.
Set-Item -Path "WSMan:\localhost\Shell\MaxMemoryPerShellMB"                      -Value 2048 -Force
Set-Item -Path "WSMan:\localhost\Plugin\Microsoft.PowerShell\Quotas\MaxMemoryPerShellMB" -Value 2048 -Force

# Prevent "Command has already been closed" errors by raising timeout and shell quota limits.
# The dmacvicar/hyperv provider opens a WinRM shell, uploads a PS script, then runs it.
# If Windows closes the shell between those two steps (low timeout or shell quota), it throws the above error.
Set-Item -Path "WSMan:\localhost\MaxTimeoutms"            -Value 1800000 -Force  # 30 min (default: 60 s)
Set-Item -Path "WSMan:\localhost\Shell\MaxShellsPerUser"  -Value 30      -Force  # (default: 5)
# NOTE: MaxConcurrentOperationsPerUser path was removed in Windows 10/11 & Server 2019+ - skip it.

# Restart WinRM so the timeout/quota changes above take effect immediately.
Write-Host "Restarting WinRM service to apply configuration changes..." -ForegroundColor Cyan
Restart-Service winrm

# Change authorization
# The taliesins/hyperv Terraform provider uses NTLM auth (use_ntlm = true in provider config).
# NTLM is connection-based: credentials are negotiated once and the HTTP connection is kept alive.
# This is what prevents "Command has already been closed" - the shell stays open across all WinRM calls.
#
# Basic auth re-authenticates per-request, causing Windows to close the shell between the
# shell-open and script-upload calls, breaking the provider.
#
# AllowUnencrypted is still required because we're on HTTP/5985 (not HTTPS).
# Tailscale/WireGuard encrypts all traffic at the network layer anyway.
Set-Item -Path "WSMan:\localhost\Service\Auth\Negotiate" -Value $true  -Force  # Enables NTLM/Kerberos
Set-Item -Path "WSMan:\localhost\Service\Auth\Basic"     -Value $true  -Force  # Kept as fallback
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