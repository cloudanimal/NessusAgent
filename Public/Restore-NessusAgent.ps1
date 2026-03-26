function Get-EpcRegistry {
    [CmdletBinding()]
    param()

    $isWindowsPlatform = $env:OS -eq 'Windows_NT'
    if (-not $isWindowsPlatform) {
        throw 'Get-EpcRegistry is supported on Windows only.'
    }

    $candidatePaths = @(
        'HKLM:\SOFTWARE\WOW6432Node\AdventNet\DesktopCentral\DCAgent',
        'HKLM:\SOFTWARE\AdventNet\DesktopCentral\DCAgent'
    )

    $basePath = $candidatePaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $basePath) {
        throw 'Could not find an EPC agent registry key under HKLM:\SOFTWARE\WOW6432Node\AdventNet\DesktopCentral\DCAgent or HKLM:\SOFTWARE\AdventNet\DesktopCentral\DCAgent.'
    }

    $baseProperties = Get-ItemProperty -LiteralPath $basePath
    $childKeys = @(Get-ChildItem -LiteralPath $basePath -ErrorAction SilentlyContinue)

    $serverInfoPath = Join-Path -Path $basePath -ChildPath 'ServerInfo'
    $serverInfo = $null
    if (Test-Path -LiteralPath $serverInfoPath) {
        $serverInfo = Get-ItemProperty -LiteralPath $serverInfoPath
    }

    [pscustomobject]@{
        BasePath = $basePath
        ServerInfoPath = if ($serverInfo) { $serverInfoPath } else { $null }
        DCAgentVersion = if ($baseProperties.PSObject.Properties['DCAgentVersion']) { $baseProperties.DCAgentVersion } else { $null }
        DCServerName = if ($serverInfo -and $serverInfo.PSObject.Properties['DCServerName']) { $serverInfo.DCServerName } else { $null }
        DCServerIPAddress = if ($serverInfo -and $serverInfo.PSObject.Properties['DCServerIPAddress']) { $serverInfo.DCServerIPAddress } else { $null }
        DCLastAccessName = if ($serverInfo -and $serverInfo.PSObject.Properties['DCLastAccessName']) { $serverInfo.DCLastAccessName } else { $null }
        DCServerPort = if ($serverInfo -and $serverInfo.PSObject.Properties['DCServerPort']) { $serverInfo.DCServerPort } else { $null }
        DCServerSecurePort = if ($serverInfo -and $serverInfo.PSObject.Properties['DCServerSecurePort']) { $serverInfo.DCServerSecurePort } else { $null }
        DCServerProtocol = if ($serverInfo -and $serverInfo.PSObject.Properties['DCServerProtocol']) { $serverInfo.DCServerProtocol } else { $null }
        BaseProperties = $baseProperties.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                Value = $_.Value
            }
        }
        ChildKeys = @($childKeys | ForEach-Object {
            [pscustomobject]@{
                Name = $_.PSChildName
                Path = $_.PSPath
            }
        })
        ServerInfoProperties = if ($serverInfo) {
            @($serverInfo.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Name
                    Value = $_.Value
                }
            })
        }
        else {
            @()
        }
    }
}

function Get-EpcDistributionServer {
    [CmdletBinding()]
    param()

    $registry = Get-EpcRegistry

    [pscustomobject]@{
        ServerName = $registry.DCServerName
        IPAddress = $registry.DCServerIPAddress
        LastAccessName = $registry.DCLastAccessName
        Port = $registry.DCServerPort
        SecurePort = $registry.DCServerSecurePort
        Protocol = $registry.DCServerProtocol
        RegistryPath = $registry.ServerInfoPath
        Raw = $registry
    }
}

