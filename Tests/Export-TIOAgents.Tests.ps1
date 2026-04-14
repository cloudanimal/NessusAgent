Describe 'Export-TIOAgents script behavior' {
    BeforeAll {
        $scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Public\Export-TIOAgents.ps1'
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "Script not found: $scriptPath"
        }

        Add-Type -TypeDefinition @"
public class TioMockStatusCode {
    public int value__;
    public TioMockStatusCode(int code) { value__ = code; }
}
public class TioMockResponse {
    public TioMockStatusCode StatusCode;
    public TioMockResponse(int code) { StatusCode = new TioMockStatusCode(code); }
}
public class TioMockHttpException : System.Exception {
    public TioMockResponse Response;
    public TioMockHttpException(int code, string message) : base(message) {
        Response = new TioMockResponse(code);
    }
}
"@ -ErrorAction SilentlyContinue
    }

    function New-TioHttpException {
        param([int]$StatusCode, [string]$Message = 'HTTP error')

        return [TioMockHttpException]::new($StatusCode, $Message)
    }

    It 'does not emit stray pipeline output from script tail' {
        $outDir = Join-Path $TestDrive 'out-no-output'

        Mock -CommandName Invoke-RestMethod -MockWith {
            param([string]$Method, [string]$Uri, [hashtable]$Headers)

            if ($Uri -like '*scanners/1/agents`?*') {
                return [pscustomobject]@{
                    agents = @(
                        [pscustomobject]@{
                            id = 1001
                            name = 'SERVER01'
                            last_connect = 1776113787
                            last_scanned = 1776113787
                        }
                    )
                }
            }

            if ($Uri -like '*scanners/1/agent-groups') {
                return [pscustomobject]@{ groups = @() }
            }

            throw (New-TioHttpException -StatusCode 500 -Message "Unexpected URI: $Uri")
        }

        $result = & $scriptPath -ScannerId 1 -OutDir $outDir -Mode Fast -AccessKey 'ak' -SecretKey 'sk'

        @($result).Count | Should -Be 0
    }

    It 'handles Never and millisecond epoch timestamps without failing report export' {
        $outDir = Join-Path $TestDrive 'out-timestamps'

        Mock -CommandName Invoke-RestMethod -MockWith {
            param([string]$Method, [string]$Uri, [hashtable]$Headers)

            if ($Uri -like '*scanners/1/agents`?*') {
                return [pscustomobject]@{
                    agents = @(
                        [pscustomobject]@{
                            id = 2001
                            name = 'SERVER-NEVER'
                            last_connect = 'Never'
                            last_scanned = '(null)'
                        },
                        [pscustomobject]@{
                            id = 2002
                            name = 'SERVER-MS'
                            last_connect = '1776113787000'
                            last_scanned = '1776113787000'
                        }
                    )
                }
            }

            if ($Uri -like '*scanners/1/agent-groups') {
                return [pscustomobject]@{ groups = @() }
            }

            throw (New-TioHttpException -StatusCode 500 -Message "Unexpected URI: $Uri")
        }

        $null = & $scriptPath -ScannerId 1 -OutDir $outDir -Mode Fast -AccessKey 'ak' -SecretKey 'sk'

        $csvPath = Join-Path $outDir 'TioAgentInventory_Fast_Scanner1.csv'
        Test-Path -LiteralPath $csvPath | Should -BeTrue

        $rows = Import-Csv -LiteralPath $csvPath

        $neverRow = $rows | Where-Object { $_.Hostname -eq 'SERVER-NEVER' } | Select-Object -First 1
        $msRow = $rows | Where-Object { $_.Hostname -eq 'SERVER-MS' } | Select-Object -First 1

        $neverRow | Should -Not -BeNullOrEmpty
        $msRow | Should -Not -BeNullOrEmpty

        $neverRow.LastConnectUtc | Should -BeNullOrEmpty
        $neverRow.LastScannedUtc | Should -BeNullOrEmpty
        $msRow.LastConnectUtc | Should -Not -BeNullOrEmpty
        $msRow.LastScannedUtc | Should -Not -BeNullOrEmpty
    }

    It 'initializes skipped 404 state per run and keeps summary count stable across repeat runs' {
        $outDir = Join-Path $TestDrive 'out-skipped-reset'

        Mock -CommandName Invoke-RestMethod -MockWith {
            param([string]$Method, [string]$Uri, [hashtable]$Headers)

            if ($Uri -like '*scanners/1/agents`?*') {
                return [pscustomobject]@{
                    agents = @(
                        [pscustomobject]@{
                            id = 3001
                            name = 'SERVER-NO404'
                            last_connect = 1776113787
                            last_scanned = 1776113787
                        }
                    )
                }
            }

            if ($Uri -like '*scanners/1/agents/3001') {
                return [pscustomobject]@{
                    id = 3001
                    uuid = 'abc'
                }
            }

            if ($Uri -like '*scanners/1/agent-groups') {
                return [pscustomobject]@{ groups = @() }
            }

            throw (New-TioHttpException -StatusCode 500 -Message "Unexpected URI: $Uri")
        }

        $scriptContent = Get-Content -LiteralPath $scriptPath -Raw
        $scriptContent | Should -Match '\$script:Skipped404\s*=\s*New-Object\s+System\.Collections\.Generic\.List\[object\]'

        $null = & $scriptPath -ScannerId 1 -OutDir $outDir -Mode Detail -AccessKey 'ak' -SecretKey 'sk' -ThrottleMs 0
        $summaryPath = Join-Path $outDir 'TioAgentInventory_Detail_Scanner1_RunSummary.json'
        $summary1 = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        [int]$summary1.Skipped404Count | Should -Be 0

        $null = & $scriptPath -ScannerId 1 -OutDir $outDir -Mode Detail -AccessKey 'ak' -SecretKey 'sk' -ThrottleMs 0
        $summary2 = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        [int]$summary2.Skipped404Count | Should -Be 0
    }

    It 'resolves group membership when agent appears on a later members page' {
        $outDir = Join-Path $TestDrive 'out-group-pagination'

        Mock -CommandName Invoke-RestMethod -MockWith {
            param([string]$Method, [string]$Uri, [hashtable]$Headers)

            if ($Uri -like '*scanners/1/agents`?*') {
                return [pscustomobject]@{
                    agents = @(
                        [pscustomobject]@{
                            id = 100000001
                            name = 'TEST-AGENT001'
                            ip = '192.0.2.1'
                            last_connect = 1776178951
                            last_scanned = 1776178951
                        }
                    )
                }
            }

            if ($Uri -like '*scanners/1/agent-groups') {
                return [pscustomobject]@{
                    groups = @(
                        [pscustomobject]@{ id = 900001; name = 'Test-Servers' }
                    )
                }
            }

            if ($Uri -like '*scanners/1/agent-groups/900001/agents`?limit=5000&offset=0') {
                return [pscustomobject]@{
                    agents = @(
                        [pscustomobject]@{ id = 101 },
                        [pscustomobject]@{ id = 102 },
                        [pscustomobject]@{ id = 103 },
                        [pscustomobject]@{ id = 104 },
                        [pscustomobject]@{ id = 105 }
                    )
                }
            }

            if ($Uri -like '*scanners/1/agent-groups/900001/agents`?limit=5&offset=0') {
                return [pscustomobject]@{
                    agents = @(
                        [pscustomobject]@{ id = 101 },
                        [pscustomobject]@{ id = 102 },
                        [pscustomobject]@{ id = 103 },
                        [pscustomobject]@{ id = 104 },
                        [pscustomobject]@{ id = 105 }
                    )
                }
            }

            if ($Uri -like '*scanners/1/agent-groups/900001/agents`?limit=5&offset=5') {
                return [pscustomobject]@{
                    agents = @(
                        [pscustomobject]@{ id = 100000001 }
                    )
                }
            }

            throw (New-TioHttpException -StatusCode 500 -Message "Unexpected URI: $Uri")
        }

        $null = & $scriptPath -ScannerId 1 -OutDir $outDir -Mode Fast -AccessKey 'ak' -SecretKey 'sk' -Limit 5

        $csvPath = Join-Path $outDir 'TioAgentInventory_Fast_Scanner1.csv'
        Test-Path -LiteralPath $csvPath | Should -BeTrue

        $row = Import-Csv -LiteralPath $csvPath | Where-Object { $_.Hostname -eq 'TEST-AGENT001' } | Select-Object -First 1
        $row | Should -Not -BeNullOrEmpty
        $row.Groups | Should -Be 'Test-Servers'
    }
}
