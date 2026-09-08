<#
.SYNOPSIS
S2D Maintenance if you need to reboot a node from an S2D Cluster.

.DESCRIPTION
Puts a node into storage maintenance mode before rebooting.
Run from ANOTHER node than the reboot target. If the node was already
rebooted, the script offers to resume at Step 7 (exit maintenance mode).

.PARAMETER NodeName
Name of the node to reboot.

.PARAMETER Force
Skip interactive confirmations (for automation). Still honors -WhatIf.

.PARAMETER StorageJobTimeoutMinutes
Max time to wait for storage resync jobs. Default 120.

.EXAMPLE
.\Reboot-S2D.ps1 -NodeName HV01

.EXAMPLE
.\Reboot-S2D.ps1 -NodeName HV01 -WhatIf

.NOTES
===========================================================================
Tool Name    : Reboot-S2D.ps1
Author       : Jérémy Maillot
Version      : 1.1
Requires     : PowerShell Version 5.1 or above
Role         : Storage Spaces Direct
===========================================================================
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $true)]
    [string]$NodeName,
    [switch]$Force,
    [ValidateRange(1, 1440)]
    [int]$StorageJobTimeoutMinutes = 120
)

function Confirm-Step($stepDescription) {
    if ($Force) { return }
    if (-not [Environment]::UserInteractive) {
        throw "Non-interactive session without -Force at: $stepDescription. Re-run with -Force (checks still apply) or interactively."
    }
    $confirmation = Read-Host "`n[STEP] $stepDescription`nType 'yes' to proceed"
    if ($confirmation -ne 'yes') {
        Write-Host "Step cancelled by user." -ForegroundColor Red
        throw "Cancelled at: $stepDescription"
    }
}

$skipToStep7 = $false

# Check if script is running on the node to be restarted (short names compared both ways)
$localShort = ($env:COMPUTERNAME -split '\.')[0]
$targetShort = ($NodeName -split '\.')[0]
if ($env:COMPUTERNAME -eq $NodeName -or $localShort -eq $targetShort) {
    Write-Host "This script is running on the node that will be rebooted ($NodeName)." -ForegroundColor Yellow
    Write-Host "Run it from another cluster node. If the node was already rebooted, resume at Step 7." -ForegroundColor Yellow
    if ($Force) {
        $skipToStep7 = $true
    } else {
        $confirmation = Read-Host "Skip to Step 7? Type 'yes' to proceed, anything else to abort"
        if ($confirmation -eq 'yes') {
            $skipToStep7 = $true
        } else {
            throw "Aborted: script must run from a different node."
        }
    }
}

