@{
    RootModule = 'Deploy-S2D.psm1'
    ModuleVersion = '1.5.0'
    GUID = '1b679426-27c1-4595-9aad-bf596b444a8c'
    Author = 'Jérémy Maillot'
    Description = "S2D deployment: Start-S2DNodePrep (per node) + New-S2DCluster (once). Start-S2DDeployment kept for back-compat."
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Start-S2DNodePrep','New-S2DCluster','Start-S2DDeployment')
    PrivateData = @{
        PSData = @{
            Tags = @('S2D','StorageSpacesDirect','FailoverCluster','Hyper-V')
        }
    }
}
