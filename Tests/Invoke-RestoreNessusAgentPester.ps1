[CmdletBinding()]
param()

if (-not (Get-Module -ListAvailable -Name Pester)) {
    throw 'Pester is not installed. Install it with: Install-Module Pester -Scope CurrentUser'
}

Invoke-Pester -Path (Join-Path $PSScriptRoot 'Restore-NessusAgent.Tests.ps1') -Output Detailed
