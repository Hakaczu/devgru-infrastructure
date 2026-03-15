function Ensure-HyperVSwitchCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$SwitchDefinitions
    )

    $result = New-HyperVExecutionResult

    foreach ($item in @($SwitchDefinitions)) {
        $switchName = [string]$item.name
        $switchType = [string]($item.type | ForEach-Object { $_ })
        if ([string]::IsNullOrWhiteSpace($switchType)) {
            $switchType = 'Internal'
        }

        $switchAdapterName = [string]($item.adapter_name | ForEach-Object { $_ })
        $switchNotes = [string]($item.notes | ForEach-Object { $_ })

        $existingSwitch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
        if (-not $existingSwitch) {
            if ($switchType -eq 'External') {
                if ([string]::IsNullOrWhiteSpace($switchAdapterName)) {
                    throw "adapter_name is required when switch type is External for switch $switchName."
                }

                New-VMSwitch -Name $switchName -NetAdapterName $switchAdapterName -AllowManagementOS $true | Out-Null
            } else {
                New-VMSwitch -Name $switchName -SwitchType $switchType | Out-Null
            }

            $existingSwitch = Get-VMSwitch -Name $switchName -ErrorAction Stop
            Set-HyperVChanged -Result $result -Message "Created switch $switchName"
        }

        if (-not [string]::IsNullOrWhiteSpace($switchNotes) -and $existingSwitch.Notes -ne $switchNotes) {
            Set-VMSwitch -Name $switchName -Notes $switchNotes | Out-Null
            Set-HyperVChanged -Result $result -Message "Updated notes for switch $switchName"
        }
    }

    return $result
}