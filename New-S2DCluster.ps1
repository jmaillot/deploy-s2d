<#
.SYNOPSIS
Run ONCE from one node after NodePrep completed on all nodes.
.EXAMPLE
.\New-S2DCluster.ps1 -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22.intra-pdl.fr\ClusterPDL$" -VolumeName "CSV_S2D" -SizingMode "Auto"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ClusterName,
    [Parameter(Mandatory = $true)]
    [string[]]$ClusterNodes,
    [Parameter(Mandatory = $true)]
    [string]$ClusterIP,
    [ValidateSet("Cloud","FileShare")]
    [string]$WitnessType = "FileShare",
    [string]$AzStorageAccount = "",
    [string]$AzStorageKey = "",
    [string]$FileShareWitness = "",
    [string]$VolumeName = "CSV_S2D",
    [string]$VolumeSize,
    [ValidateSet("Auto","Fixed")]
    [string]$SizingMode = "Auto",
    [int]$CapacityReservePercent = 20,
    [switch]$UseFullPool,
    [string]$LogPath = "C:\S2D_Deployment.log"
)
Import-Module "$PSScriptRoot\Deploy-S2D.psm1" -Force
$params = @{
    ClusterName = $ClusterName; ClusterNodes = $ClusterNodes; ClusterIP = $ClusterIP
    WitnessType = $WitnessType; VolumeName = $VolumeName; SizingMode = $SizingMode
    CapacityReservePercent = $CapacityReservePercent; UseFullPool = $UseFullPool
}
if ($AzStorageAccount) { $params.AzStorageAccount = $AzStorageAccount }
if ($AzStorageKey) { $params.AzStorageKey = $AzStorageKey }
if ($FileShareWitness) { $params.FileShareWitness = $FileShareWitness }
if ($VolumeSize) { $params.VolumeSize = $VolumeSize }
if ($LogPath) { $params.LogPath = $LogPath }
New-S2DCluster @params
