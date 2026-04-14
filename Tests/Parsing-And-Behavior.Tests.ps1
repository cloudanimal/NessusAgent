Describe 'ConvertTo-NessusDateTime' {
    BeforeAll {
        $moduleManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Restore-NessusAgent.psd1'
        Import-Module $moduleManifestPath -Force
        $privateDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Private'
        . (Join-Path $privateDir 'ConvertTo-NessusDateTime.ps1')
    }

    It 'returns $null for null input' {
        ConvertTo-NessusDateTime -Value $null | Should -BeNullOrEmpty
    }

    It 'returns $null for empty string' {
        ConvertTo-NessusDateTime -Value '' | Should -BeNullOrEmpty
    }

    It 'returns $null for whitespace' {
        ConvertTo-NessusDateTime -Value '   ' | Should -BeNullOrEmpty
    }

    It 'parses a standard datetime string' {
        $result = ConvertTo-NessusDateTime -Value '2026/03/20 09:15:42'
        $result | Should -BeOfType [datetime]
        $result.Year | Should -Be 2026
        $result.Month | Should -Be 3
        $result.Day | Should -Be 20
    }

    It 'parses a Unix epoch timestamp (integer string)' {
        # 1776113787 = 2026-04-13 20:56:27 UTC
        $result = ConvertTo-NessusDateTime -Value '1776113787'
        $result | Should -BeOfType [datetime]
        $result | Should -Not -BeNullOrEmpty
    }

    It 'returns $null for an unparseable non-numeric string' {
        ConvertTo-NessusDateTime -Value 'not-a-date' | Should -BeNullOrEmpty
    }
}

Describe 'Get-NessusAgentStatus LinkStatus parsing' {
    BeforeAll {
        $moduleManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Restore-NessusAgent.psd1'
        Import-Module $moduleManifestPath -Force
    }

    It 'sets AgentStatus to Connected when LinkStatus is "Connected to host:port"' {
        $rawOutput = @'
Running: Yes
Safe Mode: No
Plugins loaded: Yes
Linked to: sensor.cloud.tenable.com:443
Link status: Connected to sensor.cloud.tenable.com:443
Proxy: None
Plugin set: 202603200915
Scanning: No (0 jobs pending, 0 smart scan configs)
Scans run today: 0 of 10 limit
Last scanned: Never
Last connect: 1776113787
Last connection attempt: 1776113787
'@
        Mock -CommandName Invoke-NessusCli -ModuleName Restore-NessusAgent -MockWith {
            [pscustomobject]@{
                ExitCode   = 0
                Output     = $rawOutput -split "`n"
                OutputText = $rawOutput
            }
        }

        $result = Get-NessusAgentStatus
        $result.AgentStatus | Should -Be 'Connected'
        $result.LinkStatus | Should -BeLike 'Connected*'
    }

    It 'parses a Unix timestamp in Last connect into a datetime' {
        $rawOutput = @'
Running: Yes
Linked to: sensor.cloud.tenable.com:443
Link status: Connected to sensor.cloud.tenable.com:443
Proxy: None
Plugin set: 202603200915
Scanning: No (0 jobs pending, 0 smart scan configs)
Scans run today: 0 of 10 limit
Last scanned: Never
Last connect: 1776113787
Last connection attempt: 1776113787
'@
        Mock -CommandName Invoke-NessusCli -ModuleName Restore-NessusAgent -MockWith {
            [pscustomobject]@{
                ExitCode   = 0
                Output     = $rawOutput -split "`n"
                OutputText = $rawOutput
            }
        }

        $result = Get-NessusAgentStatus
        $result.LastConnect | Should -BeOfType [datetime]
        $result.LastConnectionAttempt | Should -BeOfType [datetime]
    }

    It 'does not throw when nessuscli exits non-zero but produces output (agent unlinked)' {
        $rawOutput = @'
Running: Yes
Linked to: None
Link status: Not linked to a manager
Proxy: None
Plugin set: (null)
Scanning: No (0 jobs pending, 0 smart scan configs)
Scans run today: 0 of 10 limit
Last scanned: Never
Last connect: Never
Last connection attempt: Never
'@
        Mock -CommandName Invoke-NessusCli -ModuleName Restore-NessusAgent -MockWith {
            [pscustomobject]@{
                ExitCode   = 1
                Output     = $rawOutput -split "`n"
                OutputText = $rawOutput
            }
        }

        { Get-NessusAgentStatus } | Should -Not -Throw
        $result = Get-NessusAgentStatus
        $result.AgentStatus | Should -Be 'Unlinked'
    }
}