function Write-NessusAgentLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Result,

        [Parameter()]
        [string]$Tmp = (Get-NessusAgentWorkingPath)
    )

    $localLogRoot = $Tmp
    if (-not (Test-Path -LiteralPath $localLogRoot)) {
        New-Item -ItemType Directory -Path $localLogRoot -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $computerName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'unknown-computer' }
    $logName = 'Restore-NessusAgent-{0}-{1}.log' -f $computerName, $timestamp
    $localLogPath = Join-Path -Path $localLogRoot -ChildPath $logName

    $epcDistributionServer = $null
    try {
        if ($env:OS -eq 'Windows_NT') {
            $epcDistributionServer = Get-EpcDistributionServer
        }
    }
    catch {
    }

    $logPayload = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        ComputerName = $computerName
        DetailedResult = $Result.DetailedResult
        Changed = if ($Result.PSObject.Properties['Changed']) { $Result.Changed } else { $null }
        InstallResult = if ($Result.PSObject.Properties['InstallResult']) { $Result.InstallResult } else { $null }
        Actions = if ($Result.PSObject.Properties['Actions']) { $Result.Actions } else { $null }
        Before = if ($Result.PSObject.Properties['Before']) { $Result.Before } else { $null }
        After = if ($Result.PSObject.Properties['After']) { $Result.After } else { $null }
        EpcDistributionServer = $epcDistributionServer
    } | ConvertTo-Json -Depth 8

    Set-Content -LiteralPath $localLogPath -Value $logPayload -Encoding UTF8

    $distributionLogPath = $null
    if ($epcDistributionServer -and $epcDistributionServer.ServerName) {
        try {
            $distributionLogRoot = "\\$($epcDistributionServer.ServerName)\tenable\agent\logs"
            if (-not (Test-Path -LiteralPath $distributionLogRoot)) {
                New-Item -ItemType Directory -Path $distributionLogRoot -Force | Out-Null
            }

            $distributionLogPath = Join-Path -Path $distributionLogRoot -ChildPath $logName
            Copy-Item -LiteralPath $localLogPath -Destination $distributionLogPath -Force
        }
        catch {
            $distributionLogPath = $null
        }
    }

    [pscustomobject]@{
        LocalLogPath = $localLogPath
        RemoteLogPath = $distributionLogPath
    }
}

