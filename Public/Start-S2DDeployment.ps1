function Start-S2DDeployment {
<#
.SYNOPSIS
Back-compat wrapper. Prefer Start-S2DNodePrep (per node) and New-S2DCluster (once).
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$ClusterName,
        [string[]]$ClusterNodes,
        [string]$ClusterIP,
        [string[]]$MgmtAdapters,
        [string[]]$VMAdapters,
        [string]$StorageA,
        [string]$StorageB,
        [string]$LiveMigrationAdapter,
        [string]$StorageAIP,
        [string]$StorageBIP,
        [int]$StoragePrefix = 24,
        [ValidateSet("Cloud","FileShare")]
        [string]$WitnessType = "FileShare",
        [string]$AzStorageAccount = "",
        [SecureString]$AzStorageKey,
        [string]$FileShareWitness = "",
        [string]$VolumeName = "CSV_S2D",
        [string]$VolumeSize,
        [ValidateSet("Auto","Fixed")]
        [string]$SizingMode = "Auto",
        [int]$CapacityReservePercent = 20,
        [switch]$UseFullPool,
        [string]$LiveMigrationIP = "",
        [int]$LiveMigrationPrefix = 24,
        [string]$LogPath = "C:\S2D_Deployment.log",
        [ValidateSet("NodePrep","Cluster")]
        [string]$RunPhase
    )
    Write-Warning "Start-S2DDeployment is kept for back-compat. Use Start-S2DNodePrep (per node) and New-S2DCluster (once)."
    # Forward only explicitly bound values: unprovided identity values fall through
    # to the inner Mandatory prompt instead of silently inheriting wrapper defaults.
    if ($RunPhase -eq "NodePrep") {
        $nodeParams = @{}
        foreach ($k in @('MgmtAdapters','VMAdapters','StorageA','StorageB','LiveMigrationAdapter','StorageAIP','StorageBIP','StoragePrefix','LiveMigrationIP','LiveMigrationPrefix','LogPath')) {
            if ($PSBoundParameters.ContainsKey($k)) { $nodeParams[$k] = $PSBoundParameters[$k] }
        }
        if ($PSCmdlet.ShouldProcess("local node", "Start-S2DNodePrep")) {
            Start-S2DNodePrep @nodeParams
        }
    } elseif ($RunPhase -eq "Cluster") {
        $p = @{}
        foreach ($k in @('ClusterName','ClusterNodes','ClusterIP','WitnessType','AzStorageAccount','AzStorageKey','FileShareWitness','VolumeName','VolumeSize','SizingMode','CapacityReservePercent','UseFullPool','LogPath')) {
            if ($PSBoundParameters.ContainsKey($k)) { $p[$k] = $PSBoundParameters[$k] }
        }
        if ($PSCmdlet.ShouldProcess("cluster", "New-S2DCluster")) {
            New-S2DCluster @p
        }
    } else {
        Write-Error "RunPhase must be 'NodePrep' or 'Cluster'"
    }
}
