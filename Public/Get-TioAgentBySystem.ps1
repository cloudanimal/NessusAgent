function Get-TioAgentBySystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('ComputerName', 'HostName', 'Name')]
        [string[]]$System,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ScannerId = '1',

        [Parameter()]
        [ValidateRange(1, 5000)]
        [int]$Limit = 5000,

        [Parameter()]
        [string]$AccessKey = $env:TENABLE_ACCESS_KEY,

        [Parameter()]
        [string]$SecretKey = $env:TENABLE_SECRET_KEY,

        [Parameter()]
        [switch]$IncludeDetails
    )

    begin {
        Set-StrictMode -Version Latest

        function ConvertFrom-TioEpochSeconds {
            param([Parameter()][AllowNull()][object]$Value)

            if ($null -eq $Value) {
                return $null
            }

            $text = $Value.ToString().Trim()
            if ([string]::IsNullOrWhiteSpace($text)) {
                return $null
            }

            $epoch = 0L
            if (-not [long]::TryParse($text, [ref]$epoch)) {
                return $null
            }

            if ($epoch -gt 9999999999) {
                $epoch = [long][math]::Floor($epoch / 1000)
            }

            try {
                return [DateTimeOffset]::FromUnixTimeSeconds($epoch).UtcDateTime
            }
            catch {
                return $null
            }
        }

        function Get-TioAgentPropertyValue {
            param(
                [Parameter(Mandatory)]
                [object]$Agent,

                [Parameter(Mandatory)]
                [string]$Name
            )

            if ($Agent.PSObject.Properties[$Name]) {
                return $Agent.PSObject.Properties[$Name].Value
            }

            return $null
        }

        function Invoke-TioAgentRequest {
            param(
                [Parameter(Mandatory)]
                [string]$Uri,

                [Parameter(Mandatory)]
                [hashtable]$Headers
            )

            try {
                Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -Verbose:$false
            }
            catch {
                $status = $null
                try {
                    $status = $_.Exception.Response.StatusCode.value__
                }
                catch {
                }

                if ($status) {
                    throw "Tenable API request failed ($status): $Uri"
                }

                throw "Tenable API request failed: $Uri"
            }
        }

        function Find-TioAgentBySystemName {
            param(
                [Parameter(Mandatory)]
                [string]$SystemName,

                [Parameter(Mandatory)]
                [string]$Scanner,

                [Parameter(Mandatory)]
                [int]$PageSize,

                [Parameter(Mandatory)]
                [hashtable]$Headers
            )

            $offset = 0
            while ($true) {
                $uri = "https://cloud.tenable.com/scanners/$Scanner/agents?limit=$PageSize&offset=$offset"
                $resp = Invoke-TioAgentRequest -Uri $uri -Headers $Headers
                $chunk = @($resp.agents)

                $match = $chunk | Where-Object { $_.name -ieq $SystemName } | Select-Object -First 1
                if ($match) {
                    return $match
                }

                if ($chunk.Count -lt $PageSize) {
                    break
                }

                $offset += $PageSize
            }

            return $null
        }

        if ([string]::IsNullOrWhiteSpace($AccessKey) -or [string]::IsNullOrWhiteSpace($SecretKey)) {
            $config = Get-NessusAgentConfiguration -IncludeSecrets
            if ([string]::IsNullOrWhiteSpace($AccessKey) -and $config.PSObject.Properties['TenableAccessKey']) {
                $AccessKey = [string]$config.TenableAccessKey
            }
            if ([string]::IsNullOrWhiteSpace($SecretKey) -and $config.PSObject.Properties['TenableSecretKey']) {
                $SecretKey = [string]$config.TenableSecretKey
            }
        }

        if ([string]::IsNullOrWhiteSpace($AccessKey) -or [string]::IsNullOrWhiteSpace($SecretKey)) {
            throw 'Missing Tenable API keys. Provide -AccessKey/-SecretKey, set TENABLE_ACCESS_KEY/TENABLE_SECRET_KEY, or store keys with Set-NessusAgentSecret.'
        }

        $headers = @{
            Accept = 'application/json'
            'X-ApiKeys' = "accessKey=$AccessKey; secretKey=$SecretKey"
        }
    }

    process {
        foreach ($systemName in $System) {
            $trimmedName = $systemName.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmedName)) {
                continue
            }

            try {
                $agent = Find-TioAgentBySystemName -SystemName $trimmedName -Scanner $ScannerId -PageSize $Limit -Headers $headers

                if (-not $agent) {
                    [pscustomobject]@{
                        SystemName = $trimmedName
                        Found = $false
                        ScannerId = $ScannerId
                        AgentId = $null
                        Status = $null
                        LinkedOn = $null
                        LastConnectUtc = $null
                        LastScannedUtc = $null
                        LinkStatus = $null
                        LinkedTo = $null
                        Ip = $null
                        Platform = $null
                        Distro = $null
                        Error = $null
                    }

                    continue
                }

                if ($IncludeDetails) {
                    $detailUri = "https://cloud.tenable.com/scanners/$ScannerId/agents/$($agent.id)"
                    $detail = Invoke-TioAgentRequest -Uri $detailUri -Headers $headers
                    if ($detail) {
                        foreach ($p in $detail.PSObject.Properties) {
                            $agent | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
                        }
                    }
                }

                [pscustomobject]@{
                    SystemName = $trimmedName
                    Found = $true
                    ScannerId = $ScannerId
                    AgentId = Get-TioAgentPropertyValue -Agent $agent -Name 'id'
                    Status = Get-TioAgentPropertyValue -Agent $agent -Name 'status'
                    LinkedOn = ConvertFrom-TioEpochSeconds -Value (Get-TioAgentPropertyValue -Agent $agent -Name 'linked_on')
                    LastConnectUtc = ConvertFrom-TioEpochSeconds -Value (Get-TioAgentPropertyValue -Agent $agent -Name 'last_connect')
                    LastScannedUtc = ConvertFrom-TioEpochSeconds -Value (Get-TioAgentPropertyValue -Agent $agent -Name 'last_scanned')
                    LinkStatus = Get-TioAgentPropertyValue -Agent $agent -Name 'link_status'
                    LinkedTo = Get-TioAgentPropertyValue -Agent $agent -Name 'linked_to'
                    Ip = Get-TioAgentPropertyValue -Agent $agent -Name 'ip'
                    Platform = Get-TioAgentPropertyValue -Agent $agent -Name 'platform'
                    Distro = Get-TioAgentPropertyValue -Agent $agent -Name 'distro'
                    Error = $null
                }
            }
            catch {
                [pscustomobject]@{
                    SystemName = $trimmedName
                    Found = $false
                    ScannerId = $ScannerId
                    AgentId = $null
                    Status = $null
                    LinkedOn = $null
                    LastConnectUtc = $null
                    LastScannedUtc = $null
                    LinkStatus = $null
                    LinkedTo = $null
                    Ip = $null
                    Platform = $null
                    Distro = $null
                    Error = $_.Exception.Message
                }
            }
        }
    }
}
