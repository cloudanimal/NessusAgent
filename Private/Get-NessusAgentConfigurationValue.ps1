function Get-NessusAgentConfigurationValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not $script:RestoreNessusAgentConfig) {
        return $null
    }

    if (-not $script:RestoreNessusAgentConfig.Contains($Name)) {
        return $null
    }

    $script:RestoreNessusAgentConfig[$Name]
}
