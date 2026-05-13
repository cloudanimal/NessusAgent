function Get-TioAgentGroupBySystem {
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

        $requestedSystems = New-Object System.Collections.Generic.List[string]

        function Invoke-TioGroupRequest {
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

        function Get-TioGroups {
            param(
                [Parameter(Mandatory)]
                [string]$Scanner,

                [Parameter(Mandatory)]
                [hashtable]$Headers
            )

            $uri = "https://cloud.tenable.com/scanners/$Scanner/agent-groups"
            $resp = Invoke-TioGroupRequest -Uri $uri -Headers $Headers
            @($resp.groups)
        }

        function Get-TioGroupMembers {
            param(
                [Parameter(Mandatory)]
                [string]$Scanner,

                [Parameter(Mandatory)]
                [string]$GroupId,

                [Parameter(Mandatory)]
                [hashtable]$Headers,

                [Parameter(Mandatory)]
                [int]$PageSize
            )

            $offset = 0
            $members = New-Object System.Collections.Generic.List[object]

            while ($true) {
                $uri = "https://cloud.tenable.com/scanners/$Scanner/agent-groups/$GroupId/agents?limit=$PageSize&offset=$offset"
                $resp = Invoke-TioGroupRequest -Uri $uri -Headers $Headers
                $chunk = @($resp.agents)

                foreach ($m in $chunk) {
                    [void]$members.Add($m)
                }

                if ($chunk.Count -lt $PageSize) {
                    break
                }

                $offset += $PageSize
            }

            $members
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
        foreach ($name in $System) {
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                [void]$requestedSystems.Add($name.Trim())
            }
        }
    }

    end {
        if ($requestedSystems.Count -eq 0) {
            return
        }

        $groupsByAgentId = @{}
        $groups = Get-TioGroups -Scanner $ScannerId -Headers $headers

        foreach ($group in $groups) {
            if ($null -eq $group -or $null -eq $group.id) {
                continue
            }

            $members = Get-TioGroupMembers -Scanner $ScannerId -GroupId ([string]$group.id) -Headers $headers -PageSize $Limit
            foreach ($member in $members) {
                $agentId = [int]$member.id
                if (-not $groupsByAgentId.ContainsKey($agentId)) {
                    $groupsByAgentId[$agentId] = New-Object System.Collections.Generic.List[string]
                }

                [void]$groupsByAgentId[$agentId].Add([string]$group.name)
            }
        }

        $lookupResults = Get-TioAgentBySystem -System @($requestedSystems) -ScannerId $ScannerId -Limit $Limit -AccessKey $AccessKey -SecretKey $SecretKey -IncludeDetails:$IncludeDetails

        foreach ($result in $lookupResults) {
            $groupNames = @()
            if ($result.Found -and $null -ne $result.AgentId) {
                $agentId = [int]$result.AgentId
                if ($groupsByAgentId.ContainsKey($agentId)) {
                    $groupNames = @($groupsByAgentId[$agentId] | Sort-Object -Unique)
                }
            }

            [pscustomobject]@{
                SystemName = $result.SystemName
                Found = $result.Found
                ScannerId = $result.ScannerId
                AgentId = $result.AgentId
                Status = $result.Status
                LinkedOn = $result.LinkedOn
                LastConnectUtc = $result.LastConnectUtc
                LastScannedUtc = $result.LastScannedUtc
                LinkStatus = $result.LinkStatus
                LinkedTo = $result.LinkedTo
                Ip = $result.Ip
                Platform = $result.Platform
                Distro = $result.Distro
                GroupCount = $groupNames.Count
                Groups = if ($groupNames.Count -gt 0) { $groupNames -join ', ' } else { '' }
                GroupNames = $groupNames
                Error = $result.Error
            }
        }
    }
}
