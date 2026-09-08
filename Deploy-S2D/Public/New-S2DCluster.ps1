function New-S2DCluster {
<#
.SYNOPSIS
Cluster creation + S2D. Run ONCE from one node.
.DESCRIPTION
Validates (Test-Cluster, FR-first/EN-fallback, strict), creates the cluster, sets quorum,
enables S2D, creates the mirrored CSV (ReFS), constrains SMB Multichannel to
StorageA/B, renames cluster networks. Passes the Test-Cluster report through.
Re-runnable: existing cluster (with matching nodes), S2D pool, and volume are
detected and skipped instead of recreated.
.PARAMETER ClusterName
Cluster name.
.PARAMETER ClusterNodes
Exactly 2 cluster node names.
.PARAMETER ClusterIP
Cluster static IP. Must be free (pre-checked).
.PARAMETER WitnessType
FileShare (default) or Cloud quorum.
.PARAMETER AzStorageAccount
Cloud witness account name (Cloud only).
.PARAMETER AzStorageKey
Cloud witness key as SecureString, e.g. Read-Host -AsSecureString (Cloud only).
.PARAMETER FileShareWitness
Witness UNC path, e.g. \\FS01\Witness$ (FileShare only). Reachability pre-checked.
.PARAMETER VolumeName
CSV friendly name. Default CSV_S2D.
.PARAMETER VolumeSize
Fixed size with optional suffix, e.g. 2TB, 512GB, bytes. Required when SizingMode is Fixed.
.PARAMETER SizingMode
Auto (default, keeps CapacityReservePercent) or Fixed.
.PARAMETER CapacityReservePercent
Pool percent held back in Auto mode. Default 20, range 0-100.
.PARAMETER UseFullPool
Ignore the reserve and use the whole pool.
.PARAMETER LogPath
Log file path. Default C:\S2D_Deployment.log.
.EXAMPLE
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV_S2D" -SizingMode "Auto"
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName,
        [Parameter(Mandatory = $true)]
        [ValidateCount(2, 2)]
        [string[]]$ClusterNodes,
        [Parameter(Mandatory = $true)]
        [string]$ClusterIP,
        [ValidateSet("Cloud","FileShare")]
        [string]$WitnessType = "FileShare",
        [string]$AzStorageAccount = "",
        [SecureString]$AzStorageKey,
        [string]$FileShareWitness = "",
        [string]$VolumeName = "CSV_S2D",
        [string]$VolumeSize,
        [ValidateSet("Auto","Fixed")]
        [string]$SizingMode = "Auto",
        [ValidateRange(0, 100)]
        [int]$CapacityReservePercent = 20,
        [switch]$UseFullPool,
        [string]$LogPath = "C:\S2D_Deployment.log"
    )

    if ($WitnessType -eq "FileShare" -and [string]::IsNullOrWhiteSpace($FileShareWitness)) {
        throw "WitnessType=FileShare requires -FileShareWitness (UNC path, e.g. \\FS01\Witness$)."
    }
    if ($WitnessType -eq "Cloud" -and ([string]::IsNullOrWhiteSpace($AzStorageAccount) -or $null -eq $AzStorageKey)) {
        throw "WitnessType=Cloud requires -AzStorageAccount and -AzStorageKey (pass a SecureString, e.g. Read-Host -AsSecureString)."
    }
    $VolumeSizeBytes = $null
    if ($SizingMode -eq "Fixed") {
        if ([string]::IsNullOrWhiteSpace($VolumeSize)) { throw "SizingMode=Fixed : fournir -VolumeSize (ex: 2TB)." }
        $m = [regex]::Match($VolumeSize.Trim(), '^(?<n>\d+(\.\d+)?)\s*(?<u>B|KB|MB|GB|TB)?$')
        if (-not $m.Success) { throw "Unparseable -VolumeSize: '$VolumeSize'. Use plain bytes or a KB/MB/GB/TB suffix (ex: 2TB)." }
        $unit = $m.Groups['u'].Value.ToUpper()
        $mult = if ([string]::IsNullOrEmpty($unit) -or $unit -eq 'B') { 1 } else { @{ KB = 1KB; MB = 1MB; GB = 1GB; TB = 1TB }[$unit] }
        $VolumeSizeBytes = [uint64]([double]$m.Groups['n'].Value * $mult)
        if ($VolumeSizeBytes -le 0) { throw "Unparseable -VolumeSize: '$VolumeSize' resolves to 0 bytes." }
    }

    # Pre-mutation checks: everything verifiable without changing state.
    if ($WitnessType -eq "FileShare" -and -not (Test-Path $FileShareWitness)) {
        throw "FileShare witness unreachable: $FileShareWitness."
    }
    if (Test-Connection -ComputerName $ClusterIP -Count 1 -Quiet -ErrorAction SilentlyContinue) {
        throw "ClusterIP $ClusterIP already answers. Pick a free address."
    }
    foreach ($cn in $ClusterNodes) {
        if (-not (Test-WSMan -ComputerName $cn -ErrorAction SilentlyContinue)) {
            throw "Node unreachable via WinRM: $cn."
        }
    }

    $script:S2DLogPath = $LogPath
    Write-S2DLog "== Cluster - Creating $ClusterName ($ClusterIP) =="

    Write-S2DLog "Cluster validation (Test-Cluster)"
    if ($PSCmdlet.ShouldProcess($ClusterNodes -join ',', "Test-Cluster")) {
        $frOk = $true
        $frErr = ""
        try {
            Test-Cluster -Node $ClusterNodes -Include "Espaces de stockage direct","Inventaire","Réseau","Configuration du système" -ErrorAction Stop
        } catch {
            $frOk = $false
            $frErr = $_.Exception.Message
            Write-Verbose "FR validation unavailable/failed, retrying with EN-US test names."
        }
        if (-not $frOk) {
            try {
                Test-Cluster -Node $ClusterNodes -Include "Storage Spaces Direct","Inventory","Network","System Configuration" -ErrorAction Stop
            } catch {
                throw "Cluster validation failed, aborting before any mutation. FR error: $frErr | EN error: $($_.Exception.Message)"
            }
        }
    }

    if ($PSCmdlet.ShouldProcess($ClusterName, "New-Cluster")) {
        $existing = Get-Cluster -Name $ClusterName -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-Cluster -Name $ClusterName -Node $ClusterNodes -StaticAddress $ClusterIP | Out-Null
        } else {
            $actualNodes = @(Get-ClusterNode -Cluster $ClusterName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
            $missing = @($ClusterNodes | Where-Object { $_ -notin $actualNodes })
            if ($missing.Count -gt 0) {
                throw "Cluster $ClusterName exists but misses nodes: $($missing -join ', '). Refusing to adopt a foreign cluster."
            }
            Write-S2DLog "Cluster $ClusterName exists with matching nodes, reusing."
        }
    }

    if ($PSCmdlet.ShouldProcess($ClusterName, "Set-ClusterQuorum")) {
        Write-S2DLog "Quorum - $ClusterName"
        if ($WitnessType -eq "Cloud") {
            # Decrypt only for the call; zero the unmanaged copy immediately.
            # Never logged, never stored.
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AzStorageKey)
            try {
                $plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
                Set-ClusterQuorum -CloudWitness -AccountName $AzStorageAccount -AccessKey $plainKey
            } finally {
                $plainKey = $null
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        } else {
            Set-ClusterQuorum -FileShareWitness $FileShareWitness
        }
    }

    if ($PSCmdlet.ShouldProcess($ClusterName, "Enable-ClusterS2D")) {
        Write-S2DLog "Enable S2D - $ClusterName"
        $s2dPool = Get-StoragePool -FriendlyName "S2D on $ClusterName" -ErrorAction SilentlyContinue
        if (-not $s2dPool) {
            Enable-ClusterS2D -Confirm:$false -AutoConfig:$true
        } else {
            Write-S2DLog "S2D pool exists, skipping Enable-ClusterS2D."
        }
    }

    if ($PSCmdlet.ShouldProcess($VolumeName, "New-Volume (2-way mirror)")) {
        Write-S2DLog "CSV volume (2-way mirror, CSVFS_ReFS) - $ClusterName"
        if (Get-VirtualDisk -FriendlyName $VolumeName -ErrorAction SilentlyContinue) {
            Write-S2DLog "Volume $VolumeName exists, skipping creation."
        } else {
            $pool = Get-StoragePool -FriendlyName "S2D on $ClusterName" -ErrorAction Stop
            $free = $pool.Size - $pool.AllocatedSize
            if ($SizingMode -eq "Auto") {
                $reserveFraction = if ($UseFullPool.IsPresent) { 0.0 } else { $CapacityReservePercent / 100.0 }
                $targetBytes      = [math]::Floor($free * (1.0 - $reserveFraction))
                $targetBytesFinal = [uint64]($targetBytes / 2)
                if ($targetBytesFinal -le 0) { throw "Insufficient capacity left to create a volume." }
                $targetGiB = [Math]::Round($targetBytesFinal/1GB, 2)
                Write-Host ("Free: {0} GiB | Reserve: {1}% | Volume: {2} GiB" -f ([Math]::Round($free/1GB,2)), ($reserveFraction*100), $targetGiB) -ForegroundColor Yellow
                New-Volume -StoragePoolFriendlyName "S2D on $ClusterName" -FriendlyName $VolumeName -FileSystem CSVFS_ReFS -Size $targetBytesFinal -ResiliencySettingName Mirror | Out-Null
            } else {
                New-Volume -StoragePoolFriendlyName "S2D on $ClusterName" -FriendlyName $VolumeName -FileSystem CSVFS_ReFS -Size $VolumeSizeBytes -ResiliencySettingName Mirror | Out-Null
            }
        }
    }

    if ($PSCmdlet.ShouldProcess(($ClusterNodes -join ','), "SMB Multichannel constraints (StorageA/B only)")) {
        Write-S2DLog "SMB Multichannel constraints (StorageA/B only)"
        foreach ($n in $ClusterNodes) {
            $others = $ClusterNodes | Where-Object { $_ -ne $n }
            foreach ($o in $others) {
                Invoke-Command -ComputerName $n -ScriptBlock {
                    Get-SmbMultichannelConstraint -ErrorAction SilentlyContinue | Where-Object {$_.ServerName -eq $using:o} | Remove-SmbMultichannelConstraint -Confirm:$false -ErrorAction SilentlyContinue
                    New-SmbMultichannelConstraint -ServerName $using:o -InterfaceAlias "StorageA","StorageB" -Confirm:$false | Out-Null
                } -ArgumentList $o
            }
        }
    }

    if ($PSCmdlet.ShouldProcess($ClusterName, "Rename cluster networks")) {
        Write-S2DLog "Rename cluster networks - $ClusterName"
        $netA = @(Get-ClusterNetworkInterface | Where-Object {$_.Name -like "*StorageA*"} | ForEach-Object { $_.Network.Name } | Select-Object -Unique)
        if ($netA.Count -gt 1) { throw "Multiple cluster networks match *StorageA*: $($netA -join ', ')." }
        elseif ($netA.Count -eq 1) { (Get-ClusterNetwork -Name $netA[0]).Name = "StorageA" }
        $netB = @(Get-ClusterNetworkInterface | Where-Object {$_.Name -like "*StorageB*"} | ForEach-Object { $_.Network.Name } | Select-Object -Unique)
        if ($netB.Count -gt 1) { throw "Multiple cluster networks match *StorageB*: $($netB -join ', ')." }
        elseif ($netB.Count -eq 1) { (Get-ClusterNetwork -Name $netB[0]).Name = "StorageB" }
        $netM = @(Get-ClusterNetworkInterface | Where-Object {$_.Name -like "*Mgmt*"} | ForEach-Object { $_.Network.Name } | Select-Object -Unique)
        if ($netM.Count -gt 1) { throw "Multiple cluster networks match *Mgmt*: $($netM -join ', ')." }
        elseif ($netM.Count -eq 1) { (Get-ClusterNetwork -Name $netM[0]).Name = "Mgmt" }
    }

    Write-S2DLog "== Cluster - Finished $ClusterName =="
}
