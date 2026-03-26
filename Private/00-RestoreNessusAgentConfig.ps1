$moduleRoot = Split-Path -Parent $PSScriptRoot
$localConfigPath = Join-Path -Path $moduleRoot -ChildPath 'Restore-NessusAgent.local.psd1'

$defaultWorkingDirectory = if ($env:OS -eq 'Windows_NT') { 'C:\Temp' } else { [System.IO.Path]::GetTempPath().TrimEnd('\', '/') }

$script:RestoreNessusAgentConfig = [ordered]@{
    AgentDetailsEndpoint = 'https://www.tenable.com/downloads/api/v1/public/pages/nessus-agents'
    AgentDownloadUrlFormat = 'https://www.tenable.com/downloads/api/v1/public/pages/nessus-agents/downloads/{0}/download?i_agree_to_tenable_license_agreement=true'
    TenableEulaUrl = 'https://cloud.tenable.com/print-eula.html'
    NessusServer = 'sensor.cloud.tenable.com:443'
    WorkingDirectory = $defaultWorkingDirectory
    LogPath = (Join-Path -Path $defaultWorkingDirectory -ChildPath 'agent_install.log')
    NessusKey = $null
    CustomerUuid = $null
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

$environmentOverrides = [ordered]@{
    NessusServer = $env:REPAIR_NESSUS_AGENT_SERVER
    WorkingDirectory = $env:REPAIR_NESSUS_AGENT_WORKDIR
    LogPath = $env:REPAIR_NESSUS_AGENT_LOG_PATH
    NessusKey = $env:REPAIR_NESSUS_AGENT_KEY
    CustomerUuid = $env:REPAIR_NESSUS_AGENT_CUSTOMER_UUID
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