Describe 'Get-NessusAgentHealth sentinel handling' {
    BeforeAll {
        $moduleManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Restore-NessusAgent.psd1'
        Import-Module $moduleManifestPath -Force
    }

    It 'does not raise a parse-error warning for "Never" in LastScanned' {
        $status = [pscustomobject]@{
            Running                      = 'Yes'
            LinkedTo                     = 'sensor.cloud.tenable.com:443'
            LinkStatus                   = 'Connected to sensor.cloud.tenable.com:443'
            LastScanned                  = $null
            LastScannedText              = 'Never'
            LastConnect                  = [datetime]'2026-04-13T20:56:27'
            LastConnectText              = '1776113787'
            LastConnectionAttempt        = [datetime]'2026-04-13T20:56:27'
            LastConnectionAttemptText    = '1776113787'
            AgentStatus                  = 'Connected'
            JobsPending                  = $null
        }

        $health = Get-NessusAgentHealth -InputObject $status -ExpectedHost 'sensor.cloud.tenable.com'

        $lastScannedFinding = @($health.Findings | Where-Object { $_.Property -eq 'LastScanned' })
        $lastScannedFinding.Count | Should -Be 0
    }

    It 'reports OverallStatus OK when connected with "Never" last scanned' {
        $status = [pscustomobject]@{
            Running                      = 'Yes'
            LinkedTo                     = 'sensor.cloud.tenable.com:443'
            LinkStatus                   = 'Connected to sensor.cloud.tenable.com:443'
            LastScanned                  = $null
            LastScannedText              = 'Never'
            LastConnect                  = [datetime]'2026-04-13T20:56:27'
            LastConnectText              = '1776113787'
            LastConnectionAttempt        = [datetime]'2026-04-13T20:56:27'
            LastConnectionAttemptText    = '1776113787'
            AgentStatus                  = 'Connected'
            JobsPending                  = $null
        }

        $health = Get-NessusAgentHealth -InputObject $status -ExpectedHost 'sensor.cloud.tenable.com'

        $health.OverallStatus | Should -Be 'OK'
        $health.IsHealthy | Should -BeTrue
    }
}

