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
    [int]$StorageJobTimeoutMinutes = 120
)

function Confirm-Step($stepDescription) {
    if ($Force) { return }
    $confirmation = Read-Host "`n[STEP] $stepDescription`nType 'yes' to proceed"
    if ($confirmation -ne 'yes') {
        Write-Host "Step cancelled by user." -ForegroundColor Red
        throw "Cancelled at: $stepDescription"
    }
}

$skipToStep7 = $false

# Check if script is running on the node to be restarted
if ($env:COMPUTERNAME -eq $NodeName -or $env:COMPUTERNAME -eq ($NodeName -split '\.')[0]) {
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

        # Step 2: virtual disk health
        Write-Host "Checking virtual disk health"
        Get-VirtualDisk | Format-Table FriendlyName, HealthStatus, OperationalStatus
        Confirm-Step "Confirm virtual disks are Healthy."

        # Step 3: drain node
        Confirm-Step "Drain node $NodeName (Suspend-ClusterNode -Drain)."
        if ($PSCmdlet.ShouldProcess($NodeName, "Suspend-ClusterNode -Drain")) {
            Suspend-ClusterNode -Name $NodeName -Drain -ErrorAction Stop
        }

        # Step 4: storage maintenance mode
        Confirm-Step "Enter storage maintenance mode on $NodeName."
        if ($PSCmdlet.ShouldProcess($NodeName, "Enable-StorageMaintenanceMode")) {
            Get-StorageFaultDomain -Type StorageScaleUnit -ErrorAction Stop |
                Where-Object {$_.FriendlyName -eq $NodeName} |
                Enable-StorageMaintenanceMode -ErrorAction Stop
        }

        # Step 5: verify maintenance mode
        Write-Host "Verifying disks are in maintenance mode"
        Get-PhysicalDisk | Where-Object {$_.OperationalStatus -eq "In Maintenance Mode"} | Format-Table FriendlyName, OperationalStatus
        Confirm-Step "Confirm disks are in maintenance mode."

        # Step 6: reboot
        Confirm-Step "Reboot $NodeName?"
        if ($PSCmdlet.ShouldProcess($NodeName, "Restart-Computer -Force")) {
            Restart-Computer -ComputerName $NodeName -Force -ErrorAction Stop
        }
    }

    # Step 7: exit maintenance mode (single resume moved to Step 10)
    Confirm-Step "Host restarted? Disable storage maintenance mode for $NodeName."
    if ($PSCmdlet.ShouldProcess($NodeName, "Disable-StorageMaintenanceMode")) {
        Get-StorageFaultDomain -Type StorageScaleUnit -ErrorAction Stop |
            Where-Object {$_.FriendlyName -eq $NodeName} |
            Disable-StorageMaintenanceMode -ErrorAction Stop
    }

    # Step 8: wait for resync (fixed: was looping on completed jobs forever)
    Write-Host "Waiting for storage resync jobs (timeout: $StorageJobTimeoutMinutes min)."
    $deadline = (Get-Date).AddMinutes($StorageJobTimeoutMinutes)
    while ($true) {
        $active = Get-StorageJob -ErrorAction SilentlyContinue |
            Where-Object { $_.JobState -ne 'Completed' -and $_.JobState -ne 'Canceled' -and $_.JobState -ne 'Failed' }
        $failed = Get-StorageJob -ErrorAction SilentlyContinue |
            Where-Object { $_.JobState -eq 'Failed' }
        if ($failed) {
            $failed | Format-Table Name, JobState, PercentComplete
            throw "Storage job(s) failed. Investigate before resuming $NodeName."
        }
        if (-not $active) { break }
        if ((Get-Date) -gt $deadline) {
            $active | Format-Table Name, JobState, PercentComplete
            throw "Timeout waiting for storage jobs after $StorageJobTimeoutMinutes min."
        }
        $active | Format-Table Name, JobState, PercentComplete
        Start-Sleep -Seconds 30
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
    throw
}
