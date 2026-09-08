@{
    # Error + Warning only. Information (e.g. trailing whitespace in the
    # vendored Clear-PhysicalDiskHealthData.ps1) is noise for this repo.
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Deploy/ops scripts are interactive console tools: colored host
        # output via Write-Host/Write-Log is the intended UX, not a smell.
        'PSAvoidUsingWriteHost'
    )
}
