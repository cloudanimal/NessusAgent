function Get-NessusAgentHealth {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [psobject]$InputObject,

        [Parameter()]
        [string]$Path = 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe',

        [Parameter()]
        [string]$ExpectedHost = (Get-NessusAgentDefaultLinkTarget).Host,

        [Parameter()]
        [int]$MaxHoursSinceConnect = 24,

        [Parameter()]
        [int]$MaxHoursSinceConnectionAttempt = 24,

        [Parameter()]
        [int]$MaxHoursSinceScan = 168
    )

    process {
        $status = if ($PSBoundParameters.ContainsKey('InputObject')) {
            $InputObject
        }
        else {
            Get-NessusAgentStatus -Path $Path
        }

        $linkTarget = Get-NessusAgentLinkTarget -LinkedTo $status.LinkedTo

        $findings = New-Object System.Collections.Generic.List[object]

        if (-not $status.Running) {
            $findings.Add([pscustomobject]@{
                Property = 'Running'
                Severity = 'Error'
                Value = $status.Running
                Message = 'Running status was not present in the Nessus Agent output.'
            })
        }
        elseif ($status.Running.ToString().Trim().ToLowerInvariant() -ne 'yes') {
            $findings.Add([pscustomobject]@{
                Property = 'Running'
                Severity = 'Error'
                Value = $status.Running
                Message = 'Nessus Agent is not reporting a running state.'
            })
        }

        if (-not $status.LinkedTo) {
            $findings.Add([pscustomobject]@{
                Property = 'LinkedTo'
                Severity = 'Error'
                Value = $status.LinkedTo
                Message = 'Agent is not linked to a manager or sensor endpoint.'
            })
        }
        elseif (-not [string]::IsNullOrWhiteSpace($ExpectedHost) -and $linkTarget.Host) {
            $normalizedActualHost = $linkTarget.Host.ToString().Trim().ToLowerInvariant()
            $normalizedExpectedHost = $ExpectedHost.Trim().ToLowerInvariant()

            if ($normalizedActualHost -ne $normalizedExpectedHost) {
                $findings.Add([pscustomobject]@{
                    Property = 'LinkedTo'
                    Severity = 'Error'
                    Value = $status.LinkedTo
                    Message = "Agent is linked to '$($linkTarget.Host)' instead of '$ExpectedHost'."
                })
            }
        }

        if (-not $status.LinkStatus) {
            $findings.Add([pscustomobject]@{
                Property = 'LinkStatus'
                Severity = 'Warning'
                Value = $status.LinkStatus
                Message = 'Link status was not present in the Nessus Agent output.'
            })
        }
        else {
            switch ($status.LinkStatus.ToString().Trim().ToLowerInvariant()) {
                'connected' {
                    break
                }
                'not linked' {
                    $findings.Add([pscustomobject]@{
                        Property = 'LinkStatus'
                        Severity = 'Error'
                        Value = $status.LinkStatus
                        Message = 'Agent is not linked.'
                    })
                }
                'unlinked' {
                    $findings.Add([pscustomobject]@{
                        Property = 'LinkStatus'
                        Severity = 'Error'
                        Value = $status.LinkStatus
                        Message = 'Agent is unlinked.'
                    })
                }
                default {
                    $findings.Add([pscustomobject]@{
                        Property = 'LinkStatus'
                        Severity = 'Warning'
                        Value = $status.LinkStatus
                        Message = 'Agent link status is not connected.'
                    })
                }
            }
        }

        if ($null -ne $status.JobsPending -and $status.JobsPending -gt 0) {
            $findings.Add([pscustomobject]@{
                Property = 'JobsPending'
                Severity = 'Info'
                Value = $status.JobsPending
                Message = 'Agent has pending jobs.'
            })
        }

        if ($status.LastConnect -is [datetime]) {
            $hoursSinceConnect = ((Get-Date) - $status.LastConnect).TotalHours
            if ($hoursSinceConnect -gt $MaxHoursSinceConnect) {
                $findings.Add([pscustomobject]@{
                    Property = 'LastConnect'
                    Severity = 'Warning'
                    Value = $status.LastConnect
                    Message = "Last successful connect is older than $MaxHoursSinceConnect hours."
                })
            }
        }
        elseif ($status.LastConnectText) {
            $findings.Add([pscustomobject]@{
                Property = 'LastConnect'
                Severity = 'Warning'
                Value = $status.LastConnectText
                Message = 'Last connect value was present but could not be parsed as a datetime.'
            })
        }

        if ($status.LastConnectionAttempt -is [datetime]) {
            $hoursSinceAttempt = ((Get-Date) - $status.LastConnectionAttempt).TotalHours
            if ($hoursSinceAttempt -gt $MaxHoursSinceConnectionAttempt) {
                $findings.Add([pscustomobject]@{
                    Property = 'LastConnectionAttempt'
                    Severity = 'Warning'
                    Value = $status.LastConnectionAttempt
                    Message = "Last connection attempt is older than $MaxHoursSinceConnectionAttempt hours."
                })
            }
        }
        elseif ($status.LastConnectionAttemptText) {
            $findings.Add([pscustomobject]@{
                Property = 'LastConnectionAttempt'
                Severity = 'Warning'
                Value = $status.LastConnectionAttemptText
                Message = 'Last connection attempt value was present but could not be parsed as a datetime.'
            })
        }

        if ($status.LastScanned -is [datetime]) {
            $hoursSinceScan = ((Get-Date) - $status.LastScanned).TotalHours
            if ($hoursSinceScan -gt $MaxHoursSinceScan) {
                $findings.Add([pscustomobject]@{
                    Property = 'LastScanned'
                    Severity = 'Warning'
                    Value = $status.LastScanned
                    Message = "Last scan is older than $MaxHoursSinceScan hours."
                })
            }
        }
        elseif ($status.LastScannedText) {
            $findings.Add([pscustomobject]@{
                Property = 'LastScanned'
                Severity = 'Warning'
                Value = $status.LastScannedText
                Message = 'Last scanned value was present but could not be parsed as a datetime.'
            })
        }

        $isHealthy = $true
        $overallStatus = 'OK'
        foreach ($finding in $findings) {
            if ($finding.Severity -in @('Error', 'Warning')) {
                $isHealthy = $false
            }

            if ($finding.Severity -eq 'Error') {
                $overallStatus = 'Critical'
            }
            elseif ($finding.Severity -eq 'Warning' -and $overallStatus -ne 'Critical') {
                $overallStatus = 'Warning'
            }
        }

        $exitCode = switch ($overallStatus) {
            'OK' { 0 }
            'Warning' { 1 }
            'Critical' { 2 }
            default { 3 }
        }

        $summary = if ($findings.Count -eq 0) {
            "OK: Nessus Agent status is healthy. AgentStatus=$($status.AgentStatus)"
        }
        else {
            $messages = @($findings | ForEach-Object { $_.Message })
            "{0}: {1}" -f $overallStatus.ToUpperInvariant(), ($messages -join '; ')
        }

        $findingsArray = [object[]]$findings.ToArray()

        [pscustomobject]@{
            AgentStatus = $status.AgentStatus
            ExpectedHost = $ExpectedHost
            LinkedHost = $linkTarget.Host
            LinkedPort = $linkTarget.Port
            IsHealthy = $isHealthy
            OverallStatus = $overallStatus
            ExitCode = $exitCode
            Summary = $summary
            FindingCount = $findings.Count
            Findings = $findingsArray
            Status = $status
        }
    }
}
