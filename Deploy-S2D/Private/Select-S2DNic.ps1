function Select-S2DNic {
<#
.SYNOPSIS
Console NIC picker. Lists physical adapters with help text, returns chosen names.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [string]$Help,
        [string[]]$Exclude = @(),
        [switch]$Multi
    )

    if (-not [Environment]::UserInteractive) {
        throw "Non-interactive session (including WinRM remote shells, which always report non-interactive): supply all NIC names explicitly instead of relying on the picker ($Title)."
    }

    $nics = @(Get-NetAdapter -Physical -ErrorAction Stop |
        Where-Object { $_.Name -notin $Exclude } |
        Sort-Object Name)
    if ($nics.Count -eq 0) {
        Write-Warning "No physical adapters matched - retrying with all non-virtual adapters."
        $nics = @(Get-NetAdapter -ErrorAction Stop |
            Where-Object { $_.Name -notin $Exclude -and $_.Name -notlike 'vEthernet*' -and $_.Name -notlike '*Bluetooth*' } |
            Sort-Object Name)
    }
    if ($nics.Count -eq 0) { throw "No selectable adapters left for $Title (all picked already?)." }
    Write-Host "Found $($nics.Count) adapter(s)."

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host $Help
    Write-Host "==================================================" -ForegroundColor Cyan
    for ($i = 0; $i -lt $nics.Count; $i++) {
        # Write-Host, not bare output: rows must display, not join the return value.
        Write-Host ("{0,2}: {1,-24} {2,-16} {3}" -f $i, $nics[$i].Name, $nics[$i].Status, $nics[$i].LinkSpeed)
    }
    if ($Multi) {
        Write-Host "Choose 1 or more: type the numbers separated by commas (one number alone is fine, e.g. 0). Blank = none. Q = abort." -ForegroundColor Yellow
    } else {
        Write-Host "One number. Q = abort." -ForegroundColor Yellow
    }

    while ($true) {
        $answer = Read-Host "Your choice"
        if ($answer -eq 'q' -or $answer -eq 'Q') { throw "Aborted at $Title." }
        if ([string]::IsNullOrWhiteSpace($answer)) {
            if ($Multi) { return @() }
            Write-Warning "Enter a number (this role needs exactly one adapter) or Q to abort."
            continue
        }
        $picked = @()
        $valid = $true
        foreach ($part in ($answer -split ',')) {
            $n = 0
            if (-not [int]::TryParse($part.Trim(), [ref]$n) -or $n -lt 0 -or $n -ge $nics.Count) { $valid = $false; break }
            $picked += $nics[$n].Name
        }
        if (-not $valid -or $picked.Count -eq 0 -or (-not $Multi -and $picked.Count -ne 1)) {
            Write-Warning "Invalid choice. Valid numbers: 0 to $($nics.Count - 1)."
            continue
        }
        $picked = @($picked | Select-Object -Unique)
        if (-not $Multi) { return $picked[0] }
        return $picked
    }
}
