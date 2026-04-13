Describe 'Restore-NessusAgent harness' {
    BeforeAll {
        $harnessPath = Join-Path $PSScriptRoot 'Invoke-RestoreNessusAgentHarness.ps1'
        $script:HarnessOutput = (& $harnessPath | Out-String)
        $tagHarnessPath = Join-Path $PSScriptRoot 'Invoke-RestoreNessusAgentTagHarness.ps1'
        $script:TagHarnessOutput = (& $tagHarnessPath | Out-String)
        $moduleManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Restore-NessusAgent.psd1'
        Import-Module $moduleManifestPath -Force
    }

    It 'does not expose AcceptEula on public install and repair commands' {
        (Get-Command Get-NessusAgentInstaller).Parameters.ContainsKey('AcceptEula') | Should -BeFalse
        (Get-Command Install-NessusAgent).Parameters.ContainsKey('AcceptEula') | Should -BeFalse
        (Get-Command Uninstall-NessusAgent).Parameters.ContainsKey('AcceptEula') | Should -BeFalse
        (Get-Command Restore-NessusAgent).Parameters.ContainsKey('AcceptEula') | Should -BeFalse
    }

    It 'exports uninstall command for agent removal workflows' {
        Get-Command Uninstall-NessusAgent -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'refuses uninstall when product code format is invalid' {
        { Uninstall-NessusAgent -AllowUninstall -ProductCode 'not-a-guid' -Confirm:$false } | Should -Throw 'Invalid ProductCode format*'
    }

    It 'refuses uninstall when product code is not found in uninstall registry entries' {
        Mock -CommandName Get-ItemProperty -ModuleName Restore-NessusAgent -MockWith { @() }
        { Uninstall-NessusAgent -AllowUninstall -ProductCode '{11111111-1111-1111-1111-111111111111}' -Confirm:$false } | Should -Throw "*not found in registered uninstall entries*"
    }

    It 'refuses uninstall when product code resolves to a non-Nessus product' {
        Mock -CommandName Get-ItemProperty -ModuleName Restore-NessusAgent -MockWith {
            @([pscustomobject]@{
                DisplayName = 'Some Other Product'
                Publisher = 'Other Vendor'
                InstallLocation = 'C:\Program Files\Other'
                UninstallString = 'msiexec.exe /x {22222222-2222-2222-2222-222222222222}'
            })
        }

        { Uninstall-NessusAgent -AllowUninstall -ProductCode '{22222222-2222-2222-2222-222222222222}' -Confirm:$false } | Should -Throw '*is not recognized as Tenable Nessus Agent*'
    }

    It 'refuses auto-discovery when multiple Nessus Agent uninstall candidates are found' {
        Mock -CommandName Test-Path -ModuleName Restore-NessusAgent -ParameterFilter { $LiteralPath -eq 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe' } -MockWith { $true }
        Mock -CommandName Get-ItemProperty -ModuleName Restore-NessusAgent -MockWith {
            @(
                [pscustomobject]@{
                    DisplayName = 'Tenable Nessus Agent'
                    Publisher = 'Tenable, Inc.'
                    InstallLocation = 'C:\Program Files\Tenable\Nessus Agent'
                    UninstallString = 'msiexec.exe /x {33333333-3333-3333-3333-333333333333}'
                },
                [pscustomobject]@{
                    DisplayName = 'Tenable Nessus Agent'
                    Publisher = 'Tenable, Inc.'
                    InstallLocation = 'C:\Program Files\Tenable\Nessus Agent'
                    UninstallString = 'msiexec.exe /x {44444444-4444-4444-4444-444444444444}'
                }
            )
        }

        { Uninstall-NessusAgent -AllowUninstall -Confirm:$false } | Should -Throw '*Multiple Nessus Agent uninstall candidates*'
    }

    It 'writes an uninstall audit event on refusal' {
        $auditPath = Join-Path $env:TEMP ('nessus-uninstall-audit-{0}.log' -f [guid]::NewGuid().ToString())
        try {
            { Uninstall-NessusAgent -AllowUninstall -ProductCode 'bad-code' -AuditLogPath $auditPath -Confirm:$false } | Should -Throw
            Test-Path -LiteralPath $auditPath | Should -BeTrue
            (Get-Content -LiteralPath $auditPath -Raw) | Should -Match '"Command":"Uninstall-NessusAgent"'
            (Get-Content -LiteralPath $auditPath -Raw) | Should -Match '"Outcome":"Refused"'
        }
        finally {
            if (Test-Path -LiteralPath $auditPath) {
                Remove-Item -LiteralPath $auditPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'does not export Invoke-NessusAgentDeployment from the module' {
        Get-Command Invoke-NessusAgentDeployment -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'reports no change for a healthy agent' {
        $script:HarnessOutput | Should -Match 'Scenario\s+: Healthy'
        $script:HarnessOutput | Should -Match 'Changed\s+: False'
        $script:HarnessOutput | Should -Match 'BeforeStatus\s+: Warning'
        $script:HarnessOutput | Should -Match 'AfterStatus\s+: Warning'
    }

    It 'relinks a wrong target using the CSV group' {
        $script:HarnessOutput | Should -Match 'Scenario\s+: Wrong cloud target with CSV group'
        $script:HarnessOutput | Should -Match 'Actions\s+: UnlinkAgent:Success; LinkAgent:Success:Windows Servers:Csv'
    }

    It 'does not unlink when the CSV group is missing and override is not set' {
        $script:HarnessOutput | Should -Match 'Scenario\s+: Wrong cloud target with missing CSV group and no override'
        $script:HarnessOutput | Should -Match 'Actions\s+: ResolveGroup:Failed'
    }

    It 'falls back to SCPM when override is enabled' {
        $script:HarnessOutput | Should -Match 'Scenario\s+: Wrong cloud target with missing CSV group and override'
        $script:HarnessOutput | Should -Match 'LinkAgent:Success:SCPM:Override'
    }

    It 'removes the Tenable TAG registry key before relink when it exists' {
        $script:TagHarnessOutput | Should -Match 'DetailedResult\s+: wrong target with CSV group: unlink \+ relink using CSV group'
        [regex]::Match($script:TagHarnessOutput, 'Actions.*RemoveTagRegistry:Removed', 'Singleline').Success | Should -Be $true
        $script:TagHarnessOutput | Should -Match 'RemovedPaths\s+: HKLM:\\SOFTWARE\\Tenable\\TAG'
    }
}
