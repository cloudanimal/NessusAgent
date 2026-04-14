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

function New-HealthSnapshot {
    [CmdletBinding()]
    param(
        [Parameter()]
        [psobject]$Health
    )

    if ($null -eq $Health) {
        return $null
    }

    $status = if ($Health.PSObject.Properties['Status']) { $Health.Status } else { $null }

    [pscustomobject]@{
        overallStatus = if ($Health.PSObject.Properties['OverallStatus']) { $Health.OverallStatus } else { $null }
        isHealthy = if ($Health.PSObject.Properties['IsHealthy']) { [bool]$Health.IsHealthy } else { $false }
        healthExitCode = if ($Health.PSObject.Properties['ExitCode']) { $Health.ExitCode } else { $null }
        summary = if ($Health.PSObject.Properties['Summary']) { $Health.Summary } else { $null }
        findingCount = if ($Health.PSObject.Properties['FindingCount']) { $Health.FindingCount } else { 0 }
        agentStatus = if ($Health.PSObject.Properties['AgentStatus']) { $Health.AgentStatus } else { $null }
        linkedHost = if ($Health.PSObject.Properties['LinkedHost']) { $Health.LinkedHost } else { $null }
        expectedHost = if ($Health.PSObject.Properties['ExpectedHost']) { $Health.ExpectedHost } else { $null }
        linkedTo = if ($status -and $status.PSObject.Properties['LinkedTo']) { $status.LinkedTo } else { $null }
        linkStatus = if ($status -and $status.PSObject.Properties['LinkStatus']) { $status.LinkStatus } else { $null }
        running = if ($status -and $status.PSObject.Properties['Running']) { $status.Running } else { $null }
        lastConnectUtc = if ($status -and $status.PSObject.Properties['LastConnect'] -and $status.LastConnect -is [datetime]) { $status.LastConnect.ToUniversalTime().ToString('o') } else { $null }
        lastConnectionAttemptUtc = if ($status -and $status.PSObject.Properties['LastConnectionAttempt'] -and $status.LastConnectionAttempt -is [datetime]) { $status.LastConnectionAttempt.ToUniversalTime().ToString('o') } else { $null }
        lastScannedUtc = if ($status -and $status.PSObject.Properties['LastScanned'] -and $status.LastScanned -is [datetime]) { $status.LastScanned.ToUniversalTime().ToString('o') } else { $null }
    }
}

function ConvertTo-OperatorJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Result
    )

    $normalized = [ordered]@{}
    foreach ($property in $Result.PSObject.Properties) {
        $normalized[$property.Name] = $property.Value
    }

    foreach ($name in @('actions', 'warnings', 'errors')) {
        if (-not $normalized.Contains($name) -or $null -eq $normalized[$name]) {
            $normalized[$name] = @()
            continue
        }

        $value = $normalized[$name]
        if ($value -is [System.Collections.IDictionary] -and $value.Keys.Count -eq 0) {
            $normalized[$name] = @()
            continue
        }

        if ($value -is [string]) {
            $normalized[$name] = @($value)
            continue
        }

        if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
            $normalized[$name] = @($value)
            continue
        }

        $normalized[$name] = @($value)
    }

    ([pscustomobject]$normalized | ConvertTo-Json -Compress -Depth 10)
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
            ConvertTo-OperatorJson -Result $FlatResult
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
    $runStart = Get-Date

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

    $restoreWarnings = @()
    $result = Restore-NessusAgent @restoreParams -WarningAction SilentlyContinue -WarningVariable +restoreWarnings

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
        timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        durationMs = [int]((Get-Date) - $runStart).TotalMilliseconds
        csvPath = if ($PSBoundParameters.ContainsKey('CsvPath')) { $CsvPath } else { $null }
        actions = if ($result.Actions) {
            @($result.Actions | ForEach-Object {
                if ($_.PSObject.Properties['Group'] -and $_.PSObject.Properties['GroupSource']) {
                    '{0}:{1}:{2}:{3}' -f $_.Action, $_.Result, $_.Group, $_.GroupSource
                }
                elseif ($_.PSObject.Properties['Group']) {
                    '{0}:{1}:{2}' -f $_.Action, $_.Result, $_.Group
                }
                else {
                    '{0}:{1}' -f $_.Action, $_.Result
                }
            })
        }
        else { @() }
        warnings = @(
            if ($result.After -and $result.After.PSObject.Properties['Findings']) {
                $result.After.Findings | Where-Object { $_.Severity -eq 'Warning' } | ForEach-Object { $_.Message }
            }
            if ($restoreWarnings) {
                $restoreWarnings | ForEach-Object {
                    if ($_ -is [System.Management.Automation.WarningRecord]) {
                        $_.Message
                    }
                    else {
                        [string]$_
                    }
                }
            }
        )
        errors = if ($result.After -and $result.After.PSObject.Properties['Findings']) {
            @($result.After.Findings | Where-Object { $_.Severity -eq 'Error' } | ForEach-Object { $_.Message })
        }
        else { @() }
        before = New-HealthSnapshot -Health $result.Before
        after = New-HealthSnapshot -Health $result.After
    }

    $flatResult | Add-Member -NotePropertyName exitCode -NotePropertyValue (Get-ExitCodeFromFlatResult -Result $flatResult)

    Write-FormattedResult -FlatResult $flatResult -OutputMode $outputMode
    exit $flatResult.exitCode
}
catch {
    $outputMode = $PSCmdlet.ParameterSetName
    $runEnd = Get-Date

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
        timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        durationMs = if (Get-Variable -Name runStart -Scope Local -ErrorAction SilentlyContinue) { [int]($runEnd - $runStart).TotalMilliseconds } else { $null }
        csvPath = if ($PSBoundParameters.ContainsKey('CsvPath')) { $CsvPath } else { $null }
        actions = @()
        warnings = @()
        errors = @($_.Exception.Message)
        before = $null
        after = $null
        exitCode = 2
    }

    Write-FormattedResult -FlatResult $flatErrorResult -OutputMode $outputMode
    exit 2
}
