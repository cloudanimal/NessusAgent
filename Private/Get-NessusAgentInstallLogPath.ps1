function Get-NessusAgentInstallLogPath {
    [CmdletBinding()]
    param()

    $configuredPath = Get-NessusAgentConfigurationValue -Name 'LogPath'
    if (-not [string]::IsNullOrWhiteSpace($configuredPath)) {
        return [string]$configuredPath
    }

    Join-Path -Path (Get-NessusAgentWorkingPath) -ChildPath 'agent_install.log'
}
