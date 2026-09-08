BeforeAll {
    Import-Module "$PSScriptRoot/../../Deploy-S2D.psm1" -Force
}

Describe 'Deploy-S2D module' {
    It 'has a valid manifest' {
        { Test-ModuleManifest "$PSScriptRoot/../../Deploy-S2D.psd1" -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports exactly the three public functions' {
        $names = (Get-Command -Module Deploy-S2D).Name | Sort-Object
        $names | Should -Be @('New-S2DCluster', 'Start-S2DDeployment', 'Start-S2DNodePrep')
    }

    It 'keeps helpers private' {
        (Get-Command -Module Deploy-S2D).Name | Should -Not -Contain 'Write-S2DLog'
        (Get-Command -Module Deploy-S2D).Name | Should -Not -Contain 'Select-S2DNic'
    }
}
