function Get-S2DPoolableDisk {
<#
.SYNOPSIS
Poolable physical disks. Thin wrapper so tests can mock the Storage
module (whose CIM parameter types break Pester proxy generation).
#>
    [CmdletBinding()]
    param()
    Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object {$_.CanPool -eq $true}
}
