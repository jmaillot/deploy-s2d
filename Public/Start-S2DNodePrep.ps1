function Start-S2DNodePrep {
<#
.SYNOPSIS
Local node preparation. Run locally on EACH node.
.DESCRIPTION
Renames NICs, sets storage MTU/IP, QoS/RDMA, vSwitch, VMQ/RSC, live migration.
MgmtAdapters and VMAdapters accept any count (one or more): supply a comma list,
or answer the Mandatory prompt per adapter and press Enter on a blank line to finish.
Two or more VM adapters create a SET team; a single one creates a plain vSwitch.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        # NIC names. Omit any of them to pick from a menu of local physical
        # adapters (already-picked NICs are excluded from later menus).
        [string[]]$MgmtAdapters = @(),
        [string[]]$VMAdapters = @(),
        [string]$StorageA = "",
        [string]$StorageB = "",
        [string]$LiveMigrationAdapter = "",
        [Parameter(Mandatory = $true)]
        [string]$StorageAIP,
        [Parameter(Mandatory = $true)]
        [string]$StorageBIP,
        [int]$StoragePrefix = 24
    )

    Write-S2DLog "== NodePrep - Starting on $(hostname) =="
    Write-Host "== NodePrep - Starting on $(hostname) ==" -ForegroundColor Cyan

    # NIC discovery: anything not supplied is picked interactively.
    $picked = @()
    Write-Host "NIC discovery: pick in the console (Q aborts). Titles name the role." -ForegroundColor Cyan
    if ([string]::IsNullOrWhiteSpace($StorageA))             { $StorageA = Select-S2DNic -Title "StorageA (1/5)" -Help "This adapter will be RENAMED to StorageA (fabric A). 10GbE+ RDMA required - preflight checks next." -Exclude $picked; $picked += $StorageA }
    if ([string]::IsNullOrWhiteSpace($StorageB))             { $StorageB = Select-S2DNic -Title "StorageB (2/5)" -Help "This adapter will be RENAMED to StorageB (fabric B). 10GbE+ RDMA required - preflight checks next." -Exclude $picked; $picked += $StorageB }
    if ([string]::IsNullOrWhiteSpace($LiveMigrationAdapter)) { $LiveMigrationAdapter = Select-S2DNic -Title "LiveMigration (3/5)" -Help "This adapter will be RENAMED to LiveMig. Exactly 1 by design; 10GbE+ RDMA required." -Exclude $picked; $picked += $LiveMigrationAdapter }
    if (-not $MgmtAdapters -or $MgmtAdapters.Count -eq 0)    { $MgmtAdapters = @(Select-S2DNic -Title "MGMT (4/5)" -Help "Pick 1 or more adapters; they will be RENAMED to Mgmt1..N." -Exclude $picked -Multi); $picked += $MgmtAdapters }
    if (-not $VMAdapters -or $VMAdapters.Count -eq 0)        { $VMAdapters = @(Select-S2DNic -Title "VM vSwitch (5/5)" -Help "Pick 1 or more adapters; they will be RENAMED to VM1..N. 2+ = SET team, 1 = plain vSwitch." -Exclude $picked -Multi); $picked += $VMAdapters }
    $dupes = (@($StorageA, $StorageB, $LiveMigrationAdapter) + $MgmtAdapters + $VMAdapters | Group-Object | Where-Object {$_.Count -gt 1})
    if ($dupes) { throw "NIC(s) assigned to multiple roles: $($dupes.Name -join ', ')." }

    Write-S2DLog "Preflight - 10 Gbps + RDMA on storage/LiveMig (original names)"
    $minLinkBps = 10000000000
    foreach ($iface in @($StorageA, $StorageB, $LiveMigrationAdapter)) {
        $cim = Get-CimInstance Win32_NetworkAdapter -Filter "NetConnectionID = '$iface'" -ErrorAction SilentlyContinue
        if (-not $cim) { throw "Preflight failed: NIC '$iface' not found on $(hostname)." }
        if ($null -eq $cim.Speed -or $cim.Speed -lt $minLinkBps) {
            $seen = if ($null -eq $cim.Speed) { "unknown (disconnected?)" } else { ([math]::Round($cim.Speed/1e9,1)).ToString() + " Gbps" }
            throw "Preflight failed: '$iface' link is $seen, 10 Gbps minimum required (Storage/LiveMig)."
        }
        $smbNic = Get-SmbClientNetworkInterface -ErrorAction SilentlyContinue | Where-Object {$_.InterfaceAlias -eq $iface}
        if ($smbNic -and -not $smbNic.RdmaCapable) {
            throw "Preflight failed: '$iface' is not RDMA-capable."
        }
    }

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

        Write-S2DLog "vSwitch - $(hostname)"
        if (-not (Get-VMSwitch -Name "vSwitch-VM" -ErrorAction SilentlyContinue)) {
            if ($RenamedVMAdapters.Count -ge 2) {
                New-VMSwitch -Name "vSwitch-VM" -EnableEmbeddedTeaming $true -AllowManagementOS $false -NetAdapterName $RenamedVMAdapters | Out-Null
            } elseif ($RenamedVMAdapters.Count -eq 1) {
                New-VMSwitch -Name "vSwitch-VM" -AllowManagementOS $false -NetAdapterName $RenamedVMAdapters | Out-Null
            } else {
                throw "VMAdapters requires at least one adapter."
            }
        }

        Write-S2DLog "VMQ/RSC - $(hostname)"
        Get-NetAdapterVmq -Name $RenamedVMAdapters -ErrorAction SilentlyContinue | Where-Object {$_.Enabled} | Disable-NetAdapterVmq -NoRestart
        Get-NetAdapterRsc -Name $RenamedVMAdapters -ErrorAction SilentlyContinue | Disable-NetAdapterRsc -ErrorAction SilentlyContinue
        Get-VMSwitch -Name "vSwitch-VM" | Set-VMSwitch -EnableSoftwareRsc $false

        Set-VMHost -VirtualMachineMigrationPerformanceOption SMB
    }

    Write-S2DLog "== NodePrep - Finished on $(hostname) =="
}
