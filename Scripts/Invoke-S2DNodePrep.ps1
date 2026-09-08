<#
.SYNOPSIS
Run LOCALLY on EACH node. Copy this file + Deploy-S2D.psm1 + S2D.Common.ps1 to the node, then execute.
.EXAMPLE
.\Invoke-S2DNodePrep.ps1 -MgmtAdapters "Mgmt01","Mgmt02" -VMAdapters "Vm01","Vm02" -StorageA "Storage01" -StorageB "Storage02" -LiveMigrationAdapter "Live01" -StorageAIP "192.168.200.1" -StorageBIP "192.168.201.1"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$MgmtAdapters = @(),
    [string[]]$VMAdapters = @(),
    [string]$StorageA = "",
    [string]$StorageB = "",
    [string]$LiveMigrationAdapter = "",
    [Parameter(Mandatory = $true)]
    [string]$StorageAIP,
    [Parameter(Mandatory = $true)]
    [string]$StorageBIP,
    [int]$StoragePrefix = 24,
    [string]$LiveMigrationIP = "",
    [int]$LiveMigrationPrefix = 24,
    [string]$LogPath = "C:\S2D_Deployment.log"
)
Import-Module "$PSScriptRoot\..\Deploy-S2D\Deploy-S2D.psm1" -Force
$forward = @{}
foreach ($k in @('MgmtAdapters','VMAdapters','StorageA','StorageB','LiveMigrationAdapter','StorageAIP','StorageBIP','StoragePrefix','LiveMigrationIP','LiveMigrationPrefix','LogPath')) {
    if ($PSBoundParameters.ContainsKey($k)) { $forward[$k] = $PSBoundParameters[$k] }
}
Start-S2DNodePrep @forward