function Restore-NessusAgent {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [psobject]$InputObject,

        [Parameter()]
        [string]$Path = 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe',

        [Parameter()]
        [string]$MsiPath,

        [Parameter()]
        [Alias('TempPath')]
        [string]$Tmp = (Get-NessusAgentWorkingPath),

        [Parameter()]
        [string]$DownloadPath,

        [Parameter()]
        [ValidatePattern('\d+\.\d+\.\d+')]
        [string]$Version,

        [Parameter()]
        [string]$InstallLogPath,

        [Parameter()]
        [string]$ServiceName = 'Tenable Nessus Agent',

        [Parameter()]
        [switch]$Relink,

        [Parameter()]
        [Alias('Host')]
        [ValidateNotNullOrEmpty()]
        [string]$TargetHost = (Get-NessusAgentDefaultLinkTarget).Host,

        [Parameter()]
        [string]$LinkingKey = (Get-NessusAgentConfigurationValue -Name 'NessusKey'),

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

    process {
        function Get-RepairSummary {
            param(
                [Parameter(Mandatory = $true)]
                [psobject]$Before,

                [Parameter()]
                [AllowEmptyCollection()]
                [psobject[]]$Actions = @(),

                [Parameter()]
                [switch]$GroupOverrideUsed
            )

            $linkedHost = if ($Before.PSObject.Properties['LinkedHost']) { $Before.LinkedHost } else { $null }
            $linkMismatch = ($linkedHost -and $Before.ExpectedHost -and $linkedHost.ToString().Trim().ToLowerInvariant() -ne $Before.ExpectedHost.ToString().Trim().ToLowerInvariant())
            $actionNames = @($Actions | ForEach-Object { $_.Action })
            $linkAction = @($Actions | Where-Object { $_.Action -eq 'LinkAgent' } | Select-Object -First 1)

            if ($Before.OverallStatus -eq 'OK' -and $actionNames.Count -eq 0) {
                return 'healthy agent: no change'
            }

            if ($linkMismatch -and $linkAction) {
                if ($linkAction.GroupSource -eq 'Explicit') {
                    return 'wrong target with explicit group: unlink + relink using provided group'
                }

                if ($linkAction.GroupSource -eq 'Csv') {
                    return 'wrong target with CSV group: unlink + relink using CSV group'
                }

                if ($linkAction.GroupSource -eq 'Override') {
                    return 'wrong target with missing CSV group and -GroupOverride: fallback to SCPM'
                }
            }

            if ($linkMismatch -and $actionNames -contains 'ResolveGroup' -and -not ($actionNames -contains 'UnlinkAgent')) {
                if ($GroupOverrideUsed) {
                    return 'wrong target with missing CSV group and -GroupOverride: fallback to SCPM'
                }

                return 'wrong target with missing CSV group and no override: no unlink, only ResolveGroup:Failed'
            }

            if ($actionNames.Count -eq 0) {
                return 'no change'
            }

            return ($Actions | ForEach-Object {
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

        if ($Relink -and [string]::IsNullOrWhiteSpace($LinkingKey)) {
            throw 'LinkingKey is required when -Relink is specified.'
        }

        if (-not $PSBoundParameters.ContainsKey('DownloadPath')) {
            $DownloadPath = $Tmp
        }

        if (-not $PSBoundParameters.ContainsKey('InstallLogPath')) {
            $InstallLogPath = Join-Path -Path $Tmp -ChildPath 'agent_install.log'
        }

        $installResult = $null
        $pathExists = Test-Path -LiteralPath $Path
        $shouldAttemptInstall = (-not $PSBoundParameters.ContainsKey('InputObject')) -and (-not $pathExists) -and (
            ($env:OS -eq 'Windows_NT') -or
            $PSBoundParameters.ContainsKey('MsiPath') -or
            $PSBoundParameters.ContainsKey('Version')
        )

        if ($shouldAttemptInstall) {
            $installParams = @{
                DownloadPath = $DownloadPath
                LogPath = $InstallLogPath
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
            $pathExists = Test-Path -LiteralPath $Path

            if (-not $pathExists) {
                $result = [pscustomobject]@{
                    Changed = [bool]($installResult -and $installResult.Installed)
                    InstallResult = $installResult
                    Actions = @()
                    Before = $null
                    After = $null
                    DetailedResult = $installResult.DetailedResult
                }
                $logResult = Write-NessusAgentLog -Result $result -Tmp $Tmp
                $result | Add-Member -NotePropertyName Log -NotePropertyValue $logResult
                return $result
            }
        }

        $status = if ($PSBoundParameters.ContainsKey('InputObject') -and $InputObject.PSObject.Properties['Status']) {
            $InputObject.Status
        }
        elseif ($PSBoundParameters.ContainsKey('InputObject')) {
            $InputObject
        }
        else {
            Get-NessusAgentStatus -Path $Path
        }

        $health = Get-NessusAgentHealth -InputObject $status -ExpectedHost $TargetHost -MaxHoursSinceConnect $MaxHoursSinceConnect -MaxHoursSinceConnectionAttempt $MaxHoursSinceConnectionAttempt -MaxHoursSinceScan $MaxHoursSinceScan
        $before = $health
        $actions = New-Object System.Collections.Generic.List[object]

        if ($health.IsHealthy) {
            $actionsArray = [object[]]$actions.ToArray()
            $result = [pscustomobject]@{
                Changed = $false
                InstallResult = $installResult
                Actions = $actionsArray
                Before = $health
                After = $health
                DetailedResult = (Get-RepairSummary -Before $health -Actions $actionsArray -GroupOverrideUsed:$GroupOverride)
            }
            $logResult = Write-NessusAgentLog -Result $result -Tmp $Tmp
            $result | Add-Member -NotePropertyName Log -NotePropertyValue $logResult
            return $result
        }

        $runningValue = if ($status.Running) { $status.Running.ToString().Trim().ToLowerInvariant() } else { '' }
        $needsServiceRepair = ($runningValue -ne 'yes')

        if ($needsServiceRepair -and $PSCmdlet.ShouldProcess($ServiceName, 'Restart Nessus Agent service')) {
            $service = Get-Service -Name $ServiceName -ErrorAction Stop

            if ($service.Status -eq 'Running') {
                Restart-Service -Name $ServiceName -Force -ErrorAction Stop
                $actions.Add([pscustomobject]@{
                    Action = 'RestartService'
                    Target = $ServiceName
                    Result = 'Restarted'
                })
            }
            else {
                Start-Service -Name $ServiceName -ErrorAction Stop
                $actions.Add([pscustomobject]@{
                    Action = 'StartService'
                    Target = $ServiceName
                    Result = 'Started'
                })
            }

            Start-Sleep -Seconds 5
            $status = Get-NessusAgentStatus -Path $Path
            $health = Get-NessusAgentHealth -InputObject $status -ExpectedHost $TargetHost -MaxHoursSinceConnect $MaxHoursSinceConnect -MaxHoursSinceConnectionAttempt $MaxHoursSinceConnectionAttempt -MaxHoursSinceScan $MaxHoursSinceScan
        }

        $linkRelatedFindings = @($health.Findings | Where-Object { $_.Property -in @('LinkedTo', 'LinkStatus', 'LastConnect', 'LastConnectionAttempt') })
        $needsRelink = $Relink -and ($linkRelatedFindings.Count -gt 0)
        if ($needsRelink) {
            $groupName = $null
            $groupSource = $null

            if (-not [string]::IsNullOrWhiteSpace($GroupName)) {
                $groupName = $GroupName.Trim()
                $groupSource = 'Explicit'
            }
            else {
                try {
                    $groupInfo = Get-NessusAgentGroupFromCsv -CsvPath $CsvPath -ComputerName $ComputerName
                    $groupName = $groupInfo.Group
                    $groupSource = 'Csv'
                }
                catch {
                    $actions.Add([pscustomobject]@{
                        Action = 'ResolveGroup'
                        Target = $ComputerName
                        Result = 'Failed'
                        Output = $_.Exception.Message
                    })

                    if ($GroupOverride) {
                        $groupName = 'SCPM'
                        $groupSource = 'Override'
                    }
                }
            }

            if ([string]::IsNullOrWhiteSpace($groupName)) {
                $actionsArray = [object[]]$actions.ToArray()
                $result = [pscustomobject]@{
                    Changed = ($actions.Count -gt 0)
                    InstallResult = $installResult
                    Actions = $actionsArray
                    Before = $before
                    After = $health
                    DetailedResult = (Get-RepairSummary -Before $before -Actions $actionsArray -GroupOverrideUsed:$GroupOverride)
                }
                $logResult = Write-NessusAgentLog -Result $result -Tmp $Tmp
                $result | Add-Member -NotePropertyName Log -NotePropertyValue $logResult
                return $result
            }

            if ($PSCmdlet.ShouldProcess($ComputerName, "Relink Nessus Agent to $TargetHost`:$Port with group '$groupName'")) {
                $tagRegistryResult = Remove-NessusAgentTagRegistry -Confirm:$false
                if ($tagRegistryResult -and $tagRegistryResult.Removed) {
                    $actions.Add([pscustomobject]@{
                        Action = 'RemoveTagRegistry'
                        Target = $tagRegistryResult.Path
                        Result = $tagRegistryResult.Result
                    })
                }

                $unlinkResult = Invoke-NessusCli -Path $Path -ArgumentList @('agent', 'unlink', '--force')
                $actions.Add([pscustomobject]@{
                    Action = 'UnlinkAgent'
                    Target = $TargetHost
                    Result = if ($unlinkResult.ExitCode -eq 0) { 'Success' } else { 'Failed' }
                    Output = $unlinkResult.OutputText
                })

                if ($unlinkResult.ExitCode -ne 0) {
                    throw "nessuscli agent unlink failed.`n$($unlinkResult.OutputText)"
                }

                $linkArguments = @(
                    'agent',
                    'link',
                    "--key=$LinkingKey",
                    "--host=$TargetHost",
                    "--port=$Port",
                    "--name=$AgentName",
                    "--groups=$groupName"
                )

                $linkResult = Invoke-NessusCli -Path $Path -ArgumentList $linkArguments
                $actions.Add([pscustomobject]@{
                    Action = 'LinkAgent'
                    Target = "$TargetHost`:$Port"
                    Result = if ($linkResult.ExitCode -eq 0) { 'Success' } else { 'Failed' }
                    Group = $groupName
                    GroupSource = $groupSource
                    Output = $linkResult.OutputText
                })

                if ($linkResult.ExitCode -ne 0) {
                    throw "nessuscli agent link failed.`n$($linkResult.OutputText)"
                }

                Start-Sleep -Seconds 5
                $status = Get-NessusAgentStatus -Path $Path
                $health = Get-NessusAgentHealth -InputObject $status -ExpectedHost $TargetHost -MaxHoursSinceConnect $MaxHoursSinceConnect -MaxHoursSinceConnectionAttempt $MaxHoursSinceConnectionAttempt -MaxHoursSinceScan $MaxHoursSinceScan
            }
        }

        $actionsArray = [object[]]$actions.ToArray()

        $result = [pscustomobject]@{
            Changed = (($actions.Count -gt 0) -or [bool]($installResult -and $installResult.Installed))
            InstallResult = $installResult
            Actions = $actionsArray
            Before = $before
            After = $health
            DetailedResult = (Get-RepairSummary -Before $before -Actions $actionsArray -GroupOverrideUsed:$GroupOverride)
        }
        $logResult = Write-NessusAgentLog -Result $result -Tmp $Tmp
        $result | Add-Member -NotePropertyName Log -NotePropertyValue $logResult
        $result
    }
}
