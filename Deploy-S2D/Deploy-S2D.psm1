# Deploy-S2D module loader. Private helpers first, then public functions.
$Private = @(Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue)
$Public  = @(Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue)
foreach ($file in @($Private + $Public)) {
    try {
        . $file.FullName
    } catch {
        throw "Failed to import $($file.FullName): $_"
    }
}
Export-ModuleMember -Function @('Start-S2DNodePrep','New-S2DCluster','Start-S2DDeployment')
