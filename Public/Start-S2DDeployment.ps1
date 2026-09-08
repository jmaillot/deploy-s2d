function Start-S2DDeployment {
<#
.SYNOPSIS
Back-compat wrapper. Prefer Start-S2DNodePrep (per node) and New-S2DCluster (once).
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$ClusterName = "CLUSTERS2D",
        [string[]]$ClusterNodes = @("HV1","HV2"),
        [string]$ClusterIP = "192.168.1.240",
        [string[]]$MgmtAdapters = @("Ethernet 1","Ethernet 2"),
        [string[]]$VMAdapters   = @("Ethernet 3","Ethernet 4"),
        [string]$StorageA = "Ethernet 5",
        [string]$StorageB = "Ethernet 6",
        [string]$LiveMigrationAdapter = "Ethernet 7",
        [string]$StorageAIP,
        [string]$StorageBIP,
        [int]$StoragePrefix = 24,
        [ValidateSet("Cloud","FileShare")]
        [string]$WitnessType = "FileShare",
        [string]$AzStorageAccount = "",
        [string]$AzStorageKey     = "",
        [string]$FileShareWitness = "\\FS01\ClusterWitness$",
        [string]$VolumeName = "CSV_S2D",
        [string]$VolumeSize,
        [ValidateSet("Auto","Fixed")]
        [string]$SizingMode = "Auto",
        [int]$CapacityReservePercent = 20,
        [switch]$UseFullPool,
        [ValidateSet("NodePrep","Cluster")]
        [string]$RunPhase
    )
    Write-Warning "Start-S2DDeployment is kept for back-compat. Use Start-S2DNodePrep (per node) and New-S2DCluster (once)."
    if ($RunPhase -eq "NodePrep") {
        if ($PSCmdlet.ShouldProcess("local node", "Start-S2DNodePrep")) {
            Start-S2DNodePrep -MgmtAdapters $MgmtAdapters -VMAdapters $VMAdapters -StorageA $StorageA -StorageB $StorageB -LiveMigrationAdapter $LiveMigrationAdapter -StorageAIP $StorageAIP -StorageBIP $StorageBIP -StoragePrefix $StoragePrefix
        }
    } elseif ($RunPhase -eq "Cluster") {
        $p = @{ ClusterName = $ClusterName; ClusterNodes = $ClusterNodes; ClusterIP = $ClusterIP; WitnessType = $WitnessType; VolumeName = $VolumeName; SizingMode = $SizingMode; CapacityReservePercent = $CapacityReservePercent; UseFullPool = $UseFullPool }
        if ($AzStorageAccount) { $p.AzStorageAccount = $AzStorageAccount }
        if ($AzStorageKey) { $p.AzStorageKey = $AzStorageKey }
        if ($FileShareWitness) { $p.FileShareWitness = $FileShareWitness }
        if ($VolumeSize) { $p.VolumeSize = $VolumeSize }
        if ($PSCmdlet.ShouldProcess($ClusterName, "New-S2DCluster")) {
            New-S2DCluster @p
        }
    } else {
        Write-Error "RunPhase must be 'NodePrep' or 'Cluster'"
    }
}
