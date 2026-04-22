function ConvertFrom-NessusAgentSecureString {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Security.SecureString]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function ConvertTo-NessusAgentSecureString {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Security.SecureString]) {
        return $Value
    }

    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $null
        }

        return (ConvertTo-SecureString -String $Value -AsPlainText -Force)
    }

    throw "Unsupported secret value type: $($Value.GetType().FullName)"
}

function Set-NessusAgentSecret {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [System.Security.SecureString]$NessusKey,

        [Parameter()]
        [System.Security.SecureString]$CustomerUuid,

        [Parameter()]
        [System.Security.SecureString]$TenableAccessKey,

        [Parameter()]
        [System.Security.SecureString]$TenableSecretKey,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [switch]$PassThru
    )

    if (
        -not $PSBoundParameters.ContainsKey('NessusKey') -and
        -not $PSBoundParameters.ContainsKey('CustomerUuid') -and
        -not $PSBoundParameters.ContainsKey('TenableAccessKey') -and
        -not $PSBoundParameters.ContainsKey('TenableSecretKey')
    ) {
        throw 'Specify at least one secret: -NessusKey, -CustomerUuid, -TenableAccessKey, or -TenableSecretKey.'
    }

    $secretStorePath = if ([string]::IsNullOrWhiteSpace($Path)) {
        Get-NessusAgentConfigurationValue -Name 'SecretStorePath'
    }
    else {
        $Path
    }

    if ([string]::IsNullOrWhiteSpace($secretStorePath)) {
        throw 'Secret store path is not configured.'
    }

    $existingStore = $null
    if (Test-Path -LiteralPath $secretStorePath) {
        $existingStore = Import-Clixml -LiteralPath $secretStorePath
    }

    $storeObject = [ordered]@{
        SchemaVersion = 1
        UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        NessusKey = $null
        CustomerUuid = $null
        TenableAccessKey = $null
        TenableSecretKey = $null
    }

    if ($null -ne $existingStore) {
        if ($existingStore.PSObject.Properties['NessusKey']) {
            $storeObject['NessusKey'] = ConvertTo-NessusAgentSecureString -Value $existingStore.NessusKey
        }

        if ($existingStore.PSObject.Properties['CustomerUuid']) {
            $storeObject['CustomerUuid'] = ConvertTo-NessusAgentSecureString -Value $existingStore.CustomerUuid
        }

        if ($existingStore.PSObject.Properties['TenableAccessKey']) {
            $storeObject['TenableAccessKey'] = ConvertTo-NessusAgentSecureString -Value $existingStore.TenableAccessKey
        }

        if ($existingStore.PSObject.Properties['TenableSecretKey']) {
            $storeObject['TenableSecretKey'] = ConvertTo-NessusAgentSecureString -Value $existingStore.TenableSecretKey
        }
    }

    if ($PSBoundParameters.ContainsKey('NessusKey')) {
        $storeObject['NessusKey'] = ConvertTo-NessusAgentSecureString -Value $NessusKey
    }

    if ($PSBoundParameters.ContainsKey('CustomerUuid')) {
        $storeObject['CustomerUuid'] = ConvertTo-NessusAgentSecureString -Value $CustomerUuid
    }

    if ($PSBoundParameters.ContainsKey('TenableAccessKey')) {
        $storeObject['TenableAccessKey'] = ConvertTo-NessusAgentSecureString -Value $TenableAccessKey
    }

    if ($PSBoundParameters.ContainsKey('TenableSecretKey')) {
        $storeObject['TenableSecretKey'] = ConvertTo-NessusAgentSecureString -Value $TenableSecretKey
    }

    $targetDirectory = Split-Path -Parent $secretStorePath
    if (-not [string]::IsNullOrWhiteSpace($targetDirectory) -and -not (Test-Path -LiteralPath $targetDirectory)) {
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    }

    if ($PSCmdlet.ShouldProcess($secretStorePath, 'Write encrypted Nessus agent secrets')) {
        [pscustomobject]$storeObject | Export-Clixml -LiteralPath $secretStorePath -Force

        if ($PSBoundParameters.ContainsKey('NessusKey')) {
            $script:RestoreNessusAgentConfig['NessusKey'] = ConvertFrom-NessusAgentSecureString -Value $NessusKey
        }

        if ($PSBoundParameters.ContainsKey('CustomerUuid')) {
            $script:RestoreNessusAgentConfig['CustomerUuid'] = ConvertFrom-NessusAgentSecureString -Value $CustomerUuid
        }

        if ($PSBoundParameters.ContainsKey('TenableAccessKey')) {
            $script:RestoreNessusAgentConfig['TenableAccessKey'] = ConvertFrom-NessusAgentSecureString -Value $TenableAccessKey
        }

        if ($PSBoundParameters.ContainsKey('TenableSecretKey')) {
            $script:RestoreNessusAgentConfig['TenableSecretKey'] = ConvertFrom-NessusAgentSecureString -Value $TenableSecretKey
        }
    }

    $result = [pscustomobject]@{
        SecretStorePath = $secretStorePath
        HasNessusKey = $null -ne $storeObject['NessusKey']
        HasCustomerUuid = $null -ne $storeObject['CustomerUuid']
        HasTenableAccessKey = $null -ne $storeObject['TenableAccessKey']
        HasTenableSecretKey = $null -ne $storeObject['TenableSecretKey']
    }

    if ($PassThru) {
        return $result
    }

    $result
}
