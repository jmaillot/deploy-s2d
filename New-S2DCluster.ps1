<#
.SYNOPSIS
Run ONCE from one node after NodePrep completed on all nodes.
.EXAMPLE
.\New-S2DCluster.ps1 -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22.intra-pdl.fr\ClusterPDL$" -VolumeName "CSV_S2D" -SizingMode "Auto"
#>
param(
    [string]$ClusterName = "CLUSTERS2D",
    [string[]]$ClusterNodes = @("HV1","HV2"),
    [string]$ClusterIP = "192.168.1.240",
    [ValidateSet("Cloud","FileShare")]
    [string]$WitnessType = "FileShare",
    [string]$AzStorageAccount = "",
    [string]$AzStorageKey = "",
    [string]$FileShareWitness = "\\FS01\ClusterWitness$",
    [string]$VolumeName = "CSV_S2D",
    [string]$VolumeSize,
    [ValidateSet("Auto","Fixed")]
    [string]$SizingMode = "Auto",
    [int]$CapacityReservePercent = 20,
    [switch]$UseFullPool
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
New-S2DCluster @params
