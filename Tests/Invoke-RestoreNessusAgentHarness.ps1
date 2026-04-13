$moduleRoot = Split-Path -Parent $PSScriptRoot

Get-ChildItem -LiteralPath (Join-Path $moduleRoot 'Private') -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object {
    . $_.FullName
}

Get-ChildItem -LiteralPath (Join-Path $moduleRoot 'Public') -Filter '*.ps1' -File | Sort-Object Name | Where-Object { $_.Name -ne 'Export-TIOAgents.ps1' } | ForEach-Object {
    . $_.FullName
}

function Get-MeDistributionServer {
    $null
}

$script:HarnessState = @{
    StatusByName = @{
        Healthy = [pscustomobject]@{
            Running = 'Yes'
            LinkedTo = 'sensor.cloud.tenable.com:443'
            LinkStatus = 'Connected'
            Proxy = 'none'
            PluginSet = '202603200915'
            Scanning = 'No'
            ScansRunToday = 0
            LastScanned = [datetime]'2026-03-19T23:48:10'
            LastScannedText = '2026/03/19 23:48:10'
            LastConnect = [datetime]'2026-03-20T09:15:42'
            LastConnectText = '2026/03/20 09:15:42'
            LastConnectionAttempt = [datetime]'2026-03-20T09:15:42'
            LastConnectionAttemptText = '2026/03/20 09:15:42'
            JobsPending = 0
            AgentStatus = 'Connected'
            RawOutput = ''
        }
        WrongCloudTarget = [pscustomobject]@{
            Running = 'Yes'
            LinkedTo = 'cloud.tenable.com:443'
            LinkStatus = 'Connected'
            Proxy = 'none'
            PluginSet = '202603200915'
            Scanning = 'No'
            ScansRunToday = 0
            LastScanned = [datetime]'2026-03-19T23:48:10'
            LastScannedText = '2026/03/19 23:48:10'
            LastConnect = [datetime]'2026-03-20T09:15:42'
            LastConnectText = '2026/03/20 09:15:42'
            LastConnectionAttempt = [datetime]'2026-03-20T09:15:42'
            LastConnectionAttemptText = '2026/03/20 09:15:42'
            JobsPending = 0
            AgentStatus = 'Connected'
            RawOutput = ''
        }
        Unlinked = [pscustomobject]@{
            Running = 'Yes'
            LinkedTo = $null
            LinkStatus = 'Not linked'
            Proxy = 'none'
            PluginSet = '202603200915'
            Scanning = 'No'
            ScansRunToday = 0
            LastScanned = [datetime]'2026-03-19T23:48:10'
            LastScannedText = '2026/03/19 23:48:10'
            LastConnect = [datetime]'2026-03-20T09:15:42'
            LastConnectText = '2026/03/20 09:15:42'
            LastConnectionAttempt = [datetime]'2026-03-20T09:15:42'
            LastConnectionAttemptText = '2026/03/20 09:15:42'
            JobsPending = 0
            AgentStatus = 'Unlinked'
            RawOutput = ''
        }
    }
    CurrentStatusName = 'Healthy'
    InvocationLog = New-Object System.Collections.Generic.List[object]
}

function Get-NessusAgentStatus {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe'
    )

    $script:HarnessState.StatusByName[$script:HarnessState.CurrentStatusName]
}

function Get-Service {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    [pscustomobject]@{
        Name = $Name
        Status = 'Running'
    }
}

function Restart-Service {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [switch]$Force
    )

    $script:HarnessState.InvocationLog.Add([pscustomobject]@{
        Action = 'Restart-Service'
        Name = $Name
    })
}

function Start-Service {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $script:HarnessState.InvocationLog.Add([pscustomobject]@{
        Action = 'Start-Service'
        Name = $Name
    })
}

function Start-Sleep {
    [CmdletBinding()]
    param(
        [int]$Seconds
    )
}

function Test-Path {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    switch ($LiteralPath) {
        'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe' { return $true }
        default { return (Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath) }
    }
}

