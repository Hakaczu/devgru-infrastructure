function New-HyperVExecutionResult {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        Changed = $false
        Operations = New-Object System.Collections.Generic.List[string]
    }
}

function Add-HyperVOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Result,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $Result.Operations.Add($Message) | Out-Null
}

function Set-HyperVChanged {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Result,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $Result.Changed = $true
    Add-HyperVOperation -Result $Result -Message $Message
}

function Normalize-HyperVPathKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $value = $Path.Trim().ToLowerInvariant()
    if ($value.StartsWith('\\?\')) {
        $value = $value.Substring(4)
    }

    if ($value -match '^[a-z]:') {
        while ($value -like '*\\*') {
            $value = $value -replace '\\\\', '\\'
        }
    }

    return $value
}

function Register-HyperVAttachedDiskPathAliases {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$PathMap
    )

    $currentPath = $Path
    for ($depth = 0; $depth -lt 16; $depth++) {
        if ([string]::IsNullOrWhiteSpace($currentPath)) {
            break
        }

        $normalized = Normalize-HyperVPathKey -Path $currentPath
        if (-not $PathMap.ContainsKey($normalized)) {
            $PathMap[$normalized] = $true
        }

        $vhdInfo = Get-VHD -Path $currentPath -ErrorAction SilentlyContinue
        if (-not $vhdInfo -or [string]::IsNullOrWhiteSpace($vhdInfo.ParentPath)) {
            break
        }

        $parentPath = [string]$vhdInfo.ParentPath
        $parentNormalized = Normalize-HyperVPathKey -Path $parentPath
        if ($parentNormalized -eq $normalized) {
            break
        }

        $currentPath = $parentPath
    }
}