# Start-S2DNodePrep with every external cmdlet mocked (static returns only).
# Two scopes: existing vSwitch (pipe path) and missing vSwitch (creation path).
BeforeAll {
    Import-Module "$PSScriptRoot/../../Deploy-S2D.psm1" -Force

    Mock -ModuleName Deploy-S2D Add-Content -MockWith {}
    Mock -ModuleName Deploy-S2D Get-NetAdapter -MockWith {
        if ($PSBoundParameters.ContainsKey('Name')) {
            [pscustomobject]@{
                Name = 'mock'; Status = 'Up'; LinkSpeed = '25 Gbps'
                InterfaceDescription = 'Mock Adapter'; DriverVersion = '1.0'
                MacAddress = '00-00-00-00-00-00'
            }
        } else {
            1..5 | ForEach-Object {
                [pscustomobject]@{
                    Name = "Mock$_"; Status = 'Up'; LinkSpeed = '25 Gbps'
                    InterfaceDescription = 'Mock Adapter'; DriverVersion = '1.0'
                    MacAddress = '00-00-00-00-00-00'
                }
            }
        }
    }
    Mock -ModuleName Deploy-S2D Get-CimInstance -MockWith {
        if ($ClassName -eq 'Win32_NetworkAdapter') {
            [pscustomobject]@{ Speed = 25000000000 }
        } elseif ($ClassName -eq 'Win32_Processor') {
            [pscustomobject]@{ VMMonitorModeExtensions = $true; SecondLevelAddressTranslationExtensions = $true }
        }
    }
    Mock -ModuleName Deploy-S2D Get-SmbClientNetworkInterface -MockWith {
        [pscustomobject]@{ InterfaceAlias = 'mock'; RdmaCapable = $true }
    }
    Mock -ModuleName Deploy-S2D Get-S2DPoolableDisk -MockWith {
        [pscustomobject]@{ FriendlyName = 'MockDisk'; MediaType = 'SSD'; Size = 1TB; HealthStatus = 'Healthy'; CanPool = $true }
    }
    Mock -ModuleName Deploy-S2D Rename-NetAdapter -MockWith {}
    Mock -ModuleName Deploy-S2D Set-NetAdapterAdvancedProperty -MockWith {}
    Mock -ModuleName Deploy-S2D Set-NetIPInterface -MockWith {}
    Mock -ModuleName Deploy-S2D Remove-NetIPAddress -MockWith {}
    Mock -ModuleName Deploy-S2D New-NetIPAddress -MockWith {}
    Mock -ModuleName Deploy-S2D Remove-NetQosPolicy -MockWith {}
    Mock -ModuleName Deploy-S2D Get-NetQosPolicy -MockWith {}
    Mock -ModuleName Deploy-S2D New-NetQosPolicy -MockWith {}
    Mock -ModuleName Deploy-S2D Enable-NetQosFlowControl -MockWith {}
    Mock -ModuleName Deploy-S2D Disable-NetQosFlowControl -MockWith {}
    Mock -ModuleName Deploy-S2D Set-NetQosDcbxSetting -MockWith {}
    Mock -ModuleName Deploy-S2D Get-NetAdapterQos -MockWith { [pscustomobject]@{ Name = 'mock' } }
    Mock -ModuleName Deploy-S2D Enable-NetAdapterQos -MockWith {}
    Mock -ModuleName Deploy-S2D Get-NetAdapterRdma -MockWith { [pscustomobject]@{ Enabled = $true } }
    Mock -ModuleName Deploy-S2D Enable-NetAdapterRdma -MockWith {}
    Mock -ModuleName Deploy-S2D Get-NetAdapterVmq -MockWith {}
    Mock -ModuleName Deploy-S2D Disable-NetAdapterVmq -MockWith {}
    Mock -ModuleName Deploy-S2D Get-NetAdapterRsc -MockWith {}
    Mock -ModuleName Deploy-S2D Disable-NetAdapterRsc -MockWith {}
    Mock -ModuleName Deploy-S2D Get-VMSwitch -MockWith { [pscustomobject]@{ Name = 'vSwitch-VM' } }
    Mock -ModuleName Deploy-S2D New-VMSwitch -MockWith {}
    Mock -ModuleName Deploy-S2D Set-VMSwitch -MockWith {}
    Mock -ModuleName Deploy-S2D Set-VMHost -MockWith {}
}

Describe 'Start-S2DNodePrep with existing vSwitch (mocked)' {
    It 'completes and reuses the switch' {
        { Start-S2DNodePrep -MgmtAdapters 'M1', 'M2' -VMAdapters 'V1', 'V2' -StorageA 'S1' `
                -StorageB 'S2' -LiveMigrationAdapter 'L1' -StorageAIP '10.0.0.1' -StorageBIP '10.0.1.1' `
                -LiveMigrationIP '10.0.2.1' -Confirm:$false } | Should -Not -Throw
        Should -Invoke -ModuleName Deploy-S2D -CommandName Rename-NetAdapter -Times 7 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-NetIPAddress -Times 3 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName Set-VMHost -Times 2 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-VMSwitch -Times 0 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName Set-VMSwitch -Times 1 -Exactly
    }
}

Describe 'Start-S2DNodePrep with missing vSwitch (mocked)' {
    BeforeAll {
        Mock -ModuleName Deploy-S2D Get-VMSwitch -MockWith {}
    }

    It 'creates a SET team' {
        { Start-S2DNodePrep -MgmtAdapters 'M1', 'M2' -VMAdapters 'V1', 'V2' -StorageA 'S1' `
                -StorageB 'S2' -LiveMigrationAdapter 'L1' -StorageAIP '10.0.0.1' -StorageBIP '10.0.1.1' `
                -LiveMigrationIP '10.0.2.1' -Confirm:$false } | Should -Not -Throw
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-VMSwitch -Times 1 -Exactly `
            -ParameterFilter { $EnableEmbeddedTeaming -eq $true }
    }
}
