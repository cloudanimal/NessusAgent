function Get-NessusAgentStatus {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe'
    )

    $result = Invoke-NessusCli -Path $Path -ArgumentList @('agent', 'status')
    $rawLines = $result.Output
    $exitCode = $result.ExitCode

    $hasOutput = @($rawLines | Where-Object { $_ -and $_.ToString().Trim() }).Count -gt 0
    if ($exitCode -ne 0 -and -not $hasOutput) {
        throw "nessuscli.exe agent status failed with exit code $exitCode and produced no output."
    }

    $data = [ordered]@{
        Running = $null
        LinkedTo = $null
        LinkStatus = $null
        Proxy = $null
        PluginSet = $null
        Scanning = $null
        ScansRunToday = $null
        LastScanned = $null
        LastScannedText = $null
        LastConnect = $null
        LastConnectText = $null
        LastConnectionAttempt = $null
        LastConnectionAttemptText = $null
        JobsPending = $null
        AgentStatus = $null
        StatusExitCode = $exitCode
        RawOutput = ($rawLines -join [Environment]::NewLine)
    }

    foreach ($line in $rawLines) {
        $text = $line.ToString().Trim()
        if (-not $text) {
            continue
        }

        if ($text -eq 'Agent not linked to a server') {
            $data.LinkStatus = 'Not linked'
            continue
        }

        if ($text -match '^Agent is linked to\s+(?<target>.+)$') {
            $data.LinkedTo = $matches.target.Trim()
            $data.LinkStatus = 'Connected'
            continue
        }

        if ($text -match '^(?<count>\d+)\s+jobs pending$') {
            $data.JobsPending = [int]$matches.count
            continue
        }

        if ($text -notmatch '^(?<key>[^:]+):\s*(?<value>.*)$') {
            continue
        }

        $key = $matches.key.Trim()
        $value = $matches.value.Trim()

        switch ($key) {
            'Running' {
                $data.Running = $value
            }
            'Linked to' {
                $data.LinkedTo = $value
            }
            'Link status' {
                $data.LinkStatus = $value
            }
            'Proxy' {
                $data.Proxy = $value
            }
            'Plugin set' {
                $data.PluginSet = $value
            }
            'Scanning' {
                $data.Scanning = $value
            }
            'Scans run today' {
                if ($value -match '^\d+$') {
                    $data.ScansRunToday = [int]$value
                }
                else {
                    $data.ScansRunToday = $value
                }
            }
            'Last scanned' {
                $data.LastScannedText = $value
                $data.LastScanned = ConvertTo-NessusDateTime -Value $value
            }
            'Last connect' {
                $data.LastConnectText = $value
                $data.LastConnect = ConvertTo-NessusDateTime -Value $value
            }
            'Last connection attempt' {
                $data.LastConnectionAttemptText = $value
                $data.LastConnectionAttempt = ConvertTo-NessusDateTime -Value $value
            }
        }
    }

    $normalizedLinkStatus = if ($data.LinkStatus) { $data.LinkStatus.ToString().Trim().ToLowerInvariant() } else { '' }
    $normalizedRunning = if ($data.Running) { $data.Running.ToString().Trim().ToLowerInvariant() } else { '' }

    $data.AgentStatus = switch ($true) {
        ($normalizedLinkStatus -eq 'connected' -or $normalizedLinkStatus -like 'connected *') {
            'Connected'
            break
        }
        ($normalizedLinkStatus -in @('not linked', 'unlinked') -or $normalizedLinkStatus -like 'not linked*') {
            'Unlinked'
            break
        }
        ($data.LinkedTo -and $normalizedRunning -eq 'yes') {
            'Degraded'
            break
        }
        ($data.LinkedTo -or $data.LinkStatus -or $data.Running) {
            'Degraded'
            break
        }
        default {
            'Unlinked'
        }
    }

    [pscustomobject]$data
}
