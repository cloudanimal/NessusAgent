function Get-NessusAgentLinkTarget {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [string]$LinkedTo
    )

    if ([string]::IsNullOrWhiteSpace($LinkedTo)) {
        return [pscustomobject]@{
            Host = $null
            Port = $null
            Raw = $LinkedTo
        }
    }

    $value = $LinkedTo.Trim()
    $linkHost = $value
    $port = $null

    if ($value -match '^(?<linkHost>.+):(?<port>\d+)$') {
        $linkHost = $matches.linkHost.Trim()
        $port = [int]$matches.port
    }

    [pscustomobject]@{
        Host = $linkHost
        Port = $port
        Raw = $value
    }
}