try {
    if (-not $skipToStep7) {
        # Step 1: must run elevated (real check, was prompt-only)
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) { throw "Run PowerShell as Administrator." }
        Write-Host "Running elevated." -ForegroundColor Green

        # Step 2: virtual disk health (programmatic, not just eyeballed)
        Write-Host "Checking virtual disk health"
        $preUnhealthy = @(Get-VirtualDisk | Where-Object { $_.HealthStatus -ne 'Healthy' })
        Get-VirtualDisk | Format-Table FriendlyName, HealthStatus, OperationalStatus
        if ($preUnhealthy.Count -gt 0) {
            throw "Virtual disk(s) already unhealthy before maintenance: $($preUnhealthy.FriendlyName -join ', '). Fix first, do not drain $NodeName."
        }
        Confirm-Step "Confirm virtual disks are Healthy."

        # Step 3: drain node
        Confirm-Step "Drain node $NodeName (Suspend-ClusterNode -Drain)."
        if ($PSCmdlet.ShouldProcess($NodeName, "Suspend-ClusterNode -Drain")) {
            Suspend-ClusterNode -Name $NodeName -Drain -ErrorAction Stop
        }

        # Step 4: storage maintenance mode
        Confirm-Step "Enter storage maintenance mode on $NodeName."
        if ($PSCmdlet.ShouldProcess($NodeName, "Enable-StorageMaintenanceMode")) {
            $sdu = @(Get-StorageFaultDomain -Type StorageScaleUnit -ErrorAction Stop |
                Where-Object {$_.FriendlyName -eq $NodeName})
            if ($sdu.Count -ne 1) {
                throw "Expected exactly 1 storage scale unit named '$NodeName', found $($sdu.Count). Check -NodeName spelling."
            }
            $sdu | Enable-StorageMaintenanceMode -ErrorAction Stop
        }

        # Step 5: verify maintenance mode
        Write-Host "Verifying disks are in maintenance mode"
        Get-PhysicalDisk | Where-Object {$_.OperationalStatus -eq "In Maintenance Mode"} | Format-Table FriendlyName, OperationalStatus
        Confirm-Step "Confirm disks are in maintenance mode."

        # Step 6: reboot, then wait for down + back (skipped under WhatIf)
        Confirm-Step "Reboot $NodeName?"
        if ($PSCmdlet.ShouldProcess($NodeName, "Restart-Computer -Force")) {
            Restart-Computer -ComputerName $NodeName -Force -ErrorAction Stop
        }
        if (-not $WhatIfPreference) {
            Write-Host "Waiting for $NodeName to go down (max 10 min)..."
            $downDeadline = (Get-Date).AddMinutes(10)
            do {
                Start-Sleep -Seconds 5
                $up = Test-Connection -ComputerName $NodeName -Count 1 -Quiet -ErrorAction SilentlyContinue
            } while ($up -and (Get-Date) -lt $downDeadline)
            Write-Host "Waiting for $NodeName to answer WinRM again (max 20 min)..."
            $upDeadline = (Get-Date).AddMinutes(20)
            do {
                Start-Sleep -Seconds 15
                $back = Test-WSMan -ComputerName $NodeName -ErrorAction SilentlyContinue
            } while (-not $back -and (Get-Date) -lt $upDeadline)
            if (-not $back) { throw "$NodeName did not come back within 20 min. Investigate before continuing to Step 7." }
        }
    }

    # Step 7: exit maintenance mode (single resume moved to Step 10)
    Confirm-Step "Host restarted? Disable storage maintenance mode for $NodeName."
    if ($PSCmdlet.ShouldProcess($NodeName, "Disable-StorageMaintenanceMode")) {
        $sdu7 = @(Get-StorageFaultDomain -Type StorageScaleUnit -ErrorAction Stop |
            Where-Object {$_.FriendlyName -eq $NodeName})
        if ($sdu7.Count -ne 1) {
            throw "Expected exactly 1 storage scale unit named '$NodeName', found $($sdu7.Count). Nothing disabled."
        }
        $sdu7 | Disable-StorageMaintenanceMode -ErrorAction Stop
    }

    # Step 8: wait for resync (fixed: was looping on completed jobs forever)
    Write-Host "Waiting for storage resync jobs (timeout: $StorageJobTimeoutMinutes min)."
    if ($WhatIfPreference) {
        Get-StorageJob -ErrorAction SilentlyContinue | Format-Table Name, JobState, PercentComplete
        Write-Host "WhatIf: resync wait skipped."
    } else {
    $deadline = (Get-Date).AddMinutes($StorageJobTimeoutMinutes)
    while ($true) {
        $jobs = @(Get-StorageJob -ErrorAction SilentlyContinue)
        $active = @($jobs | Where-Object { $_.JobState -ne 'Completed' -and $_.JobState -ne 'Canceled' -and $_.JobState -ne 'Failed' })
        $failed = @($jobs | Where-Object { $_.JobState -eq 'Failed' })
        if ($failed.Count -gt 0) {
            $failed | Format-Table Name, JobState, PercentComplete
            throw "Storage job(s) failed. Investigate before resuming $NodeName."
        }
        if ($active.Count -eq 0) { break }
        if ((Get-Date) -gt $deadline) {
            $active | Format-Table Name, JobState, PercentComplete
            throw "Timeout waiting for storage jobs after $StorageJobTimeoutMinutes min."
        }
        $active | Format-Table Name, JobState, PercentComplete
        Start-Sleep -Seconds 30
    }
    }
    Write-Host "No active storage jobs." -ForegroundColor Green

    # Step 9: health check again
    Write-Host "Checking virtual disk health"
    $unhealthy = Get-VirtualDisk | Where-Object { $_.HealthStatus -ne 'Healthy' }
    Get-VirtualDisk | Format-Table FriendlyName, HealthStatus, OperationalStatus
    if ($unhealthy) { throw "Virtual disk(s) unhealthy. Do not resume $NodeName yet." }

    # Step 10: single resume with immediate failback
    Confirm-Step "Resume node $NodeName (Resume-ClusterNode -Failback Immediate)."
    if ($PSCmdlet.ShouldProcess($NodeName, "Resume-ClusterNode -Failback Immediate")) {
        Resume-ClusterNode -Name $NodeName -Failback Immediate -ErrorAction Stop
    }
    Write-Host "`nNode $NodeName is back in production." -ForegroundColor Green

} catch {
    Write-Host "`nAn error occurred: $_" -ForegroundColor Red
    Write-Host "Recovery hint: if $NodeName is drained or in storage maintenance, run:" -ForegroundColor Yellow
    Write-Host "  Resume-ClusterNode -Name $NodeName -Failback Immediate" -ForegroundColor Yellow
    Write-Host "  Get-StorageFaultDomain -Type StorageScaleUnit | Where-Object {`$_.FriendlyName -eq '$NodeName'} | Disable-StorageMaintenanceMode" -ForegroundColor Yellow
    throw
}
