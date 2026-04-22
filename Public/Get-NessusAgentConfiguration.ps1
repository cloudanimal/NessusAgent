function Get-NessusAgentConfiguration {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$IncludeSecrets
    )

    $nessusKey = Get-NessusAgentConfigurationValue -Name 'NessusKey'
    $customerUuid = Get-NessusAgentConfigurationValue -Name 'CustomerUuid'
    $tenableAccessKey = Get-NessusAgentConfigurationValue -Name 'TenableAccessKey'
    $tenableSecretKey = Get-NessusAgentConfigurationValue -Name 'TenableSecretKey'
    $secretStorePath = Get-NessusAgentConfigurationValue -Name 'SecretStorePath'

    [pscustomobject]@{
        AgentDetailsEndpoint = Get-NessusAgentConfigurationValue -Name 'AgentDetailsEndpoint'
        AgentDownloadUrlFormat = Get-NessusAgentConfigurationValue -Name 'AgentDownloadUrlFormat'
        TenableEulaUrl = Get-NessusAgentConfigurationValue -Name 'TenableEulaUrl'
        NessusServer = Get-NessusAgentConfigurationValue -Name 'NessusServer'
        WorkingDirectory = Get-NessusAgentConfigurationValue -Name 'WorkingDirectory'
        LogPath = Get-NessusAgentConfigurationValue -Name 'LogPath'
        InstallerSearchPaths = @(Get-NessusAgentConfigurationValue -Name 'InstallerSearchPaths')
        LocalConfigPath = Get-NessusAgentConfigurationValue -Name 'LocalConfigPath'
        SecretStorePath = $secretStorePath
        SecretStorePresent = -not [string]::IsNullOrWhiteSpace($secretStorePath) -and (Test-Path -LiteralPath $secretStorePath)
        HasNessusKey = -not [string]::IsNullOrWhiteSpace($nessusKey)
        HasCustomerUuid = -not [string]::IsNullOrWhiteSpace($customerUuid)
        HasTenableAccessKey = -not [string]::IsNullOrWhiteSpace($tenableAccessKey)
        HasTenableSecretKey = -not [string]::IsNullOrWhiteSpace($tenableSecretKey)
        NessusKey = if ($IncludeSecrets) { $nessusKey } else { $null }
        CustomerUuid = if ($IncludeSecrets) { $customerUuid } else { $null }
        TenableAccessKey = if ($IncludeSecrets) { $tenableAccessKey } else { $null }
        TenableSecretKey = if ($IncludeSecrets) { $tenableSecretKey } else { $null }
    }
}
