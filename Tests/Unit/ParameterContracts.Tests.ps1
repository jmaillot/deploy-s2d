BeforeAll {
    Import-Module "$PSScriptRoot/../../Deploy-S2D.psm1" -Force
}

Describe 'Parameter contracts' {
    It 'NodePrep identity params are Mandatory' {
        $params = (Get-Command Start-S2DNodePrep).Parameters
        foreach ($n in @('StorageAIP', 'StorageBIP')) {
            $attr = $params[$n].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] })
            $attr.Mandatory | Should -BeTrue
        }
    }

    It 'Cluster identity params are Mandatory' {
        $params = (Get-Command New-S2DCluster).Parameters
        foreach ($n in @('ClusterName', 'ClusterNodes', 'ClusterIP')) {
            $attr = $params[$n].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] })
            $attr.Mandatory | Should -BeTrue
        }
    }

    It 'AzStorageKey is SecureString' {
        (Get-Command New-S2DCluster).Parameters['AzStorageKey'].ParameterType |
            Should -Be ([System.Security.SecureString])
    }

    It 'shared code has no environment defaults' {
        $src = Get-Content "$PSScriptRoot/../../Public/*.ps1" -Raw
        $src | Should -Not -Match '@\("Ethernet'
        $src | Should -Not -Match '="Ethernet'
        $src | Should -Not -Match '"CLUSTERS2D"'
        $src | Should -Not -Match '@\("HV1"'
        $src | Should -Not -Match 'FS01\\ClusterWitness'
    }

    It 'state-changing functions support ShouldProcess' {
        foreach ($n in @('Start-S2DNodePrep', 'New-S2DCluster', 'Start-S2DDeployment')) {
            (Get-Command $n).Parameters.Keys | Should -Contain 'WhatIf'
        }
    }
}
