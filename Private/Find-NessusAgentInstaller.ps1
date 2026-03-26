function Find-NessusAgentInstaller {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Path,

        [Parameter()]
        [ValidatePattern('\d+\.\d+\.\d+')]
        [string]$Version
    )

    $candidates = foreach ($root in $Path) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) {
            continue
        }

        foreach ($file in Get-ChildItem -LiteralPath $root -Filter 'NessusAgent-*-x64.msi' -File -Recurse -ErrorAction SilentlyContinue) {
            if ($file.Name -notmatch '^NessusAgent-(?<version>\d+\.\d+\.\d+)-x64\.msi$') {
                continue
            }

            if ($PSBoundParameters.ContainsKey('Version') -and $matches.version -ne $Version) {
                continue
            }

            [pscustomobject]@{
                Version = $matches.version
                FileName = $file.Name
                FullName = $file.FullName
                Root = $root
            }
        }
    }

    if (-not $candidates) {
        return $null
    }

    $candidates |
        Sort-Object { [version]$_.Version }, FullName -Descending |
        Select-Object -First 1
}
