function Get-NessusAgentDefaultLinkTarget {
    [CmdletBinding()]
    param()

    $serverSetting = $null
    if ($script:RestoreNessusAgentConfig -and $script:RestoreNessusAgentConfig.NessusServer) {
        $serverSetting = [string]$script:RestoreNessusAgentConfig.NessusServer
    }

    if ([string]::IsNullOrWhiteSpace($serverSetting)) {
        $serverSetting = 'sensor.cloud.tenable.com:443'
    }

    $target = Get-NessusAgentLinkTarget -LinkedTo $serverSetting
    [pscustomobject]@{
        Host = if ($target.Host) { $target.Host } else { 'sensor.cloud.tenable.com' }
        Port = if ($target.Port) { $target.Port } else { 443 }
        Raw = $serverSetting
    }
}
