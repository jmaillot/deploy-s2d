function Write-S2DLog {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $logPath = if ($script:S2DLogPath) { $script:S2DLogPath } else { "C:\S2D_Deployment.log" }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp][$Level] $Message"
    Write-Host $entry
    Add-Content -Path $logPath -Value $entry
}
