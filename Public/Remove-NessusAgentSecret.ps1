function Remove-NessusAgentSecret {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [switch]$NessusKey,

        [Parameter()]
        [switch]$CustomerUuid,

        [Parameter()]
        [switch]$TenableAccessKey,

        [Parameter()]
        [switch]$TenableSecretKey,

        [Parameter()]
        [switch]$All,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [switch]$PassThru
    )

    $secretStorePath = if ([string]::IsNullOrWhiteSpace($Path)) {
        Get-NessusAgentConfigurationValue -Name 'SecretStorePath'
    }
    else {
        $Path
    }

    if ([string]::IsNullOrWhiteSpace($secretStorePath)) {
        throw 'Secret store path is not configured.'
    }

    if (
        -not $PSBoundParameters.ContainsKey('All') -and
        -not $PSBoundParameters.ContainsKey('NessusKey') -and
        -not $PSBoundParameters.ContainsKey('CustomerUuid') -and
        -not $PSBoundParameters.ContainsKey('TenableAccessKey') -and
        -not $PSBoundParameters.ContainsKey('TenableSecretKey')
    ) {
        $All = $true
    }

    if (-not (Test-Path -LiteralPath $secretStorePath)) {
        $result = [pscustomobject]@{
            SecretStorePath = $secretStorePath
            SecretStorePresent = $false
            HasNessusKey = -not [string]::IsNullOrWhiteSpace((Get-NessusAgentConfigurationValue -Name 'NessusKey'))
            HasCustomerUuid = -not [string]::IsNullOrWhiteSpace((Get-NessusAgentConfigurationValue -Name 'CustomerUuid'))
            HasTenableAccessKey = -not [string]::IsNullOrWhiteSpace((Get-NessusAgentConfigurationValue -Name 'TenableAccessKey'))
            HasTenableSecretKey = -not [string]::IsNullOrWhiteSpace((Get-NessusAgentConfigurationValue -Name 'TenableSecretKey'))
        }

        if ($PassThru) {
            return $result
        }

        $result
        return
    }

    if ($All) {
        if ($PSCmdlet.ShouldProcess($secretStorePath, 'Remove all encrypted Nessus agent secrets')) {
            Remove-Item -LiteralPath $secretStorePath -Force
            $script:RestoreNessusAgentConfig['NessusKey'] = $null
            $script:RestoreNessusAgentConfig['CustomerUuid'] = $null
            $script:RestoreNessusAgentConfig['TenableAccessKey'] = $null
            $script:RestoreNessusAgentConfig['TenableSecretKey'] = $null
        }
    }
    else {
        $existingStore = Import-Clixml -LiteralPath $secretStorePath

        if ($NessusKey -and $existingStore.PSObject.Properties['NessusKey']) {
            $existingStore.NessusKey = $null
            $script:RestoreNessusAgentConfig['NessusKey'] = $null
        }

        if ($CustomerUuid -and $existingStore.PSObject.Properties['CustomerUuid']) {
            $existingStore.CustomerUuid = $null
            $script:RestoreNessusAgentConfig['CustomerUuid'] = $null
        }

        if ($TenableAccessKey -and $existingStore.PSObject.Properties['TenableAccessKey']) {
            $existingStore.TenableAccessKey = $null
            $script:RestoreNessusAgentConfig['TenableAccessKey'] = $null
        }

        if ($TenableSecretKey -and $existingStore.PSObject.Properties['TenableSecretKey']) {
            $existingStore.TenableSecretKey = $null
            $script:RestoreNessusAgentConfig['TenableSecretKey'] = $null
        }

        $hasAnySecrets =
            ($null -ne $existingStore.NessusKey) -or
            ($null -ne $existingStore.CustomerUuid) -or
            ($null -ne $existingStore.TenableAccessKey) -or
            ($null -ne $existingStore.TenableSecretKey)

        if ($PSCmdlet.ShouldProcess($secretStorePath, 'Update encrypted Nessus agent secrets')) {
            if ($hasAnySecrets) {
                $existingStore.UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
                $existingStore | Export-Clixml -LiteralPath $secretStorePath -Force
            }
            else {
                Remove-Item -LiteralPath $secretStorePath -Force
            }
        }
    }

    $postResult = [pscustomobject]@{
        SecretStorePath = $secretStorePath
        SecretStorePresent = Test-Path -LiteralPath $secretStorePath
        HasNessusKey = -not [string]::IsNullOrWhiteSpace((Get-NessusAgentConfigurationValue -Name 'NessusKey'))
        HasCustomerUuid = -not [string]::IsNullOrWhiteSpace((Get-NessusAgentConfigurationValue -Name 'CustomerUuid'))
        HasTenableAccessKey = -not [string]::IsNullOrWhiteSpace((Get-NessusAgentConfigurationValue -Name 'TenableAccessKey'))
        HasTenableSecretKey = -not [string]::IsNullOrWhiteSpace((Get-NessusAgentConfigurationValue -Name 'TenableSecretKey'))
    }

    if ($PassThru) {
        return $postResult
    }

    $postResult
}
