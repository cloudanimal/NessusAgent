function Get-NessusAgentConfiguration {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$IncludeSecrets
    )

    $nessusKey = Get-NessusAgentConfigurationValue -Name 'NessusKey'
    $customerUuid = Get-NessusAgentConfigurationValue -Name 'CustomerUuid'

    [pscustomobject]@{
        AgentDetailsEndpoint = Get-NessusAgentConfigurationValue -Name 'AgentDetailsEndpoint'
        AgentDownloadUrlFormat = Get-NessusAgentConfigurationValue -Name 'AgentDownloadUrlFormat'
        TenableEulaUrl = Get-NessusAgentConfigurationValue -Name 'TenableEulaUrl'
        NessusServer = Get-NessusAgentConfigurationValue -Name 'NessusServer'
        WorkingDirectory = Get-NessusAgentConfigurationValue -Name 'WorkingDirectory'
        LogPath = Get-NessusAgentConfigurationValue -Name 'LogPath'
        InstallerSearchPaths = @(Get-NessusAgentConfigurationValue -Name 'InstallerSearchPaths')
        LocalConfigPath = Get-NessusAgentConfigurationValue -Name 'LocalConfigPath'
        HasNessusKey = -not [string]::IsNullOrWhiteSpace($nessusKey)
        HasCustomerUuid = -not [string]::IsNullOrWhiteSpace($customerUuid)
        NessusKey = if ($IncludeSecrets) { $nessusKey } else { $null }
        CustomerUuid = if ($IncludeSecrets) { $customerUuid } else { $null }
    }
}
