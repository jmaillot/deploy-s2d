# Step 1 - run LOCALLY on EACH node (edit StorageAIP/StorageBIP per node).
# Copy Invoke-S2DNodePrep.ps1 + Deploy-S2D.psm1 + S2D.Common.ps1 to the node first.
.\Invoke-S2DNodePrep.ps1 `
  -MgmtAdapters "Mgmt01","Mgmt02" -VMAdapters "Vm01","Vm02" `
  -StorageA "Storage01" -StorageB "Storage02" -LiveMigrationAdapter "Live01" `
  -StorageAIP "192.168.200.1" -StorageBIP "192.168.201.1" -StoragePrefix 24
