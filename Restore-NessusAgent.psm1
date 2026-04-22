$publicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'

foreach ($path in @($privatePath, $publicPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        continue
    }

    foreach ($file in Get-ChildItem -LiteralPath $path -Filter '*.ps1' -File | Sort-Object -Property Name) {
        # Standalone operational scripts with top-level param blocks should not be dot-sourced during module import.
        if ($file.Name -eq 'Export-TIOAgents.ps1') {
            continue
        }

        . $file.FullName
    }
}

Export-ModuleMember -Function @(
    'Get-MeDistributionServer',
    'Get-NessusAgentHealth',
    'Get-NessusAgentInstaller',
    'Get-EpcRegistry',
    'Set-NessusAgentSecret',
    'Remove-NessusAgentSecret',
    'Get-NessusAgentStatus',
    'Get-NessusAgentConfiguration',
    'Install-NessusAgent',
    'Uninstall-NessusAgent',
    'Restore-NessusAgent'
) -Alias @(
    'Get-MEDS'
)
