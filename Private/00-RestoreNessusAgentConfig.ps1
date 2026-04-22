$moduleRoot = Split-Path -Parent $PSScriptRoot
$localConfigPath = Join-Path -Path $moduleRoot -ChildPath 'Restore-NessusAgent.local.psd1'

function ConvertFrom-RestoreNessusSecureString {
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

$defaultWorkingDirectory = if ($env:OS -eq 'Windows_NT') { 'C:\Temp' } else { [System.IO.Path]::GetTempPath().TrimEnd('\', '/') }
$defaultLogPath = if ($defaultWorkingDirectory -match '^[A-Za-z]:\\') {
    '{0}\agent_install.log' -f $defaultWorkingDirectory.TrimEnd('\')
}
else {
    Join-Path -Path $defaultWorkingDirectory -ChildPath 'agent_install.log'
}

$defaultSecretStorePath = if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Restore-NessusAgent\secrets.clixml'
}
else {
    Join-Path -Path $defaultWorkingDirectory -ChildPath 'Restore-NessusAgent\secrets.clixml'
}

$script:RestoreNessusAgentConfig = [ordered]@{
    AgentDetailsEndpoint = 'https://www.tenable.com/downloads/api/v1/public/pages/nessus-agents'
    AgentDownloadUrlFormat = 'https://www.tenable.com/downloads/api/v1/public/pages/nessus-agents/downloads/{0}/download?i_agree_to_tenable_license_agreement=true'
    TenableEulaUrl = 'https://cloud.tenable.com/print-eula.html'
    NessusServer = 'sensor.cloud.tenable.com:443'
    WorkingDirectory = $defaultWorkingDirectory
    LogPath = $defaultLogPath
    NessusKey = $null
    CustomerUuid = $null
    TenableAccessKey = $null
    TenableSecretKey = $null
    SecretStorePath = $defaultSecretStorePath
    InstallerSearchPaths = @(
        '\\fs\share\vmops'
    )
    LocalConfigPath = $localConfigPath
}

if (Test-Path -LiteralPath $localConfigPath) {
    $localConfig = Import-PowerShellDataFile -LiteralPath $localConfigPath

    foreach ($property in $localConfig.GetEnumerator()) {
        $script:RestoreNessusAgentConfig[$property.Key] = $property.Value
    }
}

$secretStorePath = $script:RestoreNessusAgentConfig['SecretStorePath']
if (-not [string]::IsNullOrWhiteSpace($secretStorePath) -and (Test-Path -LiteralPath $secretStorePath)) {
    $secretStore = Import-Clixml -LiteralPath $secretStorePath

    if ($secretStore.PSObject.Properties['NessusKey']) {
        $secretNessusKey = $secretStore.NessusKey
        if ($secretNessusKey -is [System.Security.SecureString]) {
            $script:RestoreNessusAgentConfig['NessusKey'] = ConvertFrom-RestoreNessusSecureString -Value $secretNessusKey
        }
        elseif ($secretNessusKey -is [string] -and -not [string]::IsNullOrWhiteSpace($secretNessusKey)) {
            $script:RestoreNessusAgentConfig['NessusKey'] = $secretNessusKey
        }
    }

    if ($secretStore.PSObject.Properties['CustomerUuid']) {
        $secretCustomerUuid = $secretStore.CustomerUuid
        if ($secretCustomerUuid -is [System.Security.SecureString]) {
            $script:RestoreNessusAgentConfig['CustomerUuid'] = ConvertFrom-RestoreNessusSecureString -Value $secretCustomerUuid
        }
        elseif ($secretCustomerUuid -is [string] -and -not [string]::IsNullOrWhiteSpace($secretCustomerUuid)) {
            $script:RestoreNessusAgentConfig['CustomerUuid'] = $secretCustomerUuid
        }
    }

    if ($secretStore.PSObject.Properties['TenableAccessKey']) {
        $secretTenableAccessKey = $secretStore.TenableAccessKey
        if ($secretTenableAccessKey -is [System.Security.SecureString]) {
            $script:RestoreNessusAgentConfig['TenableAccessKey'] = ConvertFrom-RestoreNessusSecureString -Value $secretTenableAccessKey
        }
        elseif ($secretTenableAccessKey -is [string] -and -not [string]::IsNullOrWhiteSpace($secretTenableAccessKey)) {
            $script:RestoreNessusAgentConfig['TenableAccessKey'] = $secretTenableAccessKey
        }
    }

    if ($secretStore.PSObject.Properties['TenableSecretKey']) {
        $secretTenableSecretKey = $secretStore.TenableSecretKey
        if ($secretTenableSecretKey -is [System.Security.SecureString]) {
            $script:RestoreNessusAgentConfig['TenableSecretKey'] = ConvertFrom-RestoreNessusSecureString -Value $secretTenableSecretKey
        }
        elseif ($secretTenableSecretKey -is [string] -and -not [string]::IsNullOrWhiteSpace($secretTenableSecretKey)) {
            $script:RestoreNessusAgentConfig['TenableSecretKey'] = $secretTenableSecretKey
        }
    }
}

$environmentOverrides = [ordered]@{
    NessusServer = $env:REPAIR_NESSUS_AGENT_SERVER
    WorkingDirectory = $env:REPAIR_NESSUS_AGENT_WORKDIR
    LogPath = $env:REPAIR_NESSUS_AGENT_LOG_PATH
    NessusKey = $env:REPAIR_NESSUS_AGENT_KEY
    CustomerUuid = $env:REPAIR_NESSUS_AGENT_CUSTOMER_UUID
    TenableAccessKey = if (-not [string]::IsNullOrWhiteSpace($env:TENABLE_ACCESS_KEY)) { $env:TENABLE_ACCESS_KEY } else { $env:REPAIR_NESSUS_TENABLE_ACCESS_KEY }
    TenableSecretKey = if (-not [string]::IsNullOrWhiteSpace($env:TENABLE_SECRET_KEY)) { $env:TENABLE_SECRET_KEY } else { $env:REPAIR_NESSUS_TENABLE_SECRET_KEY }
}

foreach ($override in $environmentOverrides.GetEnumerator()) {
    if (-not [string]::IsNullOrWhiteSpace($override.Value)) {
        $script:RestoreNessusAgentConfig[$override.Key] = $override.Value
    }
}

if (-not [string]::IsNullOrWhiteSpace($env:REPAIR_NESSUS_AGENT_INSTALLER_SEARCH_PATHS)) {
    $script:RestoreNessusAgentConfig['InstallerSearchPaths'] = @(
        $env:REPAIR_NESSUS_AGENT_INSTALLER_SEARCH_PATHS.Split([System.IO.Path]::PathSeparator) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}
