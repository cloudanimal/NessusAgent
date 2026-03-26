$publicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'

foreach ($path in @($privatePath, $publicPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        continue
    }

    foreach ($file in Get-ChildItem -LiteralPath $path -Filter '*.ps1' -File | Sort-Object -Property Name) {
        . $file.FullName
    }
}

Export-ModuleMember -Function @(
    'Get-EpcDistributionServer',
    'Get-NessusAgentHealth',
    'Get-NessusAgentInstaller',
    'Get-EpcRegistry',
    'Get-NessusAgentStatus',
    'Get-NessusAgentConfiguration',
    'Install-NessusAgent',
    'Invoke-NessusAgentDeployment',
    'Restore-NessusAgent'
)
