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

# 2. Create C:\Temp for Terraform provider script uploads
# The taliesins/hyperv provider copies temporary scripts to C:\Temp\ (the HYPERV_SCRIPT_PATH default).
# Without this folder the WinRM 'copy' command fails instantly → "Command has already been closed".
Write-Host "Creating C:\Temp for Terraform script uploads..." -ForegroundColor Cyan
if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" | Out-Null
    Write-Host "Created C:\Temp" -ForegroundColor Green
} else {
    Write-Host "C:\Temp already exists." -ForegroundColor Yellow
}

# Grant TerraformUser FullControl so the provider can write, execute, and clean up temp scripts
$Acl = Get-Acl "C:\Temp"
$Rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "$env:COMPUTERNAME\$UserName",
    "FullControl",
    "ContainerInherit,ObjectInherit",
    "None",
    "Allow"
)
$Acl.SetAccessRule($Rule)
Set-Acl -Path "C:\Temp" -AclObject $Acl
Write-Host "Granted FullControl on C:\Temp to $UserName." -ForegroundColor Green

# 3. Add to Hyper-V and Remote Management groups
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
# IMPORTANT: We use HTTPS (port 5986) with Basic auth to fix "Command has already been closed".
#
# Diagnosis: NTLM fails from macOS (Go ntlmssp library incompatibility with workgroup Windows).
# Basic auth works (HTTP 200), but over plain HTTP the connection closes between the WinRM shell-open
# and script-upload calls because HTTP/1.0-style Basic auth doesn't keep the connection alive.
#
# Solution: HTTPS (TLS) keeps the session persistent so the shell stays open across all WinRM calls.
# AllowUnencrypted is NOT needed anymore since we're using TLS.
Set-Item -Path "WSMan:\localhost\Service\Auth\Basic"    -Value $true -Force
Set-Item -Path "WSMan:\localhost\Service\Auth\Negotiate" -Value $true -Force  # Keep NTLM available as fallback

# Create a self-signed certificate for the WinRM HTTPS listener (if not already present)
$CertSubject = "CN=$env:COMPUTERNAME"
$ExistingCert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Subject -eq $CertSubject } | Select-Object -First 1

if (-not $ExistingCert) {
    Write-Host "Creating self-signed TLS certificate for WinRM HTTPS listener..." -ForegroundColor Cyan
    $ExistingCert = New-SelfSignedCertificate `
        -DnsName $env:COMPUTERNAME `
        -CertStoreLocation Cert:\LocalMachine\My `
        -KeyExportPolicy Exportable `
        -KeySpec KeyExchange
}
Write-Host "Using certificate: $($ExistingCert.Thumbprint)" -ForegroundColor Green

# Create (or update) the HTTPS WinRM listener on port 5986
# NOTE: Get-WSManInstance throws (instead of returning $null) when the listener doesn't exist yet,
# so we use try/catch for idempotent detection.
$ExistingHttpsListener = $null
try {
    $ExistingHttpsListener = Get-WSManInstance -ResourceURI winrm/config/Listener `
        -SelectorSet @{Address="*"; Transport="HTTPS"} -ErrorAction Stop
} catch { <# Listener doesn't exist yet - that's fine, we'll create it below #> }

if ($ExistingHttpsListener) {
    Write-Host "WinRM HTTPS listener already exists. Updating thumbprint..." -ForegroundColor Yellow
    Set-WSManInstance -ResourceURI winrm/config/Listener `
        -SelectorSet @{Address="*"; Transport="HTTPS"} `
        -ValueSet @{CertificateThumbprint=$ExistingCert.Thumbprint} | Out-Null
} else {
    Write-Host "Creating WinRM HTTPS listener on port 5986..." -ForegroundColor Cyan
    New-WSManInstance -ResourceURI winrm/config/Listener `
        -SelectorSet @{Address="*"; Transport="HTTPS"} `
        -ValueSet @{Hostname=$env:COMPUTERNAME; CertificateThumbprint=$ExistingCert.Thumbprint} | Out-Null
}

# 4. Open ports in Firewall
Write-Host "Configuring firewall (WinRM HTTP + HTTPS ports)..." -ForegroundColor Cyan
# HTTP (5985) - keep for backward compat
if (-not (Get-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "WinRM HTTP Terraform" -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow | Out-Null
} else {
    Enable-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -ErrorAction SilentlyContinue
}
# HTTPS (5986) - required by Terraform provider
if (-not (Get-NetFirewallRule -Name "WINRM-HTTPS-In-TCP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name "WINRM-HTTPS-In-TCP" -DisplayName "WinRM HTTPS Terraform" -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow | Out-Null
    Write-Host "Opened port 5986 (WinRM HTTPS)." -ForegroundColor Green
} else {
    Enable-NetFirewallRule -Name "WINRM-HTTPS-In-TCP" -ErrorAction SilentlyContinue
}

Write-Host "`n--- DONE! ---" -ForegroundColor Cyan
Write-Host "Hyper-V host is ready for connection."
Write-Host "Use user: $UserName"