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
    }
    CurrentStatusName = 'WrongCloudTarget'
    InvocationLog = New-Object System.Collections.Generic.List[object]
    RemovedPaths = New-Object System.Collections.Generic.List[string]
}

$env:OS = 'Windows_NT'

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
}

function Start-Service {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
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
        'HKLM:\SOFTWARE\Tenable\TAG' { return $true }
        default { return (Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath) }
    }
}

function Remove-Item {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath,

        [switch]$Recurse,

        [switch]$Force
    )

    $script:HarnessState.RemovedPaths.Add($LiteralPath)
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
        $script:HarnessState.CurrentStatusName = 'WrongCloudTarget'
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

$repair = Restore-NessusAgent -ComputerName 'SERVER01' -CsvPath $csvPath -Relink -LinkingKey 'HARNESS-KEY' -Confirm:$false

[pscustomobject]@{
    DetailedResult = $repair.DetailedResult
    Actions = ($repair.Actions | ForEach-Object {
        if ($_.PSObject.Properties['Group'] -and $_.PSObject.Properties['GroupSource']) {
            '{0}:{1}:{2}:{3}' -f $_.Action, $_.Result, $_.Group, $_.GroupSource
        }
        else {
            '{0}:{1}' -f $_.Action, $_.Result
        }
    }) -join '; '
    RemovedPaths = ($script:HarnessState.RemovedPaths -join '; ')
} | Format-List
