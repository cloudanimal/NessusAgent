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
        (Get-Command Restore-NessusAgent).Parameters.ContainsKey('AcceptEula') | Should -BeFalse
    }

    It 'does not export Invoke-NessusAgentDeployment from the module' {
        Get-Command Invoke-NessusAgentDeployment -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'reports no change for a healthy agent' {
        $script:HarnessOutput | Should -Match 'Scenario\s+: Healthy'
        $script:HarnessOutput | Should -Match 'Changed\s+: False'
        $script:HarnessOutput | Should -Match 'BeforeStatus\s+: Warning'
        $script:HarnessOutput | Should -Match 'AfterStatus\s+: Warning'
        $script:HarnessOutput | Should -Match 'HealthSummary\s+: WARNING: Last successful connect is older than 24 hours\.; Last connection attempt is older than 24 hours\.'
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
        $script:TagHarnessOutput | Should -Match 'Actions\s+: RemoveTagRegistry:Removed; UnlinkAgent:Success; LinkAgent:Success:Windows Servers:Csv'
        $script:TagHarnessOutput | Should -Match 'RemovedPaths\s+: HKLM:\\SOFTWARE\\Tenable\\TAG'
    }
}
