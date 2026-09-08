function Start-S2DNodePrep {
<#
.SYNOPSIS
Local node preparation. Run locally on EACH node, elevated.
.DESCRIPTION
Renames NICs, sets storage MTU/IP, QoS/RDMA, vSwitch, VMQ/RSC, live migration.
MgmtAdapters and VMAdapters accept any count (one or more); omitted NIC names
are picked via console menu. Two or more VM adapters create a SET team; a single
one creates a plain vSwitch. Exactly 2 storage adapters (StorageA/B) and exactly
1 LiveMigration adapter. Minimum 4 physical NICs. Optional -LiveMigrationIP binds
the migration network; without it LiveMig stays unbound (warning).
.PARAMETER MgmtAdapters
Pre-rename management NIC names. Omit to pick from a console menu.
.PARAMETER VMAdapters
Pre-rename vSwitch NIC names (1+). Omit to pick from a console menu.
.PARAMETER StorageA
Pre-rename NIC for fabric A (exactly 1). Omit to pick.
.PARAMETER StorageB
Pre-rename NIC for fabric B (exactly 1). Omit to pick.
.PARAMETER LiveMigrationAdapter
Pre-rename NIC for live migration (exactly 1, by design). Omit to pick.
.PARAMETER StorageAIP
This node's StorageA IP. Must differ from StorageBIP and sit on another subnet.
.PARAMETER StorageBIP
This node's StorageB IP. Must differ from StorageAIP and sit on another subnet.
.PARAMETER StoragePrefix
Storage subnet prefix length. Default 24.
.PARAMETER LiveMigrationIP
Optional. LiveMig IP; when supplied the migration network is bound to its
subnet, otherwise LiveMig stays unbound (warning).
.PARAMETER LiveMigrationPrefix
LiveMig subnet prefix length. Default 24.
.PARAMETER LogPath
Log file path. Default C:\S2D_Deployment.log.
.EXAMPLE
Start-S2DNodePrep -MgmtAdapters "Mgmt01","Mgmt02" -VMAdapters "Vm01","Vm02" -StorageA "Storage01" -StorageB "Storage02" -LiveMigrationAdapter "Live01" -StorageAIP "192.168.200.1" -StorageBIP "192.168.201.1"
.EXAMPLE
Start-S2DNodePrep -StorageAIP "192.168.200.1" -StorageBIP "192.168.201.1" -WhatIf
Dry run with NIC picker guiding every adapter choice.
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType()]
    param(
        # NIC names. Omit any of them to pick from a menu of local physical
        # adapters (already-picked NICs are excluded from later menus).
        [ValidateScript({ if ($_ -match '[\*\?\[\]]') { throw "Wildcard characters not allowed in NIC names: '$_'." } $true })]
        [string[]]$MgmtAdapters = @(),
        [ValidateScript({ if ($_ -match '[\*\?\[\]]') { throw "Wildcard characters not allowed in NIC names." } $true })]
        [string[]]$VMAdapters = @(),
        [ValidateScript({ if ($_ -match '[\*\?\[\]]') { throw "Wildcard characters not allowed in NIC names: '$_'." } $true })]
        [string]$StorageA = "",
        [ValidateScript({ if ($_ -match '[\*\?\[\]]') { throw "Wildcard characters not allowed in NIC names: '$_'." } $true })]
        [string]$StorageB = "",
        [ValidateScript({ if ($_ -match '[\*\?\[\]]') { throw "Wildcard characters not allowed in NIC names: '$_'." } $true })]
        [string]$LiveMigrationAdapter = "",
        [ValidateScript({ try { [void][System.Net.IPAddress]::Parse($_); $true } catch { throw "'$_' is not a valid IP address." } })]
        [Parameter(Mandatory = $true)]
        [string]$StorageAIP,
        [ValidateScript({ try { [void][System.Net.IPAddress]::Parse($_); $true } catch { throw "'$_' is not a valid IP address." } })]
        [Parameter(Mandatory = $true)]
        [string]$StorageBIP,
        [ValidateRange(1, 31)]
        [int]$StoragePrefix = 24,
        [ValidateScript({ if ([string]::IsNullOrWhiteSpace($_)) { $true } else { try { [void][System.Net.IPAddress]::Parse($_); $true } catch { throw "'$_' is not a valid IP address." } } })]
        [string]$LiveMigrationIP = "",
        [ValidateRange(1, 31)]
        [int]$LiveMigrationPrefix = 24,
        [string]$LogPath = "C:\S2D_Deployment.log"
    )

    $script:S2DLogPath = $LogPath
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw "Start-S2DNodePrep requires elevation. Run PowerShell as Administrator." }

    if ($StorageAIP -eq $StorageBIP) { throw "StorageAIP and StorageBIP must differ." }
    if ($LiveMigrationIP -and ($LiveMigrationIP -eq $StorageAIP -or $LiveMigrationIP -eq $StorageBIP)) {
        throw "LiveMigrationIP must differ from both storage IPs."
    }
    $aBytes = ([System.Net.IPAddress]$StorageAIP).GetAddressBytes()
    $bBytes = ([System.Net.IPAddress]$StorageBIP).GetAddressBytes()
    $maskBytes = for ($i = 0; $i -lt 4; $i++) { $bits = [math]::Max(0, [math]::Min(8, $StoragePrefix - $i * 8)); [byte](256 - [math]::Pow(2, (8 - $bits))) }
    $sameSubnet = $true
    for ($i = 0; $i -lt 4; $i++) { if (($aBytes[$i] -band $maskBytes[$i]) -ne ($bBytes[$i] -band $maskBytes[$i])) { $sameSubnet = $false } }
    if ($sameSubnet) { throw "StorageAIP and StorageBIP must be on different subnets (multipath failover)." }

    $physCount = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue).Count
    if ($physCount -lt 4) { throw "Preflight failed: found $physCount physical NIC(s), minimum 4 (StorageA/B + LiveMig + 1 VM)." }

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
        if ($smbNic) {
            if (-not $smbNic.RdmaCapable) { throw "Preflight failed: '$iface' is not RDMA-capable." }
        } else {
            $rdmaSetting = Get-NetAdapterRdma -Name $iface -ErrorAction SilentlyContinue
            if ($null -eq $rdmaSetting) { throw "Preflight failed: '$iface' RDMA capability unproven (no SMB binding info, no RDMA settings). Install/enable the RDMA stack first." }
            Write-Warning "Preflight: '$iface' has no SMB binding info yet; RDMA presence inferred from adapter settings only."
        }
    }

    Write-S2DLog "Preflight - storage (Dell: HBA mode + media tiers)"
    $poolable = @(Get-S2DPoolableDisk)
    if ($poolable.Count -eq 0) {
        throw "Preflight failed: no poolable disks (CanPool). PERC in RAID mode? S2D needs HBA/pass-through so physical disks are visible."
    }
    if (@($poolable | Where-Object {$_.MediaType -ne 'HDD'}).Count -eq 0) {
        Write-Warning "Preflight: all-HDD pool, no SSD/NVMe cache tier. S2D will work but performance will be poor."
    }
    $poolable | Format-Table FriendlyName, MediaType, Size, HealthStatus | Out-String | Write-Verbose
    Write-S2DLog "Preflight - NIC drivers (verify firmware/driver minimums against vendor matrix)"
    Get-NetAdapter -Name @($StorageA, $StorageB, $LiveMigrationAdapter) -ErrorAction SilentlyContinue |
        Select-Object Name, InterfaceDescription, DriverVersion, Status | Format-Table | Out-String | Write-Verbose
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cpu -and (-not $cpu.VMMonitorModeExtensions -or -not $cpu.SecondLevelAddressTranslationExtensions)) {
        Write-Warning "Preflight: CPU virtualization extensions (VT-x/SLATT) look disabled in BIOS. SET works; SR-IOV offload will not."
    }

    Write-S2DLog "NIC renaming - $(hostname)"
    if ($PSCmdlet.ShouldProcess($(hostname), "Rename NICs to StorageA/StorageB/LiveMig/MgmtN/VMN")) {
        Rename-NetAdapter -Name $StorageA -NewName "StorageA" -ErrorAction Stop
        Rename-NetAdapter -Name $StorageB -NewName "StorageB" -ErrorAction Stop
        Rename-NetAdapter -Name $LiveMigrationAdapter -NewName "LiveMig" -ErrorAction Stop
    }
    $RenamedMgmtAdapters = @()
    for ($i = 0; $i -lt $MgmtAdapters.Count; $i++) {
        $mgmtNewName = "Mgmt$($i + 1)"
        if ($PSCmdlet.ShouldProcess($MgmtAdapters[$i], "Rename to $mgmtNewName")) {
            Rename-NetAdapter -Name $MgmtAdapters[$i] -NewName $mgmtNewName -ErrorAction Stop
        }
        $RenamedMgmtAdapters += $mgmtNewName
    }
    $RenamedVMAdapters = @()
    for ($i = 0; $i -lt $VMAdapters.Count; $i++) {
        $newName = "VM$($i + 1)"
        if ($PSCmdlet.ShouldProcess($VMAdapters[$i], "Rename to $newName")) {
            Rename-NetAdapter -Name $VMAdapters[$i] -NewName $newName -ErrorAction Stop
        }
        $RenamedVMAdapters += $newName
    }

    Write-S2DLog "Post-rename verification - $(hostname)"
    if ($WhatIfPreference) {
        Write-S2DLog "WhatIf: rename skipped, verification deferred to live run."
    } else {
        foreach ($canon in @("StorageA", "StorageB", "LiveMig") + $RenamedMgmtAdapters + $RenamedVMAdapters) {
            $found = @(Get-NetAdapter -Name $canon -ErrorAction SilentlyContinue)
            if ($found.Count -ne 1) {
                throw "Post-rename verification failed: '$canon' resolves to $($found.Count) adapter(s). Name collision from a prior run? Clean up before retrying."
            }
        }
    }

    if ($PSCmdlet.ShouldProcess($(hostname), "Configure storage MTU/IP, QoS/RDMA, vSwitch, VMQ/RSC")) {
        Write-S2DLog "Storage MTU + IP - $(hostname)"
        foreach ($st in @("StorageA","StorageB","LiveMig")) {
            try { Set-NetAdapterAdvancedProperty -Name $st -RegistryKeyword "*JumboPacket" -RegistryValue 9014 -ErrorAction Stop } catch { Write-Warning "JumboPacket failed on $st - $_ . Fabric stays at 1500B; align switch/NIC MTU (Broadcom caps at 9000 on some models) before production." }
        }
        foreach ($st in @("StorageA","StorageB","LiveMig")) {
            $mtuProp = Get-NetAdapterAdvancedProperty -Name $st -ErrorAction SilentlyContinue |
                Where-Object { $_.RegistryKeyword -eq "*JumboPacket" } |
                Select-Object -First 1
            if ($mtuProp -and $mtuProp.RegistryValue -ne 9014) {
                Write-Warning "MTU read-back on $st is $($mtuProp.RegistryValue), expected 9014. VM/Mgmt intentionally left at default."
            }
        }

        Set-NetIPInterface -InterfaceAlias "StorageA" -Dhcp Disabled
        Set-NetIPInterface -InterfaceAlias "StorageB" -Dhcp Disabled
        if ($StorageAIP) { Remove-NetIPAddress -InterfaceAlias "StorageA" -IPAddress $StorageAIP -Confirm:$false -ErrorAction SilentlyContinue }
        if ($StorageBIP) { Remove-NetIPAddress -InterfaceAlias "StorageB" -IPAddress $StorageBIP -Confirm:$false -ErrorAction SilentlyContinue }
        if ($StorageAIP) { New-NetIPAddress -InterfaceAlias "StorageA" -IPAddress $StorageAIP -PrefixLength $StoragePrefix | Out-Null }
        if ($StorageBIP) { New-NetIPAddress -InterfaceAlias "StorageB" -IPAddress $StorageBIP -PrefixLength $StoragePrefix | Out-Null }
        if ($LiveMigrationIP) {
            Set-NetIPInterface -InterfaceAlias "LiveMig" -Dhcp Disabled
            Remove-NetIPAddress -InterfaceAlias "LiveMig" -IPAddress $LiveMigrationIP -Confirm:$false -ErrorAction SilentlyContinue
            New-NetIPAddress -InterfaceAlias "LiveMig" -IPAddress $LiveMigrationIP -PrefixLength $LiveMigrationPrefix | Out-Null
            $lmBytes = ([System.Net.IPAddress]$LiveMigrationIP).GetAddressBytes()
            $lmMask = for ($i = 0; $i -lt 4; $i++) { $bits = [math]::Max(0, [math]::Min(8, $LiveMigrationPrefix - $i * 8)); [byte](256 - [math]::Pow(2, (8 - $bits))) }
            $lmNet = for ($i = 0; $i -lt 4; $i++) { $lmBytes[$i] -band $lmMask[$i] }
            $lmSubnet = "$($lmNet -join '.')/$LiveMigrationPrefix"
            $existingMigNets = @(Get-VMMigrationNetwork -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Subnet)
            if ($existingMigNets -notcontains $lmSubnet) {
                Add-VMMigrationNetwork -Subnet $lmSubnet -ErrorAction Stop
            }
        } else {
            Write-Warning "No -LiveMigrationIP: LiveMig NIC stays unbound; migration traffic may use other networks."
        }

        Write-S2DLog "QoS + RDMA - $(hostname)"
        Remove-NetQosPolicy -Name "SMBDirect" -Confirm:$false -ErrorAction SilentlyContinue
        Disable-NetQosFlowControl -Priority 0,1,2,3,4,5,6,7
        if (-not (Get-NetQosPolicy -Name "SMBDirect" -ErrorAction SilentlyContinue)) {
            New-NetQosPolicy "SMBDirect" -NetDirectPortMatchCondition 445 -PriorityValue8021Action 3 | Out-Null
        }
        Enable-NetQosFlowControl -Priority 3 | Out-Null

        foreach ($iface in @("StorageA","StorageB","LiveMig")) {
            Set-NetQosDcbxSetting -InterfaceAlias $iface -Willing $false -Confirm:$false
            $qos = Get-NetAdapterQos -Name $iface -ErrorAction SilentlyContinue
            if ($qos) { $qos | Enable-NetAdapterQos } else { Write-Warning "QoS/DCB unsupported on $iface; RDMA may underperform." }
            Enable-NetAdapterRdma -Name $iface -ErrorAction Stop | Out-Null
        }
        foreach ($iface in @("StorageA","StorageB","LiveMig")) {
            $rdmaState = Get-NetAdapterRdma -Name $iface -ErrorAction SilentlyContinue
            if ($rdmaState -and -not $rdmaState.Enabled) {
                Write-Warning "RDMA not enabled on $iface after configuration (driver/reboot pending?). Verify before production."
            }
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

        Write-S2DLog "EEE off (Mgmt) - $(hostname)"
        foreach ($mgmt in $RenamedMgmtAdapters) {
            $eeeProp = Get-NetAdapterAdvancedProperty -Name $mgmt -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match 'Energy Efficient|EEE|Green Ethernet|Power Sav' } |
                Select-Object -First 1
            if ($eeeProp) {
                Set-NetAdapterAdvancedProperty -Name $mgmt -DisplayName $eeeProp.DisplayName -DisplayValue "Disabled" -ErrorAction SilentlyContinue | Out-Null
            } else {
                Write-Verbose "No EEE property on $mgmt, skipping."
            }
        }

        Write-S2DLog "EEE off (LiveMig) - $(hostname)"
        $eeeLive = Get-NetAdapterAdvancedProperty -Name "LiveMig" -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match 'Energy Efficient|EEE|Green Ethernet|Power Sav' } |
            Select-Object -First 1
        if ($eeeLive) {
            Set-NetAdapterAdvancedProperty -Name "LiveMig" -DisplayName $eeeLive.DisplayName -DisplayValue "Disabled" -ErrorAction SilentlyContinue | Out-Null
        } else {
            Write-Verbose "No EEE property on LiveMig, skipping."
        }

        Write-S2DLog "DNS/NetBIOS off (Storage+LiveMig) - $(hostname)"
        foreach ($nn in @("StorageA","StorageB","LiveMig")) {
            Set-DnsClient -InterfaceAlias $nn -RegisterThisConnectionsAddress $false -ErrorAction SilentlyContinue
            $idx = (Get-NetAdapter -Name $nn -ErrorAction SilentlyContinue).InterfaceIndex
            if ($idx) {
                $cfg = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "InterfaceIndex = $idx" -ErrorAction SilentlyContinue
                if ($cfg) { Invoke-CimMethod -InputObject $cfg -MethodName SetTcpipNetbios -Arguments @{TcpipNetbiosOptions = [uint32]2} | Out-Null }
            }
        }
        # No vSwitch-level RSC toggle: Set-VMSwitch has no such parameter (WS2025
        # reference). Physical RSC is already off on every team member above.

        Set-VMHost -VirtualMachineMigrationPerformanceOption SMB
    }

    Write-S2DLog "== NodePrep - Finished on $(hostname) =="
}
