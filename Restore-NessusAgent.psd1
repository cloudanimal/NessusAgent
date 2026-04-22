@{
    RootModule = 'Restore-NessusAgent.psm1'
    ModuleVersion = '0.1.0'
    GUID = '13f4e99f-cf23-49e0-bc97-6028c8588b35'
    Author = 'OpenAI Codex'
    CompanyName = 'OpenAI'
    Copyright = '(c) OpenAI. All rights reserved.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
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
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @(
        'Get-MEDS'
    )
}
