function Invoke-NessusAgentDeployment {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter()]
        [string]$NessusCliPath = 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe',

        [Parameter()]
        [string]$MsiPath,

        [Parameter()]
        [string]$DownloadPath = (Get-NessusAgentWorkingPath),

        [Parameter()]
        [ValidatePattern('\d+\.\d+\.\d+')]
        [string]$Version,

        [Parameter()]
        [string]$InstallLogPath = (Get-NessusAgentInstallLogPath),

        [Parameter()]
        [switch]$AcceptEula,

        [Parameter()]
        [string]$ServiceName = 'Tenable Nessus Agent',

        [Parameter()]
        [switch]$Relink,

        [Parameter()]
        [string]$LinkingKey = (Get-NessusAgentConfigurationValue -Name 'NessusKey'),

        [Parameter()]
        [Alias('Host')]
        [ValidateNotNullOrEmpty()]
        [string]$TargetHost = (Get-NessusAgentDefaultLinkTarget).Host,

        [Parameter()]
        [int]$Port = (Get-NessusAgentDefaultLinkTarget).Port,

        [Parameter()]
        [string]$CsvPath,

        [Parameter()]
        [Alias('Group')]
        [string]$GroupName,

        [Parameter()]
        [string]$ComputerName = $env:COMPUTERNAME,

        [Parameter()]
        [switch]$GroupOverride,

        [Parameter()]
        [string]$AgentName = $env:COMPUTERNAME,

        [Parameter()]
        [int]$MaxHoursSinceConnect = 24,

        [Parameter()]
        [int]$MaxHoursSinceConnectionAttempt = 24,

        [Parameter()]
        [int]$MaxHoursSinceScan = 168
    )

    $installResult = $null
    $repairResult = $null
    $status = $null
    $health = $null
    $localLogPath = $null
    $remoteLogPath = $null

    $agentInstalled = Test-Path -LiteralPath $NessusCliPath

    if (-not $agentInstalled) {
        $installParams = @{
            DownloadPath = $DownloadPath
            LogPath = $InstallLogPath
            AcceptEula = $AcceptEula
            WhatIf = $WhatIfPreference
            Confirm = $false
        }

        if ($PSBoundParameters.ContainsKey('MsiPath')) {
            $installParams.MsiPath = $MsiPath
        }

        if ($PSBoundParameters.ContainsKey('Version')) {
            $installParams.Version = $Version
        }

        $installResult = Install-NessusAgent @installParams
    }

    $statusAvailable = $false
    if ($agentInstalled -or ($installResult -and $installResult.Installed) -or ($installResult -and $installResult.DetailedResult -eq 'non-Windows WhatIf: msiexec command prepared only')) {
        try {
            $status = Get-NessusAgentStatus -Path $NessusCliPath
            $statusAvailable = $true
        }
        catch {
            if (-not ($WhatIfPreference -or -not ($env:OS -eq 'Windows_NT'))) {
                throw
            }
        }
    }

    if ($statusAvailable) {
        $health = Get-NessusAgentHealth -InputObject $status -ExpectedHost $TargetHost -MaxHoursSinceConnect $MaxHoursSinceConnect -MaxHoursSinceConnectionAttempt $MaxHoursSinceConnectionAttempt -MaxHoursSinceScan $MaxHoursSinceScan

        $repairParams = @{
            InputObject = $status
            Path = $NessusCliPath
            ServiceName = $ServiceName
            Relink = $Relink
            LinkingKey = $LinkingKey
            TargetHost = $TargetHost
            Port = $Port
            CsvPath = $CsvPath
            GroupName = $GroupName
            ComputerName = $ComputerName
            GroupOverride = $GroupOverride
            AgentName = $AgentName
            MaxHoursSinceConnect = $MaxHoursSinceConnect
            MaxHoursSinceConnectionAttempt = $MaxHoursSinceConnectionAttempt
            MaxHoursSinceScan = $MaxHoursSinceScan
            WhatIf = $WhatIfPreference
            Confirm = $false
        }

        $repairResult = Restore-NessusAgent @repairParams
        $health = $repairResult.After

        if ($repairResult.PSObject.Properties['Log']) {
            $localLogPath = $repairResult.Log.LocalLogPath
            $remoteLogPath = $repairResult.Log.RemoteLogPath
        }
    }

    $summary = if ($repairResult) {
        $repairResult.DetailedResult
    }
    elseif ($installResult) {
        $installResult.DetailedResult
    }
    elseif ($health) {
        $health.Summary
    }
    else {
        'agent not installed and no action taken'
    }

    [pscustomobject]@{
        Installed = [bool]$agentInstalled
        InstallResult = $installResult
        RepairResult = $repairResult
        Status = $status
        Health = $health
        LocalLogPath = $localLogPath
        RemoteLogPath = $remoteLogPath
        Summary = $summary
    }
}
