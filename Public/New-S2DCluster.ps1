function New-S2DCluster {
<#
.SYNOPSIS
Cluster creation + S2D. Run ONCE from one node.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$ClusterName = "CLUSTERS2D",
        [string[]]$ClusterNodes = @("HV1","HV2"),
        [string]$ClusterIP = "192.168.1.240",
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
        [switch]$UseFullPool
    )

    Write-S2DLog "== Cluster - Creating $ClusterName ($ClusterIP) =="

    Write-S2DLog "Cluster validation (Test-Cluster)"
    if ($PSCmdlet.ShouldProcess($ClusterNodes -join ',', "Test-Cluster")) {
        try {
            Test-Cluster -Node $ClusterNodes -Include "Espaces de stockage direct","Inventaire","Réseau","Configuration du système" -ErrorAction Stop
        } catch {
            Test-Cluster -Node $ClusterNodes -Include "Storage Spaces Direct","Inventory","Network","System Configuration"
        }
    }

    if ($PSCmdlet.ShouldProcess($ClusterName, "New-Cluster + quorum + Enable-ClusterS2D + volume")) {
        if (-not (Get-Cluster -Name $ClusterName -ErrorAction SilentlyContinue)) {
            New-Cluster -Name $ClusterName -Node $ClusterNodes -StaticAddress $ClusterIP | Out-Null
        }

        Write-S2DLog "Quorum - $ClusterName"
        if ($WitnessType -eq "Cloud" -and $AzStorageAccount -and $AzStorageKey) {
            Set-ClusterQuorum -CloudWitness -AccountName $AzStorageAccount -AccessKey $AzStorageKey
        } else {
            Set-ClusterQuorum -FileShareWitness $FileShareWitness
        }

        Write-S2DLog "Enable S2D - $ClusterName"
        Enable-ClusterS2D -Confirm:$false -AutoConfig:$true

        Write-S2DLog "CSV volume (2-way mirror, CSVFS_ReFS) - $ClusterName"
        $pool = Get-StoragePool -FriendlyName "S2D on $ClusterName" -ErrorAction Stop
        $free = $pool.Size - $pool.AllocatedSize

        if ($SizingMode -eq "Auto") {
            $reserveFraction = if ($UseFullPool.IsPresent) { 0.0 } else { [math]::Max([math]::Min($CapacityReservePercent,100),0) / 100.0 }
            $targetBytes      = [math]::Floor($free * (1.0 - $reserveFraction))
            $targetBytesFinal = ($targetBytes / 2)
            if ($targetBytesFinal -le 0) { throw "Insufficient capacity left to create a volume." }
            $targetGiB = [Math]::Round($targetBytesFinal/1GB, 2)
            Write-Host ("Free: {0} GiB | Reserve: {1}% | Volume: {2} GiB" -f ([Math]::Round($free/1GB,2)), ($reserveFraction*100), $targetGiB) -ForegroundColor Yellow
            New-Volume -StoragePoolFriendlyName "S2D on $ClusterName" -FriendlyName $VolumeName -FileSystem CSVFS_ReFS -Size $targetBytesFinal -ResiliencySettingName Mirror | Out-Null
        } else {
            if (-not $VolumeSize) { throw "SizingMode=Fixed : fournir -VolumeSize (ex: 2TB)." }
            New-Volume -StoragePoolFriendlyName "S2D on $ClusterName" -FriendlyName $VolumeName -FileSystem CSVFS_ReFS -Size $VolumeSize -ResiliencySettingName Mirror | Out-Null
        }

        Write-S2DLog "SMB Multichannel constraints (StorageA/B only)"
        foreach ($n in $ClusterNodes) {
            $others = $ClusterNodes | Where-Object { $_ -ne $n }
            foreach ($o in $others) {
                Invoke-Command -ComputerName $n -ScriptBlock {
                    Get-SmbMultichannelConstraint -ErrorAction SilentlyContinue | Where-Object {$_.ServerName -eq $using:o} | Remove-SmbMultichannelConstraint -Confirm:$false -ErrorAction SilentlyContinue
                    New-SmbMultichannelConstraint -ServerName $using:o -InterfaceAlias "StorageA","StorageB" -Confirm:$false | Out-Null
                }
            }
        }

        Write-S2DLog "Rename cluster networks - $ClusterName"
        $netA = (Get-ClusterNetworkInterface | Where-Object {$_.Name -like "*StorageA*"}).Network.Name | Select-Object -Unique
        if ($netA) { (Get-ClusterNetwork -Name "$netA").Name = "StorageA" }
        $netB = (Get-ClusterNetworkInterface | Where-Object {$_.Name -like "*StorageB*"}).Network.Name | Select-Object -Unique
        if ($netB) { (Get-ClusterNetwork -Name "$netB").Name = "StorageB" }
        $netM = (Get-ClusterNetworkInterface | Where-Object {$_.Name -like "*Mgmt*"}).Network.Name | Select-Object -Unique
        if ($netM) { (Get-ClusterNetwork -Name "$netM").Name = "Mgmt" }
    }

    Write-S2DLog "== Cluster - Finished $ClusterName =="
}
