function Get-NessusAgentDownloadInfo {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ApiUri = $script:RestoreNessusAgentConfig.AgentDetailsEndpoint,

        [Parameter()]
        [ValidateSet('x64')]
        [string]$Architecture = 'x64',

        [Parameter()]
        [ValidatePattern('\d+\.\d+\.\d+')]
        [string]$Version
    )

    $agentInformation = Invoke-RestMethod -Uri $ApiUri -ErrorAction Stop
    if (-not $agentInformation -or -not $agentInformation.products) {
        throw "Could not retrieve Nessus Agent download metadata from '$ApiUri'."
    }

    $availableVersions = foreach ($item in $agentInformation.products.PSObject.Properties) {
        if ($item.Name -match '^nessus-agents-(?<version>\d+\.\d+\.\d+)$') {
            $matches.version
        }
    }

    if (-not $availableVersions) {
        throw "Could not determine any Nessus Agent versions from '$ApiUri'."
    }

    if (-not $Version) {
        $Version = $availableVersions | Sort-Object { [version]$_ } -Descending | Select-Object -First 1
    }

    if (-not $Version) {
        throw "Could not determine the latest Nessus Agent version from '$ApiUri'."
    }

    if ($Version -notin $availableVersions) {
        throw "Version '$Version' is not available. Available versions: $($availableVersions -join ', ')."
    }

    $product = $agentInformation.products."nessus-agents-$Version"
    if (-not $product -or -not $product.downloads) {
        throw "Could not find download metadata for Nessus Agent version '$Version'."
    }

    $download = $product.downloads | Where-Object {
        $_.name -eq "NessusAgent-$Version-$Architecture.msi"
    } | Select-Object -First 1

    if (-not $download -or -not $download.id -or -not $download.file) {
        throw "Could not find the Windows $Architecture MSI for Nessus Agent version '$Version'."
    }

    [pscustomobject]@{
        Version = $Version
        FileName = [string]$download.file
        Uri = [string]::Format($script:RestoreNessusAgentConfig.AgentDownloadUrlFormat, $download.id)
        Source = 'DownloadsApi'
        MetadataUri = $ApiUri
        Sha256 = if ($download.meta_data) { [string]$download.meta_data.sha256 } else { $null }
        DownloadId = [string]$download.id
    }
}
