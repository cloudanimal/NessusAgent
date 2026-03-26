function Install-NessusAgent {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter()]
        [string]$MsiPath,

        [Parameter()]
        [string]$DownloadPath = (Get-NessusAgentWorkingPath),

        [Parameter()]
        [ValidatePattern('\d+\.\d+\.\d+')]
        [string]$Version,

        [Parameter()]
        [string]$LogPath = (Get-NessusAgentInstallLogPath),

        [Parameter()]
        [switch]$AcceptEula
    )

    $isWindowsPlatform = $env:OS -eq 'Windows_NT'
    $isSimulation = [bool]$WhatIfPreference

    if (-not $PSBoundParameters.ContainsKey('MsiPath')) {
        $downloadParams = @{
            Path = $DownloadPath
            AcceptEula = $AcceptEula
        }

        if ($PSBoundParameters.ContainsKey('Version')) {
            $downloadParams.Version = $Version
        }

        $downloadResult = Get-NessusAgentInstaller @downloadParams
        $MsiPath = $downloadResult.Path
    }

    if ((-not $isSimulation) -and (-not (Test-Path -LiteralPath $MsiPath))) {
        throw "MSI file was not found at '$MsiPath'."
    }

    $arguments = @(
        '/i'
        "`"$MsiPath`""
        '/qn'
        '/norestart'
        '/l*v'
        "`"$LogPath`""
    )

    $result = [pscustomobject]@{
        Installed = $false
        MsiPath = $MsiPath
        LogPath = $LogPath
        Arguments = @($arguments)
        ExitCode = $null
        RebootRequired = $false
        DetailedResult = 'install pending'
    }

    if (-not $isWindowsPlatform) {
        if ($isSimulation) {
            $result.DetailedResult = 'non-Windows WhatIf: msiexec command prepared only'
            return $result
        }

        throw 'Install-NessusAgent must run on Windows to execute msiexec.exe.'
    }

    if ($PSCmdlet.ShouldProcess($MsiPath, 'Install Nessus Agent MSI')) {
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru
        $result.ExitCode = $process.ExitCode

        switch ($process.ExitCode) {
            0 {
                $result.Installed = $true
                $result.DetailedResult = 'install completed successfully'
            }
            3010 {
                $result.Installed = $true
                $result.RebootRequired = $true
                $result.DetailedResult = 'install completed successfully and requires reboot'
            }
            default {
                $result.DetailedResult = "install failed with exit code $($process.ExitCode)"
                throw "msiexec.exe failed with exit code $($process.ExitCode). Review '$LogPath'."
            }
        }
    }
    else {
        $result.DetailedResult = 'install skipped by WhatIf or confirmation'
    }

    $result
}
