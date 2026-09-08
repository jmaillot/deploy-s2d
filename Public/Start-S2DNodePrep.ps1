function Start-S2DNodePrep {
<#
.SYNOPSIS
Local node preparation. Run locally on EACH node.
.DESCRIPTION
Renames NICs, sets storage MTU/IP, QoS/RDMA, vSwitch SET, VMQ/RSC, live migration.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string[]]$MgmtAdapters = @("Ethernet 1","Ethernet 2"),
        [string[]]$VMAdapters   = @("Ethernet 3","Ethernet 4"),
        [string]$StorageA = "Ethernet 5",
        [string]$StorageB = "Ethernet 6",
        [string]$LiveMigrationAdapter = "Ethernet 7",
        [string]$StorageAIP,
        [string]$StorageBIP,
        [int]$StoragePrefix = 24
    )

    Write-S2DLog "== NodePrep - Starting on $(hostname) =="
    Write-Host "== NodePrep - Starting on $(hostname) ==" -ForegroundColor Cyan

    Write-S2DLog "NIC renaming - $(hostname)"
    if ($PSCmdlet.ShouldProcess($(hostname), "Rename NICs to StorageA/StorageB/LiveMig/MgmtN/VMN")) {
        Rename-NetAdapter -Name $StorageA -NewName "StorageA" -ErrorAction SilentlyContinue | Out-Null
        Rename-NetAdapter -Name $StorageB -NewName "StorageB" -ErrorAction SilentlyContinue | Out-Null
        Rename-NetAdapter -Name $LiveMigrationAdapter -NewName "LiveMig" -ErrorAction SilentlyContinue | Out-Null
    }
    $RenamedMgmtAdapters = @()
    for ($i = 0; $i -lt $MgmtAdapters.Count; $i++) {
        $mgmtNewName = "Mgmt$($i + 1)"
        if ($PSCmdlet.ShouldProcess($MgmtAdapters[$i], "Rename to $mgmtNewName")) {
            Rename-NetAdapter -Name $MgmtAdapters[$i] -NewName $mgmtNewName -ErrorAction SilentlyContinue | Out-Null
        }
        $RenamedMgmtAdapters += $mgmtNewName
    }
    $RenamedVMAdapters = @()
    for ($i = 0; $i -lt $VMAdapters.Count; $i++) {
        $newName = "VM$($i + 1)"
        if ($PSCmdlet.ShouldProcess($VMAdapters[$i], "Rename to $newName")) {
            Rename-NetAdapter -Name $VMAdapters[$i] -NewName $newName -ErrorAction SilentlyContinue | Out-Null
        }
        $RenamedVMAdapters += $newName
    }

    if ($PSCmdlet.ShouldProcess($(hostname), "Configure storage MTU/IP, QoS/RDMA, vSwitch, VMQ/RSC")) {
        Write-S2DLog "Storage MTU + IP - $(hostname)"
        foreach ($st in @("StorageA","StorageB")) {
            try { Set-NetAdapterAdvancedProperty -Name $st -RegistryKeyword "*JumboPacket" -RegistryValue 9014 -ErrorAction Stop } catch { Write-Verbose "JumboPacket not supported on $st, skipping." }
        }

        Set-NetIPInterface -InterfaceAlias "StorageA" -Dhcp Disabled
        Set-NetIPInterface -InterfaceAlias "StorageB" -Dhcp Disabled
        if ($StorageAIP) { Remove-NetIPAddress -InterfaceAlias "StorageA" -IPAddress $StorageAIP -Confirm:$false -ErrorAction SilentlyContinue }
        if ($StorageBIP) { Remove-NetIPAddress -InterfaceAlias "StorageB" -IPAddress $StorageBIP -Confirm:$false -ErrorAction SilentlyContinue }
        if ($StorageAIP) { New-NetIPAddress -InterfaceAlias "StorageA" -IPAddress $StorageAIP -PrefixLength $StoragePrefix | Out-Null }
        if ($StorageBIP) { New-NetIPAddress -InterfaceAlias "StorageB" -IPAddress $StorageBIP -PrefixLength $StoragePrefix | Out-Null }

        Write-S2DLog "QoS + RDMA - $(hostname)"
        Remove-NetQosPolicy -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetQosTrafficClass -Confirm:$false -ErrorAction SilentlyContinue
        Disable-NetQosFlowControl -Priority 0,1,2,3,4,5,6,7
        New-NetQosPolicy "SMBDirect" -NetDirectPortMatchCondition 445 -PriorityValue8021Action 3 | Out-Null
        Enable-NetQosFlowControl -Priority 3 | Out-Null

        foreach ($iface in @("StorageA","StorageB","LiveMig")) {
            Set-NetQosDcbxSetting -InterfaceAlias $iface -Willing $false -Confirm:$false
            Get-NetAdapterQos -Name $iface | Enable-NetAdapterQos
            Get-NetAdapterRdma -Name $iface -ErrorAction SilentlyContinue | Enable-NetAdapterRdma
        }

        Write-S2DLog "vSwitch SET - $(hostname)"
        if (-not (Get-VMSwitch -Name "vSwitch-VM" -ErrorAction SilentlyContinue)) {
            New-VMSwitch -Name "vSwitch-VM" -EnableEmbeddedTeaming $true -AllowManagementOS $false -NetAdapterName $RenamedVMAdapters | Out-Null
        }

        Write-S2DLog "VMQ/RSC - $(hostname)"
        Get-NetAdapterVmq -Name $RenamedVMAdapters -ErrorAction SilentlyContinue | Where-Object {$_.Enabled} | Disable-NetAdapterVmq -NoRestart
        Get-NetAdapterRsc -Name $RenamedVMAdapters -ErrorAction SilentlyContinue | Disable-NetAdapterRsc -ErrorAction SilentlyContinue
        Get-VMSwitch -Name "vSwitch-VM" | Set-VMSwitch -EnableSoftwareRsc $false

        Set-VMHost -VirtualMachineMigrationPerformanceOption SMB
    }

    Write-S2DLog "== NodePrep - Finished on $(hostname) =="
}
