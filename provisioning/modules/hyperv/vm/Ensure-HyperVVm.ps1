function Ensure-VhdFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$SizeGB,
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][pscustomobject]$Result
    )

    if ($SizeGB -le 0) {
        throw "size_gb must be greater than 0 for disk path $Path"
    }

    $diskDirectory = Split-Path -Path $Path -Parent
    if ([string]::IsNullOrWhiteSpace($diskDirectory)) {
        throw "Could not resolve parent directory for disk path: $Path"
    }

    if (-not (Test-Path -LiteralPath $diskDirectory)) {
        New-Item -Path $diskDirectory -ItemType Directory -Force | Out-Null
        Set-HyperVChanged -Result $Result -Message "Created disk directory $diskDirectory"
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($Type -eq 'fixed') {
            New-VHD -Path $Path -SizeBytes ($SizeGB * 1GB) -Fixed | Out-Null
        } else {
            New-VHD -Path $Path -SizeBytes ($SizeGB * 1GB) -Dynamic | Out-Null
        }

        Set-HyperVChanged -Result $Result -Message "Created VHD $Path"
    }
}

function Get-HyperVScsiCoordinates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$Index,
        [Parameter(Mandatory = $true)][int]$MaxControllers,
        [Parameter(Mandatory = $true)][int]$MaxLocations
    )

    $maxDisks = $MaxControllers * $MaxLocations
    if ($Index -ge $maxDisks) {
        throw "Requested disk index $Index exceeds SCSI capacity ($maxDisks slots)."
    }

    return [pscustomobject]@{
        ControllerNumber = [int][math]::Floor($Index / $MaxLocations)
        ControllerLocation = [int]($Index % $MaxLocations)
    }
}

function Add-HyperVVmDiskWithFallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$VmName,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$Index,
        [Parameter(Mandatory = $true)][int]$MaxControllers,
        [Parameter(Mandatory = $true)][int]$MaxLocations
    )

    $coords = Get-HyperVScsiCoordinates -Index $Index -MaxControllers $MaxControllers -MaxLocations $MaxLocations
    try {
        Add-VMHardDiskDrive -VMName $VmName -ControllerType SCSI -ControllerNumber $coords.ControllerNumber -ControllerLocation $coords.ControllerLocation -Path $Path -ErrorAction Stop | Out-Null
    } catch {
        Add-VMHardDiskDrive -VMName $VmName -Path $Path -ErrorAction Stop | Out-Null
    }
}

