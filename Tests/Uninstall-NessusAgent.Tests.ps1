Describe 'Uninstall-NessusAgent safeguards' {
    BeforeAll {
        $moduleManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Restore-NessusAgent.psd1'
        Import-Module $moduleManifestPath -Force
    }

    It 'returns preflight details and does not invoke msiexec when PreflightOnly is set' {
        Mock -CommandName Get-ItemProperty -ModuleName Restore-NessusAgent -MockWith {
            @([pscustomobject]@{
                DisplayName = 'Nessus Agent (x64)'
                Publisher = 'Tenable, Inc.'
                InstallLocation = 'C:\Program Files\Tenable\Nessus Agent'
                UninstallString = 'MsiExec.exe /X{D0822BC1-BFBE-44E9-BC56-7378EFE30433}'
            })
        }
        Mock -CommandName Get-Service -ModuleName Restore-NessusAgent -MockWith {
            [pscustomobject]@{ Name = 'Tenable Nessus Agent'; Status = 'Running' }
        }
        Mock -CommandName Stop-Service -ModuleName Restore-NessusAgent -MockWith { }
        Mock -CommandName Get-Process -ModuleName Restore-NessusAgent -MockWith { @() }
        Mock -CommandName Stop-Process -ModuleName Restore-NessusAgent -MockWith { }
        Mock -CommandName Start-Process -ModuleName Restore-NessusAgent -MockWith {
            [pscustomobject]@{ ExitCode = 0 }
        }

        $result = Uninstall-NessusAgent -AllowUninstall -ProductCode '{D0822BC1-BFBE-44E9-BC56-7378EFE30433}' -PreflightOnly -Confirm:$false

        $result.PreflightPassed | Should -BeTrue
        $result.SafetyChecksPassed | Should -BeTrue
        $result.DetailedResult | Should -Be 'preflight checks passed; uninstall not executed'
        Assert-MockCalled -CommandName Start-Process -ModuleName Restore-NessusAgent -Times 0 -Exactly
    }

    It 'refuses uninstall when Nessus processes still remain after retry attempts' {
        Mock -CommandName Get-ItemProperty -ModuleName Restore-NessusAgent -MockWith {
            @([pscustomobject]@{
                DisplayName = 'Nessus Agent (x64)'
                Publisher = 'Tenable, Inc.'
                InstallLocation = 'C:\Program Files\Tenable\Nessus Agent'
                UninstallString = 'MsiExec.exe /X{D0822BC1-BFBE-44E9-BC56-7378EFE30433}'
            })
        }
        Mock -CommandName Get-Service -ModuleName Restore-NessusAgent -MockWith {
            [pscustomobject]@{ Name = 'Tenable Nessus Agent'; Status = 'Running' }
        }
        Mock -CommandName Stop-Service -ModuleName Restore-NessusAgent -MockWith { }
        Mock -CommandName Stop-Process -ModuleName Restore-NessusAgent -MockWith { }
        Mock -CommandName Start-Sleep -ModuleName Restore-NessusAgent -MockWith { }
        Mock -CommandName Get-Process -ModuleName Restore-NessusAgent -MockWith {
            @([pscustomobject]@{ Name = 'nessusd'; Id = 9999 })
        }

        { Uninstall-NessusAgent -AllowUninstall -ProductCode '{D0822BC1-BFBE-44E9-BC56-7378EFE30433}' -Confirm:$false } | Should -Throw '*still running*'
    }

    It 'proceeds to msiexec only after processes are cleared' {
        $script:getProcessCalls = 0

        Mock -CommandName Get-ItemProperty -ModuleName Restore-NessusAgent -MockWith {
            @([pscustomobject]@{
                DisplayName = 'Nessus Agent (x64)'
                Publisher = 'Tenable, Inc.'
                InstallLocation = 'C:\Program Files\Tenable\Nessus Agent'
                UninstallString = 'MsiExec.exe /X{D0822BC1-BFBE-44E9-BC56-7378EFE30433}'
            })
        }
        Mock -CommandName Get-Service -ModuleName Restore-NessusAgent -MockWith {
            [pscustomobject]@{ Name = 'Tenable Nessus Agent'; Status = 'Running' }
        }
        Mock -CommandName Stop-Service -ModuleName Restore-NessusAgent -MockWith { }
        Mock -CommandName Stop-Process -ModuleName Restore-NessusAgent -MockWith { }
        Mock -CommandName Start-Sleep -ModuleName Restore-NessusAgent -MockWith { }
        Mock -CommandName Get-Process -ModuleName Restore-NessusAgent -MockWith {
            $script:getProcessCalls++
            if ($script:getProcessCalls -le 2) {
                @([pscustomobject]@{ Name = 'nessusd'; Id = 10001 })
            }
            else {
                @()
            }
        }
        Mock -CommandName Start-Process -ModuleName Restore-NessusAgent -MockWith {
            [pscustomobject]@{ ExitCode = 1605 }
        }

        $result = Uninstall-NessusAgent -AllowUninstall -ProductCode '{D0822BC1-BFBE-44E9-BC56-7378EFE30433}' -Confirm:$false
        $result.DetailedResult | Should -Be 'product is not installed'
        Assert-MockCalled -CommandName Start-Process -ModuleName Restore-NessusAgent -Times 1
    }
}
