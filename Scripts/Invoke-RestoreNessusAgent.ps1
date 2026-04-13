[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Default')]
param(
    [Parameter()]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter()]
    [string]$AgentName = $env:COMPUTERNAME,

    [Parameter()]
    [string]$CsvPath,

    [Parameter()]
    [string]$NessusCliPath = 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe',

    [Parameter()]
    [string]$MsiPath,

    [Parameter()]
    [ValidatePattern('\d+\.\d+\.\d+')]
    [string]$Version,

    [Parameter()]
    [switch]$Relink = $true,

    [Parameter()]
    [Alias('LinkingKey')]
    [string]$Key,

    [Parameter()]
    [Alias('GroupName')]
    [string]$Group,

    [Parameter()]
    [switch]$GroupOverride,

    [Parameter()]
    [int]$MaxHoursSinceConnect = 24,

    [Parameter()]
    [int]$MaxHoursSinceConnectionAttempt = 24,

    [Parameter()]
    [int]$MaxHoursSinceScan = 168

    ,

    [Parameter(ParameterSetName = 'Csv')]
    [switch]$Csv,

    [Parameter(ParameterSetName = 'Json')]
    [switch]$Json,

    [Parameter(ParameterSetName = 'Tab')]
    [switch]$Tab
)

$moduleRoot = Split-Path -Parent $PSScriptRoot
$moduleManifest = Join-Path -Path $moduleRoot -ChildPath 'Restore-NessusAgent.psd1'
Import-Module -Name $moduleManifest -Force

function Get-ExitCodeFromFlatResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Result
    )

    if ($Result.PSObject.Properties['AfterStatus'] -and $Result.AfterStatus -eq 'Critical') {
        return 2
    }

    if ($Result.PSObject.Properties['Outcome'] -and $Result.Outcome -in @('Failed', 'Error')) {
        return 2
    }

    if ($Result.PSObject.Properties['AfterStatus'] -and $Result.AfterStatus -eq 'Warning') {
        return 1
    }

    if ($Result.PSObject.Properties['Outcome'] -and $Result.Outcome -in @('InstallPending', 'Observed')) {
        return 1
    }

    0
}

function Write-FormattedResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$FlatResult,

        [Parameter()]
        [string]$OutputMode
    )

    switch ($OutputMode) {
        'Csv' {
            $FlatResult | ConvertTo-Csv -NoTypeInformation
            break
        }
        'Json' {
            $FlatResult | ConvertTo-Json -Compress
            break
        }
        'Tab' {
            $properties = @(
                'ComputerName',
                'AgentName',
                'Installed',
                'Changed',
                'Outcome',
                'ActionTaken',
                'Summary',
                'BeforeStatus',
                'AfterStatus',
                'LinkedHost',
                'ExpectedHost',
                'Group',
                'GroupSource',
                'LocalLogPath',
                'RemoteLogPath'
            )

            $header = $properties -join "`t"
            $row = $properties | ForEach-Object {
                $value = $FlatResult.$_
                if ($null -eq $value) {
                    ''
                }
                else {
                    $value.ToString().Replace("`t", ' ').Replace("`r", ' ').Replace("`n", ' ')
                }
            }

            $header
            ($row -join "`t")
            break
        }
        default {
            $FlatResult
        }
    }
}