function Ensure-HyperVVirtualMachineCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$VmDefinitions,
        [Parameter(Mandatory = $true)][int]$MaxScsiControllers,
        [Parameter(Mandatory = $true)][int]$MaxScsiLocations,
        [Parameter(Mandatory = $true)][bool]$AllowDestroy,
        [Parameter(Mandatory = $true)][bool]$BootFromIsoOnCreate
    )

    $result = New-HyperVExecutionResult

    foreach ($item in @($VmDefinitions)) {
        $vmName = [string]$item.vm_name
        $targetState = [string]($item.state | ForEach-Object { $_ })
        if ([string]::IsNullOrWhiteSpace($targetState)) {
            $targetState = 'Running'
        }

        if ($targetState -eq 'Stopped') {
            $targetState = 'Off'
        }

        $generation = [int]$item.generation
        if ($generation -eq 0) {
            $generation = 2
        }

        $memoryMB = [int]$item.memory
        if ($memoryMB -eq 0) {
            $memoryMB = 2048
        }

        $processors = [int]$item.processors
        if ($processors -eq 0) {
            $processors = 2
        }

        $switchName = [string]$item.network_switch_name
        $isoPath = [string]($item.iso_path | ForEach-Object { $_ })
        $vmDisks = @($item.disks)

        if (-not $vmDisks -or $vmDisks.Count -eq 0) {
            throw "VM $vmName must define at least one disk in disks[]."
        }

        foreach ($disk in $vmDisks) {
            $diskPath = Normalize-HyperVPathKey -Path ([string]$disk.path)
            if ([string]::IsNullOrWhiteSpace($diskPath)) {
                throw "VM $vmName has a disk entry without path."
            }

            $diskType = [string]$disk.type
            if ($diskType -ne 'dynamic' -and $diskType -ne 'fixed') {
                throw "VM $vmName disk type '$diskType' is invalid. Allowed: dynamic, fixed."
            }

            if ([int]$disk.size_gb -le 0) {
                throw "VM $vmName disk $($disk.path) has invalid size_gb $($disk.size_gb)."
            }
        }

        if ($targetState -eq 'absent') {
            if (-not $AllowDestroy) {
                throw "Destroy requested for $vmName but hyperv_vm_allow_destroy is false."
            }

            $existingVm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($existingVm) {
                if ($existingVm.State -ne 'Off') {
                    Stop-VM -Name $vmName -Force -Confirm:$false | Out-Null
                }

                Remove-VM -Name $vmName -Force -Confirm:$false
                Set-HyperVChanged -Result $result -Message "Removed VM $vmName"
            }

            continue
        }

        if (-not (Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue)) {
            throw "Switch $switchName required by VM $vmName is missing on host."
        }

        $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
        $isNewVm = $false
        if (-not $vm) {
            $bootDisk = $vmDisks[0]
            $bootDiskPath = Normalize-HyperVPathKey -Path ([string]$bootDisk.path)
            Ensure-VhdFile -Path $bootDiskPath -SizeGB ([int]$bootDisk.size_gb) -Type ([string]$bootDisk.type) -Result $result

            New-VM -Name $vmName -Generation $generation -MemoryStartupBytes ($memoryMB * 1MB) -VHDPath $bootDiskPath -SwitchName $switchName | Out-Null

            for ($i = 1; $i -lt $vmDisks.Count; $i++) {
                $disk = $vmDisks[$i]
                $diskPath = Normalize-HyperVPathKey -Path ([string]$disk.path)
                Ensure-VhdFile -Path $diskPath -SizeGB ([int]$disk.size_gb) -Type ([string]$disk.type) -Result $result
                Add-HyperVVmDiskWithFallback -VmName $vmName -Path $diskPath -Index $i -MaxControllers $MaxScsiControllers -MaxLocations $MaxScsiLocations
            }

            Set-VMProcessor -VMName $vmName -Count $processors | Out-Null
            Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $false -StartupBytes ($memoryMB * 1MB) | Out-Null
            Set-HyperVChanged -Result $result -Message "Created VM $vmName"
            $isNewVm = $true
        } else {
            if ($vm.Generation -ne $generation) {
                throw "VM $vmName exists with generation $($vm.Generation), requested $generation. Recreate required."
            }

            $currentStartupMB = [int]($vm.MemoryStartup / 1MB)
            if ($currentStartupMB -ne $memoryMB) {
                Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $false -StartupBytes ($memoryMB * 1MB) | Out-Null
                Set-HyperVChanged -Result $result -Message "Updated memory for VM $vmName"
            }

            $currentProcessors = (Get-VMProcessor -VMName $vmName).Count
            if ($currentProcessors -ne $processors) {
                Set-VMProcessor -VMName $vmName -Count $processors | Out-Null
                Set-HyperVChanged -Result $result -Message "Updated processor count for VM $vmName"
            }

            $adapter = Get-VMNetworkAdapter -VMName $vmName -Name 'Network Adapter' -ErrorAction SilentlyContinue
            if ($adapter -and $adapter.SwitchName -ne $switchName) {
                Connect-VMNetworkAdapter -VMName $vmName -Name 'Network Adapter' -SwitchName $switchName | Out-Null
                Set-HyperVChanged -Result $result -Message "Reconnected network adapter for VM $vmName"
            }

            $attachedDisks = Get-VMHardDiskDrive -VMName $vmName -ErrorAction SilentlyContinue
            if (-not $attachedDisks) {
                $attachedDisks = @()
            }

            $attachedDiskPaths = @{}
            foreach ($attachedDisk in $attachedDisks) {
                if ($attachedDisk.Path) {
                    Register-HyperVAttachedDiskPathAliases -Path ([string]$attachedDisk.Path) -PathMap $attachedDiskPaths
                }
            }

            for ($i = 1; $i -lt $vmDisks.Count; $i++) {
                $disk = $vmDisks[$i]
                $diskPath = [string]$disk.path
                $diskPathKey = Normalize-HyperVPathKey -Path $diskPath
                if (-not $attachedDiskPaths.ContainsKey($diskPathKey)) {
                    Ensure-VhdFile -Path $diskPath -SizeGB ([int]$disk.size_gb) -Type ([string]$disk.type) -Result $result
                    Add-HyperVVmDiskWithFallback -VmName $vmName -Path $diskPath -Index $i -MaxControllers $MaxScsiControllers -MaxLocations $MaxScsiLocations
                    Set-HyperVChanged -Result $result -Message "Attached disk $diskPath to VM $vmName"
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($isoPath)) {
            if (-not (Test-Path -LiteralPath $isoPath)) {
                throw "ISO path for VM $vmName does not exist: $isoPath"
            }

            $dvdDrive = Get-VMDvdDrive -VMName $vmName -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $dvdDrive) {
                Add-VMDvdDrive -VMName $vmName -Path $isoPath | Out-Null
                Set-HyperVChanged -Result $result -Message "Attached ISO to VM $vmName"
                $dvdDrive = Get-VMDvdDrive -VMName $vmName -ErrorAction SilentlyContinue | Select-Object -First 1
            } elseif ($dvdDrive.Path -ne $isoPath) {
                Set-VMDvdDrive -VMName $vmName -ControllerNumber $dvdDrive.ControllerNumber -ControllerLocation $dvdDrive.ControllerLocation -Path $isoPath | Out-Null
                Set-HyperVChanged -Result $result -Message "Updated ISO for VM $vmName"
                $dvdDrive = Get-VMDvdDrive -VMName $vmName -ErrorAction SilentlyContinue | Select-Object -First 1
            }

            if ($isNewVm -and $BootFromIsoOnCreate -and $generation -eq 2 -and $dvdDrive) {
                Set-VMFirmware -VMName $vmName -FirstBootDevice $dvdDrive | Out-Null
                Set-HyperVChanged -Result $result -Message "Set ISO boot order for VM $vmName"
            }
        }

        $vm = Get-VM -Name $vmName -ErrorAction Stop
        if ($targetState -eq 'Running' -and $vm.State -ne 'Running') {
            Start-VM -Name $vmName | Out-Null
            Set-HyperVChanged -Result $result -Message "Started VM $vmName"
        }

        if ($targetState -eq 'Off' -and $vm.State -ne 'Off') {
            Stop-VM -Name $vmName -Force -Confirm:$false | Out-Null
            Set-HyperVChanged -Result $result -Message "Stopped VM $vmName"
        }
    }

    return $result
}