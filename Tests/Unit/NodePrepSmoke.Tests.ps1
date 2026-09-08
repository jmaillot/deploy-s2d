# Start-S2DNodePrep with every external cmdlet mocked (static returns only).
# Two scopes: existing vSwitch (pipe path) and missing vSwitch (creation path).
BeforeAll {
    Import-Module "$PSScriptRoot/../../Deploy-S2D/Deploy-S2D.psm1" -Force

    # The runner image lacks some role cmdlets (Hyper-V, DCB). Define global
    # stubs for anything missing so Mock -ModuleName can attach; mocks replace
    # them entirely, so no real host is ever touched.
    $externals = @(
        'Add-Content', 'Get-NetAdapter', 'Get-CimInstance', 'Get-SmbClientNetworkInterface',
        'Rename-NetAdapter', 'Set-NetAdapterAdvancedProperty', 'Set-NetIPInterface',
        'Remove-NetIPAddress', 'New-NetIPAddress', 'Remove-NetQosPolicy', 'Get-NetQosPolicy',
        'New-NetQosPolicy', 'Enable-NetQosFlowControl', 'Disable-NetQosFlowControl',
        'Set-NetQosDcbxSetting', 'Get-NetAdapterQos', 'Enable-NetAdapterQos',
        'Get-NetAdapterRdma', 'Enable-NetAdapterRdma', 'Get-NetAdapterVmq', 'Disable-NetAdapterVmq', 'Enable-NetAdapterVmq', 'Enable-NetAdapterRss', 'Enable-NetAdapterRsc',
        'Get-NetAdapterRsc', 'Disable-NetAdapterRsc', 'Enable-NetAdapterRss', 'Get-VMSwitch', 'New-VMSwitch',
        'Set-VMSwitch', 'Set-VMHost', 'Get-VMMigrationNetwork', 'Add-VMMigrationNetwork',
        'Set-DnsClient'
    )
    foreach ($e in $externals) {
        if (-not (Get-Command $e -ErrorAction SilentlyContinue)) {
            New-Item -Path "function:Global:$e" -Value {} -Force | Out-Null
        }
    }

    Mock -ModuleName Deploy-S2D Add-Content -MockWith {}
    Mock -ModuleName Deploy-S2D Get-NetAdapter -MockWith {
        # NOTE: $PSBoundParameters is empty here - Pester exposes the mocked
        # call's arguments as plain variables, so test $Name directly.
        if ($Name) {
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
    Mock -ModuleName Deploy-S2D Get-NetAdapterAdvancedProperty -MockWith {
        [pscustomobject]@{ DisplayName = 'Jumbo Packet'; RegistryKeyword = '*JumboPacket'; RegistryValue = 9014 }
    }
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
    Mock -ModuleName Deploy-S2D Get-NetAdapterVmq -MockWith { [pscustomobject]@{ Enabled = $true } }
    Mock -ModuleName Deploy-S2D Disable-NetAdapterVmq -MockWith {}
    Mock -ModuleName Deploy-S2D Enable-NetAdapterVmq -MockWith {}
    Mock -ModuleName Deploy-S2D Enable-NetAdapterRss -MockWith {}
    Mock -ModuleName Deploy-S2D Enable-NetAdapterRsc -MockWith {}
    Mock -ModuleName Deploy-S2D Get-NetAdapterRsc -MockWith {}
    Mock -ModuleName Deploy-S2D Disable-NetAdapterRsc -MockWith {}
    Mock -ModuleName Deploy-S2D Get-VMSwitch -MockWith { [pscustomobject]@{ Name = 'vSwitch-VM' } }
    Mock -ModuleName Deploy-S2D New-VMSwitch -MockWith {}
    Mock -ModuleName Deploy-S2D Set-VMSwitch -MockWith {}
    Mock -ModuleName Deploy-S2D Set-DnsClient -MockWith {}
    Mock -ModuleName Deploy-S2D Set-VMHost -MockWith {}
    Mock -ModuleName Deploy-S2D Get-VMMigrationNetwork -MockWith {}
    Mock -ModuleName Deploy-S2D Add-VMMigrationNetwork -MockWith {}
}

Describe 'Start-S2DNodePrep with existing vSwitch (mocked)' {
    It 'completes and reuses the switch' {
        { Start-S2DNodePrep -MgmtAdapters 'M1', 'M2' -VMAdapters 'V1', 'V2' -StorageA 'S1' -StorageB 'S2' -LiveMigrationAdapter 'L1' -StorageAIP '10.0.0.1' -StorageBIP '10.0.1.1' -LiveMigrationIP '10.0.2.1' -Confirm:$false } | Should -Not -Throw
        Should -Invoke -ModuleName Deploy-S2D -CommandName Rename-NetAdapter -Times 7 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-NetIPAddress -Times 3 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName Set-DnsClient -Times 3 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName Disable-NetAdapterVmq -Times 3 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName Disable-NetAdapterRsc -Times 1 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName Enable-NetAdapterVmq -Times 1 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName Enable-NetAdapterRss -Times 3 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName Enable-NetAdapterRsc -Times 1 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName Set-NetAdapterAdvancedProperty -Times 4 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName Set-NetAdapterAdvancedProperty -Times 0 -Exactly `
            -ParameterFilter { $Name -like 'VM*' -or $Name -like 'Mgmt*' }
        Should -Invoke -ModuleName Deploy-S2D -CommandName Set-VMHost -Times 1 -Exactly
        Should -Invoke -ModuleName Deploy-S2D -CommandName Add-VMMigrationNetwork -Times 1 -Exactly -ParameterFilter { $Subnet -eq '10.0.2.0/24' }
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-VMSwitch -Times 0 -Exactly
    }
}

Describe 'Start-S2DNodePrep with missing vSwitch (mocked)' {
    BeforeAll {
        Mock -ModuleName Deploy-S2D Get-VMSwitch -MockWith {}
    }

    It 'creates a SET team' {
        { Start-S2DNodePrep -MgmtAdapters 'M1', 'M2' -VMAdapters 'V1', 'V2' -StorageA 'S1' -StorageB 'S2' -LiveMigrationAdapter 'L1' -StorageAIP '10.0.0.1' -StorageBIP '10.0.1.1' -LiveMigrationIP '10.0.2.1' -Confirm:$false } | Should -Not -Throw
        Should -Invoke -ModuleName Deploy-S2D -CommandName New-VMSwitch -Times 1 -Exactly -ParameterFilter { $EnableEmbeddedTeaming -eq $true }
    }
}
