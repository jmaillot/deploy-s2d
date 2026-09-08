<#
.SYNOPSIS
Run LOCALLY on EACH node. Copy this file + Deploy-S2D.psm1 + S2D.Common.ps1 to the node, then execute.
.EXAMPLE
.\Invoke-S2DNodePrep.ps1 -MgmtAdapters "Mgmt01","Mgmt02" -VMAdapters "Vm01","Vm02" -StorageA "Storage01" -StorageB "Storage02" -LiveMigrationAdapter "Live01" -StorageAIP "192.168.200.1" -StorageBIP "192.168.201.1"
#>
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
Import-Module "$PSScriptRoot\Deploy-S2D.psm1" -Force
Start-S2DNodePrep -MgmtAdapters $MgmtAdapters -VMAdapters $VMAdapters -StorageA $StorageA -StorageB $StorageB -LiveMigrationAdapter $LiveMigrationAdapter -StorageAIP $StorageAIP -StorageBIP $StorageBIP -StoragePrefix $StoragePrefix