Describe 'Restore-NessusAgent unlink tolerance' {
    BeforeAll {
        $moduleManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Restore-NessusAgent.psd1'
        Import-Module $moduleManifestPath -Force
    }

    It 'tolerates unlink failure when agent was not previously linked' {
        $unlinkCallCount = 0
        $linkCallCount = 0

        Mock -CommandName Get-NessusAgentStatus -ModuleName Restore-NessusAgent -MockWith {
            [pscustomobject]@{
                Running                      = 'Yes'
                LinkedTo                     = 'None'
                LinkStatus                   = 'Not linked to a manager'
                LastScanned                  = $null
                LastScannedText              = 'Never'
                LastConnect                  = $null
                LastConnectText              = 'Never'
                LastConnectionAttempt        = $null
                LastConnectionAttemptText    = 'Never'
                AgentStatus                  = 'Unlinked'
                JobsPending                  = $null
                StatusExitCode               = 1
                RawOutput                    = ''
            }
        }

        Mock -CommandName Invoke-NessusCli -ModuleName Restore-NessusAgent -MockWith {
            param([string]$Path, [string[]]$ArgumentList)
            if ($ArgumentList -contains 'unlink') {
                $unlinkCallCount++
                return [pscustomobject]@{ ExitCode = 1; Output = @('[error] [agent] No host information found'); OutputText = '[error] [agent] No host information found' }
            }
            if ($ArgumentList -contains 'link') {
                $linkCallCount++
                return [pscustomobject]@{ ExitCode = 0; Output = @('Successfully linked'); OutputText = 'Successfully linked' }
            }
            [pscustomobject]@{ ExitCode = 0; Output = @(); OutputText = '' }
        }

        Mock -CommandName Remove-NessusAgentTagRegistry -ModuleName Restore-NessusAgent -MockWith {
            [pscustomobject]@{ Removed = $false; Path = $null; Result = 'NotFound' }
        }

        Mock -CommandName Test-Path -ModuleName Restore-NessusAgent -ParameterFilter { $LiteralPath -eq 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe' } -MockWith { $true }

        Mock -CommandName Get-MeDistributionServer -ModuleName Restore-NessusAgent -MockWith { $null }

        Mock -CommandName Start-Sleep -ModuleName Restore-NessusAgent -MockWith { }

        $result = Restore-NessusAgent `
            -Path 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe' `
            -Relink `
            -LinkingKey 'testkey' `
            -GroupName 'AIGI-Server' `
            -TargetHost 'sensor.cloud.tenable.com' `
            -Port 443 `
            -Confirm:$false

        $unlinkAction = @($result.Actions | Where-Object { $_.Action -eq 'UnlinkAgent' })
        $linkAction   = @($result.Actions | Where-Object { $_.Action -eq 'LinkAgent' })

        $unlinkAction.Count | Should -Be 1
        $unlinkAction[0].Result | Should -Be 'Skipped'
        $linkAction.Count | Should -Be 1
        $linkAction[0].Result | Should -Be 'Success'
    }

    It 'retries status checks after relink until link status is connected' {
        $script:statusCallCount = 0

        Mock -CommandName Get-NessusAgentStatus -ModuleName Restore-NessusAgent -MockWith {
            $script:statusCallCount++

            if ($script:statusCallCount -lt 4) {
                return [pscustomobject]@{
                    Running                   = 'Yes'
                    LinkedTo                  = 'None'
                    LinkStatus                = 'connection has not been attempted'
                    LastScanned               = [datetime]'2026-04-13T20:56:27'
                    LastScannedText           = '1776113787'
                    LastConnect               = [datetime]'2026-04-13T20:56:27'
                    LastConnectText           = '1776113787'
                    LastConnectionAttempt     = [datetime]'2026-04-13T20:56:27'
                    LastConnectionAttemptText = '1776113787'
                    AgentStatus               = 'Degraded'
                    JobsPending               = $null
                    StatusExitCode            = 1
                    RawOutput                 = ''
                }
            }

            [pscustomobject]@{
                Running                   = 'Yes'
                LinkedTo                  = 'sensor.cloud.tenable.com:443'
                LinkStatus                = 'Connected to sensor.cloud.tenable.com:443'
                LastScanned               = [datetime]'2026-04-13T20:56:27'
                LastScannedText           = '1776113787'
                LastConnect               = [datetime]'2026-04-13T20:56:27'
                LastConnectText           = '1776113787'
                LastConnectionAttempt     = [datetime]'2026-04-13T20:56:27'
                LastConnectionAttemptText = '1776113787'
                AgentStatus               = 'Connected'
                JobsPending               = $null
                StatusExitCode            = 0
                RawOutput                 = ''
            }
        }

        Mock -CommandName Invoke-NessusCli -ModuleName Restore-NessusAgent -MockWith {
            param([string]$Path, [string[]]$ArgumentList)
            if ($ArgumentList -contains 'unlink') {
                return [pscustomobject]@{ ExitCode = 1; Output = @('[error] [agent] No host information found'); OutputText = '[error] [agent] No host information found' }
            }
            if ($ArgumentList -contains 'link') {
                return [pscustomobject]@{ ExitCode = 0; Output = @('Successfully linked'); OutputText = 'Successfully linked' }
            }
            [pscustomobject]@{ ExitCode = 0; Output = @(); OutputText = '' }
        }

        Mock -CommandName Remove-NessusAgentTagRegistry -ModuleName Restore-NessusAgent -MockWith {
            [pscustomobject]@{ Removed = $false; Path = $null; Result = 'NotFound' }
        }

        Mock -CommandName Test-Path -ModuleName Restore-NessusAgent -ParameterFilter { $LiteralPath -eq 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe' } -MockWith { $true }
        Mock -CommandName Get-MeDistributionServer -ModuleName Restore-NessusAgent -MockWith { $null }
        Mock -CommandName Start-Sleep -ModuleName Restore-NessusAgent -MockWith { }

        $result = Restore-NessusAgent `
            -Path 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe' `
            -Relink `
            -LinkingKey 'testkey' `
            -GroupName 'AIGI-Server' `
            -TargetHost 'sensor.cloud.tenable.com' `
            -Port 443 `
            -LinkStatusRetryCount 4 `
            -LinkStatusRetryDelaySeconds 1 `
            -Confirm:$false

        Assert-MockCalled -CommandName Start-Sleep -ModuleName Restore-NessusAgent -Times 2 -Exactly -ParameterFilter { $Seconds -eq 1 }
        $result.After.OverallStatus | Should -Be 'OK'
        $result.After.IsHealthy | Should -BeTrue
    }
}

Describe 'Invoke-RestoreNessusAgent JSON warning capture regression' {
    It 'suppresses restore warning stream and captures warning records into JSON warnings' {
        $scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Scripts\Invoke-RestoreNessusAgent.ps1'
        $content = Get-Content -LiteralPath $scriptPath -Raw

        $content | Should -Match 'Restore-NessusAgent\s+@restoreParams\s+-WarningAction\s+SilentlyContinue\s+-WarningVariable\s+\+restoreWarnings'
        $content | Should -Match 'if \(\$restoreWarnings\)'
        $content | Should -Match '\$restoreWarnings\s*\|\s*ForEach-Object'
    }

    It 'keeps operator JSON collection fields normalized as arrays' {
        $scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Scripts\Invoke-RestoreNessusAgent.ps1'
        $content = Get-Content -LiteralPath $scriptPath -Raw

        $content | Should -Match 'foreach \(\$name in @\(''actions'', ''warnings'', ''errors''\)\)'
        $content | Should -Match '\$normalized\[\$name\]\s*=\s*@\(\)'
        $content | Should -Match '\$normalized\[\$name\]\s*=\s*@\(\$value\)'
    }
}
