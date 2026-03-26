function Get-NessusAgentWorkingPath {
    [CmdletBinding()]
    param()

    $configuredPath = $null
    if ($script:RestoreNessusAgentConfig -and $script:RestoreNessusAgentConfig.WorkingDirectory) {
        $configuredPath = [string]$script:RestoreNessusAgentConfig.WorkingDirectory
    }

    $isWindowsPlatform = $env:OS -eq 'Windows_NT'
    if ($isWindowsPlatform) {
        if (-not [string]::IsNullOrWhiteSpace($configuredPath)) {
            return $configuredPath
        }

        return 'C:\Temp'
    }

    if (-not [string]::IsNullOrWhiteSpace($configuredPath) -and $configuredPath -notmatch '^[A-Za-z]:\\') {
        return $configuredPath
    }

    [System.IO.Path]::GetTempPath().TrimEnd('\', '/')
}
