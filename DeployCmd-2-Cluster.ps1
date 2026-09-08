# Step 2 - run ONCE from one node after NodePrep succeeded everywhere.
$cluster = @{
    ClusterName       = "ClusterPDL"
    ClusterNodes      = "HV1", "HV2"
    ClusterIP         = "192.168.1.240"
    WitnessType       = "FileShare"
    FileShareWitness  = "\\NTSVR22.intra-pdl.fr\ClusterPDL$"
    VolumeName        = "CSV_S2D"
    SizingMode        = "Auto"
}
.\New-S2DCluster.ps1 @cluster