try {
    $outputMode = $PSCmdlet.ParameterSetName

    $configuration = Get-NessusAgentConfiguration -IncludeSecrets
    $resolvedComputerName = $ComputerName
    $resolvedAgentName = $AgentName
    $effectiveLinkingKey = if ($PSBoundParameters.ContainsKey('Key')) { $Key } else { $configuration.NessusKey }
    $linkTargetHost = 'sensor.cloud.tenable.com'
    $linkTargetPort = 443
    if (-not [string]::IsNullOrWhiteSpace($configuration.NessusServer) -and $configuration.NessusServer -match '^(?<host>.+):(?<port>\d+)$') {
        $linkTargetHost = $matches.host.Trim()
        $linkTargetPort = [int]$matches.port
    }
    elseif (-not [string]::IsNullOrWhiteSpace($configuration.NessusServer)) {
        $linkTargetHost = $configuration.NessusServer.Trim()
    }

    if (-not (Test-Path -LiteralPath (Split-Path -Parent $configuration.LogPath))) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $configuration.LogPath) -Force | Out-Null
    }

    if ($Relink -and [string]::IsNullOrWhiteSpace($effectiveLinkingKey)) {
        if ($WhatIfPreference) {
            Write-Warning 'No Nessus linking key is configured. Continuing because -WhatIf was specified.'
        }
        else {
        throw @"
No Nessus linking key is configured.

Set one of these before running with -Relink:
- REPAIR_NESSUS_AGENT_KEY environment variable
- Restore-NessusAgent.local.psd1 (copy from Restore-NessusAgent.local.psd1.example)
"@
        }
    }

    $restoreParams = @{
        Path = $NessusCliPath
        Relink = $Relink
        LinkingKey = $effectiveLinkingKey
        TargetHost = $linkTargetHost
        Port = $linkTargetPort
        ComputerName = $resolvedComputerName
        AgentName = $resolvedAgentName
        MaxHoursSinceConnect = $MaxHoursSinceConnect
        MaxHoursSinceConnectionAttempt = $MaxHoursSinceConnectionAttempt
        MaxHoursSinceScan = $MaxHoursSinceScan
        Confirm = $false
        WhatIf = $WhatIfPreference
    }

    if ($PSBoundParameters.ContainsKey('Group')) {
        $restoreParams.GroupName = $Group
    }
    else {
        $restoreParams.GroupOverride = $GroupOverride
    }

    if ($PSBoundParameters.ContainsKey('CsvPath')) {
        $restoreParams.CsvPath = $CsvPath
    }

    if ($PSBoundParameters.ContainsKey('MsiPath')) {
        $restoreParams.MsiPath = $MsiPath
    }

    if ($PSBoundParameters.ContainsKey('Version')) {
        $restoreParams.Version = $Version
    }

    $result = Restore-NessusAgent @restoreParams

    $linkAction = $null
    if ($result.Actions) {
        $linkAction = $result.Actions | Where-Object { $_.Action -eq 'LinkAgent' } | Select-Object -First 1
    }

    $agentInstalled = (Test-Path -LiteralPath $NessusCliPath) -or [bool]($result.InstallResult -and $result.InstallResult.Installed)

    $flatResult = [pscustomobject]@{
        ComputerName = $resolvedComputerName
        AgentName = $resolvedAgentName
        Installed = $agentInstalled
        Changed = $result.Changed
        Outcome = if ($result.InstallResult -and $result.InstallResult.Installed -and -not $result.After) {
            'Installed'
        }
        elseif ($result.InstallResult -and -not $result.InstallResult.Installed -and -not $result.After) {
            'InstallPending'
        }
        elseif ($result.Changed) {
            'Changed'
        }
        else {
            'NoChange'
        }
        ActionTaken = if ($result.Actions) {
            (($result.Actions | ForEach-Object { $_.Action }) -join '; ')
        }
        else {
            $null
        }
        Summary = $result.DetailedResult
        BeforeStatus = if ($result.Before) { $result.Before.OverallStatus } else { $null }
        AfterStatus = if ($result.After) { $result.After.OverallStatus } else { $null }
        LinkedHost = if ($result.After) { $result.After.LinkedHost } else { $null }
        ExpectedHost = if ($result.After) { $result.After.ExpectedHost } else { $null }
        Group = if ($linkAction) { $linkAction.Group } else { $null }
        GroupSource = if ($linkAction) { $linkAction.GroupSource } else { $null }
        LocalLogPath = if ($result.Log) { $result.Log.LocalLogPath } else { $null }
        RemoteLogPath = if ($result.Log) { $result.Log.RemoteLogPath } else { $null }
    }

    Write-FormattedResult -FlatResult $flatResult -OutputMode $outputMode
    exit (Get-ExitCodeFromFlatResult -Result $flatResult)
}
catch {
    $outputMode = $PSCmdlet.ParameterSetName

    $flatErrorResult = [pscustomobject]@{
        ComputerName = $ComputerName
        AgentName = $AgentName
        Installed = $false
        Changed = $null
        Outcome = 'Failed'
        ActionTaken = $null
        Summary = $_.Exception.Message
        BeforeStatus = $null
        AfterStatus = 'Critical'
        LinkedHost = $null
        ExpectedHost = $null
        Group = $Group
        GroupSource = if ($PSBoundParameters.ContainsKey('Group')) { 'Explicit' } else { $null }
        LocalLogPath = $null
        RemoteLogPath = $null
    }

    Write-FormattedResult -FlatResult $flatErrorResult -OutputMode $outputMode
    exit 2
}
