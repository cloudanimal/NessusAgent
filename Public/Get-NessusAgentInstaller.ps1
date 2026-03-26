function Get-NessusAgentInstaller {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter()]
        [string]$Path = (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'NessusAgent'),

        [Parameter()]
        [string]$ApiUri = $script:RestoreNessusAgentConfig.AgentDetailsEndpoint,

        [Parameter()]
        [ValidatePattern('\d+\.\d+\.\d+')]
        [string]$Version,

        [Parameter()]
        [string[]]$SearchPath = $script:RestoreNessusAgentConfig.InstallerSearchPaths
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    $searchRoots = New-Object System.Collections.Generic.List[string]
    $isWindowsPlatform = $env:OS -eq 'Windows_NT'
    $moduleRoot = Split-Path -Parent $PSScriptRoot

    if (-not [string]::IsNullOrWhiteSpace($moduleRoot)) {
        $searchRoots.Add($moduleRoot)
    }

    $epcDistributionShare = $null
    if ($isWindowsPlatform) {
        try {
            $epcDistributionServer = Get-EpcDistributionServer
            if ($epcDistributionServer -and $epcDistributionServer.ServerName) {
                $epcDistributionShare = "\\$($epcDistributionServer.ServerName)\tenable\agent"
            }
        }
        catch {
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($epcDistributionShare)) {
        $searchRoots.Add($epcDistributionShare)
    }

    foreach ($item in $SearchPath) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $searchRoots.Add($item)
        }
    }

    $findInstallerParams = @{
        Path = [string[]]$searchRoots.ToArray()
    }

    if ($PSBoundParameters.ContainsKey('Version')) {
        $findInstallerParams.Version = $Version
    }

    $internalInstaller = $null
    if ($findInstallerParams.Path.Count -gt 0) {
        $internalInstaller = Find-NessusAgentInstaller @findInstallerParams
    }

    if ($internalInstaller) {
        $destination = Join-Path -Path $Path -ChildPath $internalInstaller.FileName
        $downloaded = $false

        if (-not (Test-Path -LiteralPath $destination)) {
            if ($PSCmdlet.ShouldProcess($destination, "Copy Nessus Agent from $($internalInstaller.FullName)")) {
                Copy-Item -LiteralPath $internalInstaller.FullName -Destination $destination -Force
                $downloaded = $true
            }
        }

        return [pscustomobject]@{
            Downloaded = $downloaded
            Path = $destination
            FileName = $internalInstaller.FileName
            Version = $internalInstaller.Version
            Uri = $null
            Source = 'InternalShare'
            MetadataUri = $null
            DownloadId = $null
            HashValidated = $false
            Sha256 = $null
        }
    }

    $downloadInfoParams = @{
        ApiUri = $ApiUri
    }

    if ($PSBoundParameters.ContainsKey('Version')) {
        $downloadInfoParams.Version = $Version
    }

    $downloadInfo = Get-NessusAgentDownloadInfo @downloadInfoParams

    $destination = Join-Path -Path $Path -ChildPath $downloadInfo.FileName
    $downloaded = $false
    $hashValidated = $false

    if (-not (Test-Path -LiteralPath $destination)) {
        if ($PSCmdlet.ShouldProcess($destination, "Download Nessus Agent from $($downloadInfo.Uri)")) {
            $previousProgressPreference = $ProgressPreference
            try {
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri $downloadInfo.Uri -OutFile $destination -UseBasicParsing -ErrorAction Stop
                $downloaded = $true
            }
            finally {
                $ProgressPreference = $previousProgressPreference
            }
        }
    }

    if ($downloadInfo.Sha256 -and (Test-Path -LiteralPath $destination)) {
        $actualHash = (Get-FileHash -Path $destination -Algorithm SHA256).Hash
        if ($actualHash -ne $downloadInfo.Sha256) {
            throw "Downloaded file hash '$actualHash' did not match expected hash '$($downloadInfo.Sha256)'."
        }

        $hashValidated = $true
    }

    $result = [pscustomobject]@{
        Downloaded = $downloaded
        Path = $destination
        FileName = $downloadInfo.FileName
        Version = $downloadInfo.Version
        Uri = $downloadInfo.Uri
        Source = $downloadInfo.Source
        MetadataUri = $downloadInfo.MetadataUri
        DownloadId = $downloadInfo.DownloadId
        HashValidated = $hashValidated
        Sha256 = $downloadInfo.Sha256
    }

    $result
}