function Invoke-NessusCli {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe',

        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    $script:HarnessState.InvocationLog.Add([pscustomobject]@{
        Action = 'Invoke-NessusCli'
        Arguments = ($ArgumentList -join ' ')
    })

    if ($ArgumentList[0] -eq 'agent' -and $ArgumentList[1] -eq 'unlink') {
        $script:HarnessState.CurrentStatusName = 'Unlinked'
    }
    elseif ($ArgumentList[0] -eq 'agent' -and $ArgumentList[1] -eq 'link') {
        $script:HarnessState.CurrentStatusName = 'Healthy'
    }

    [pscustomobject]@{
        Path = $Path
        ArgumentList = @($ArgumentList)
        ExitCode = 0
        Output = @('ok')
        OutputText = 'ok'
    }
}

$csvPath = Join-Path $PSScriptRoot 'agents.csv'

$scenarios = @(
    [pscustomobject]@{
        Name = 'Healthy'
        ComputerName = 'SERVER01'
        StatusName = 'Healthy'
        Relink = $false
        GroupOverride = $false
    }
    [pscustomobject]@{
        Name = 'Wrong cloud target with CSV group'
        ComputerName = 'SERVER01'
        StatusName = 'WrongCloudTarget'
        Relink = $true
        GroupOverride = $false
    }
    [pscustomobject]@{
        Name = 'Wrong cloud target with missing CSV group and no override'
        ComputerName = 'SERVER03'
        StatusName = 'WrongCloudTarget'
        Relink = $true
        GroupOverride = $false
    }
    [pscustomobject]@{
        Name = 'Wrong cloud target with missing CSV group and override'
        ComputerName = 'SERVER03'
        StatusName = 'WrongCloudTarget'
        Relink = $true
        GroupOverride = $true
    }
)

$results = foreach ($scenario in $scenarios) {
    $script:HarnessState.CurrentStatusName = $scenario.StatusName
    $script:HarnessState.InvocationLog.Clear()

    $health = Get-NessusAgentHealth -InputObject (Get-NessusAgentStatus) -ExpectedHost 'sensor.cloud.tenable.com'

    $repairParams = @{
        ComputerName = $scenario.ComputerName
        CsvPath = $csvPath
        Confirm = $false
        WhatIf = $false
        Path = 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe'
    }

    if ($scenario.Relink) {
        $repairParams.Relink = $true
        $repairParams.LinkingKey = 'HARNESS-KEY'
    }

    if ($scenario.GroupOverride) {
        $repairParams.GroupOverride = $true
    }

    $repair = Restore-NessusAgent @repairParams

    [pscustomobject]@{
        Scenario = $scenario.Name
        HealthSummary = $health.Summary
        ExpectedHost = $health.ExpectedHost
        LinkedHost = $health.LinkedHost
        BeforeStatus = $repair.Before.OverallStatus
        AfterStatus = $repair.After.OverallStatus
        Changed = $repair.Changed
        BeforeSummary = $repair.Before.Summary
        AfterSummary = $repair.After.Summary
        Actions = ($repair.Actions | ForEach-Object {
            if (-not $_) {
                return
            }

            if ($_.PSObject.Properties['Group'] -and $_.PSObject.Properties['GroupSource']) {
                '{0}:{1}:{2}:{3}' -f $_.Action, $_.Result, $_.Group, $_.GroupSource
            }
            elseif ($_.PSObject.Properties['Group']) {
                '{0}:{1}:{2}' -f $_.Action, $_.Result, $_.Group
            }
            else {
                '{0}:{1}' -f $_.Action, $_.Result
            }
        }) -join '; '
    }
}

$results | Format-List

'Expected behavior summary:'
'- healthy agent: no change'
'- wrong target with CSV group: unlink + relink using CSV group'
'- wrong target with missing CSV group and no override: no unlink, only ResolveGroup:Failed'
'- wrong target with missing CSV group and -GroupOverride: fallback to SCPM'
