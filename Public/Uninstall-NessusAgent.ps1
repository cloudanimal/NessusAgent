function Uninstall-NessusAgent {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [switch]$AllowUninstall,

        [Parameter()]
        [switch]$PreflightOnly,

        [Parameter()]
        [string]$ProductCode,

        [Parameter()]
        [string]$Path = 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe',

        [Parameter()]
        [string]$Reason = 'NotSpecified',

        [Parameter()]
        [string]$LogPath = (Join-Path -Path (Get-NessusAgentWorkingPath) -ChildPath 'agent_uninstall.log'),

        [Parameter()]
        [string]$AuditLogPath = (Join-Path -Path (Get-NessusAgentWorkingPath) -ChildPath 'agent_uninstall_audit.log')
    )

    $isWindowsPlatform = $env:OS -eq 'Windows_NT'
    $isSimulation = [bool]$WhatIfPreference
    $candidateKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $result = [pscustomobject]@{
        Uninstalled = $false
        ProductCode = $ProductCode
        LogPath = $LogPath
        AuditLogPath = $AuditLogPath
        Reason = $Reason
        PreflightPassed = $false
        SafetyChecksPassed = $false
        StoppedService = $false
        StoppedProcesses = @()
        RemainingProcesses = @()
        ExitCode = $null
        DetailedResult = 'uninstall pending'
    }

    function Write-UninstallAuditEvent {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Stage,

            [Parameter(Mandatory = $true)]
            [string]$Outcome,

            [Parameter()]
            [string]$Message,

            [Parameter()]
            [int]$ExitCode
        )

        try {
            $auditDir = Split-Path -Parent $AuditLogPath
            if (-not [string]::IsNullOrWhiteSpace($auditDir) -and (-not (Test-Path -LiteralPath $auditDir))) {
                New-Item -ItemType Directory -Path $auditDir -Force | Out-Null
            }

            $callerIdentity = $null
            try {
                $callerIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            }
            catch {
                $callerIdentity = if ($env:USERNAME) { $env:USERNAME } else { 'unknown-user' }
            }

            $entry = [pscustomobject]@{
                Timestamp = (Get-Date).ToString('o')
                Command = 'Uninstall-NessusAgent'
                Stage = $Stage
                Outcome = $Outcome
                Message = $Message
                ComputerName = $env:COMPUTERNAME
                CallerIdentity = $callerIdentity
                ProductCode = $ProductCode
                ProductName = if ($result.PSObject.Properties['ProductName']) { $result.ProductName } else { $null }
                Publisher = if ($result.PSObject.Properties['Publisher']) { $result.Publisher } else { $null }
                Reason = $Reason
                ExitCode = $ExitCode
                LogPath = $LogPath
            } | ConvertTo-Json -Depth 4 -Compress

            Add-Content -LiteralPath $AuditLogPath -Value $entry -Encoding UTF8
        }
        catch {
            Write-Warning ("Failed to write uninstall audit log '{0}': {1}" -f $AuditLogPath, $_.Exception.Message)
        }
    }

    function Set-UninstallExitCode {
        param(
            [Parameter(Mandatory = $true)]
            [int]$Code
        )

        $global:LASTEXITCODE = $Code
    }

    Write-UninstallAuditEvent -Stage 'Precheck' -Outcome 'Started' -Message 'Beginning uninstall prechecks.'

    if (-not [string]::IsNullOrWhiteSpace($Path) -and (-not (Test-Path -LiteralPath $Path)) -and [string]::IsNullOrWhiteSpace($ProductCode)) {
        $result.DetailedResult = 'agent executable not found; uninstall not required'
        Write-UninstallAuditEvent -Stage 'Precheck' -Outcome 'Skipped' -Message $result.DetailedResult
        Set-UninstallExitCode -Code 0
        return $result
    }

    if ([string]::IsNullOrWhiteSpace($ProductCode)) {
        $resolvedCandidates = New-Object System.Collections.Generic.List[object]

        foreach ($key in $candidateKeys) {
            $entries = @(Get-ItemProperty -Path $key -ErrorAction SilentlyContinue | Where-Object {
                $_.DisplayName -like '*Nessus Agent*' -and (
                    $_.Publisher -like '*Tenable*' -or
                    $_.InstallLocation -like '*Tenable*' -or
                    $_.UninstallString -like '*nessus*'
                )
            })

            foreach ($entry in $entries) {
                if (-not $entry.UninstallString) {
                    continue
                }

                $match = [regex]::Match($entry.UninstallString, '\{[0-9A-Fa-f-]+\}')
                if (-not $match.Success) {
                    continue
                }

                $resolvedCandidates.Add([pscustomobject]@{
                    ProductCode = $match.Value
                    DisplayName = $entry.DisplayName
                    Publisher = $entry.Publisher
                    UninstallString = $entry.UninstallString
                })
            }
        }

        $uniqueCandidates = @($resolvedCandidates | Sort-Object -Property ProductCode -Unique)

        if ($uniqueCandidates.Count -eq 0) {
            Write-UninstallAuditEvent -Stage 'ResolveProduct' -Outcome 'Refused' -Message 'No Nessus Agent uninstall candidates found.'
            Set-UninstallExitCode -Code 1
            throw 'Unable to resolve Nessus Agent product code. Provide -ProductCode explicitly.'
        }

        if ($uniqueCandidates.Count -gt 1) {
            Write-UninstallAuditEvent -Stage 'ResolveProduct' -Outcome 'Refused' -Message 'Multiple Nessus Agent uninstall candidates found.'
            Set-UninstallExitCode -Code 1
            throw 'Multiple Nessus Agent uninstall candidates were found. Provide -ProductCode explicitly to uninstall exactly one product.'
        }

        $resolvedEntry = $uniqueCandidates[0]
        $ProductCode = $resolvedEntry.ProductCode
        $result.ProductCode = $ProductCode
        $result | Add-Member -NotePropertyName ProductName -NotePropertyValue $resolvedEntry.DisplayName
        $result | Add-Member -NotePropertyName Publisher -NotePropertyValue $resolvedEntry.Publisher
    }

    if ($ProductCode -notmatch '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$') {
        Write-UninstallAuditEvent -Stage 'ValidateProductCode' -Outcome 'Refused' -Message "Invalid product code format: $ProductCode"
        Set-UninstallExitCode -Code 1
        throw "Invalid ProductCode format '$ProductCode'. Expected MSI product code GUID in braces, for example {00000000-0000-0000-0000-000000000000}."
    }

    $validatedEntry = $null
    foreach ($key in $candidateKeys) {
        $validatedEntry = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue | Where-Object {
            $_.UninstallString -and $_.UninstallString -match [regex]::Escape($ProductCode)
        } | Select-Object -First 1

        if ($validatedEntry) {
            break
        }
    }

    if (-not $validatedEntry) {
        Write-UninstallAuditEvent -Stage 'ValidateProductCode' -Outcome 'Refused' -Message "Product code not found in uninstall entries: $ProductCode"
        Set-UninstallExitCode -Code 1
        throw "ProductCode '$ProductCode' was not found in registered uninstall entries. Refusing uninstall."
    }

    $isNessusAgent = ($validatedEntry.DisplayName -like '*Nessus Agent*') -and (
        $validatedEntry.Publisher -like '*Tenable*' -or
        $validatedEntry.InstallLocation -like '*Tenable*' -or
        $validatedEntry.UninstallString -like '*nessus*'
    )

    if (-not $isNessusAgent) {
        Write-UninstallAuditEvent -Stage 'ValidateProduct' -Outcome 'Refused' -Message "Resolved product is not Nessus Agent: $($validatedEntry.DisplayName)"
        Set-UninstallExitCode -Code 1
        throw "ProductCode '$ProductCode' resolves to '$($validatedEntry.DisplayName)' and is not recognized as Tenable Nessus Agent. Refusing uninstall."
    }

    $result | Add-Member -NotePropertyName ProductName -NotePropertyValue $validatedEntry.DisplayName -Force
    $result | Add-Member -NotePropertyName Publisher -NotePropertyValue $validatedEntry.Publisher -Force

    if (-not $AllowUninstall) {
        Write-UninstallAuditEvent -Stage 'SafetyGate' -Outcome 'Refused' -Message 'AllowUninstall switch was not provided.'
        Set-UninstallExitCode -Code 1
        throw 'Uninstall is blocked unless -AllowUninstall is explicitly provided.'
    }

    if (-not $isWindowsPlatform) {
        if ($isSimulation) {
            $result.DetailedResult = 'non-Windows WhatIf: msiexec uninstall command prepared only'
            Write-UninstallAuditEvent -Stage 'Execute' -Outcome 'Prepared' -Message $result.DetailedResult
            Set-UninstallExitCode -Code 0
            return $result
        }

        Write-UninstallAuditEvent -Stage 'Execute' -Outcome 'Refused' -Message 'Uninstall attempted on non-Windows platform.'
        Set-UninstallExitCode -Code 1
        throw 'Uninstall-NessusAgent must run on Windows to execute msiexec.exe.'
    }

    $nessusServiceName = 'Tenable Nessus Agent'
    $nessusProcessNames = @('nessus-service', 'nessus-agent-module', 'nessusd')
    $stoppedProcesses = New-Object System.Collections.Generic.List[string]

    Write-UninstallAuditEvent -Stage 'StopAgent' -Outcome 'Attempting' -Message 'Stopping Nessus service and processes before uninstall.'

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $nessusService = Get-Service -Name $nessusServiceName -ErrorAction SilentlyContinue
        if ($nessusService -and $nessusService.Status -ne 'Stopped') {
            try {
                Stop-Service -Name $nessusServiceName -Force -ErrorAction Stop
                $result.StoppedService = $true
            }
            catch {
                Write-UninstallAuditEvent -Stage 'StopAgent' -Outcome 'Warning' -Message ("Failed to stop service '{0}' on attempt {1}: {2}" -f $nessusServiceName, $attempt, $_.Exception.Message)
                Write-Warning ("Failed to stop service '{0}' on attempt {1}: {2}" -f $nessusServiceName, $attempt, $_.Exception.Message)
            }
        }

        foreach ($processName in $nessusProcessNames) {
            $running = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
            foreach ($process in $running) {
                try {
                    Stop-Process -Id $process.Id -Force -ErrorAction Stop
                    $stoppedProcesses.Add(('{0}:{1}' -f $process.Name, $process.Id))
                }
                catch {
                    Write-UninstallAuditEvent -Stage 'StopAgent' -Outcome 'Warning' -Message ("Failed to stop process '{0}' (PID {1}) on attempt {2}: {3}" -f $process.Name, $process.Id, $attempt, $_.Exception.Message)
                    Write-Warning ("Failed to stop process '{0}' (PID {1}) on attempt {2}: {3}" -f $process.Name, $process.Id, $attempt, $_.Exception.Message)
                }
            }
        }

        $maxStopWaitSeconds = 15
        $deadline = (Get-Date).AddSeconds($maxStopWaitSeconds)
        do {
            $remaining = @(Get-Process -Name $nessusProcessNames -ErrorAction SilentlyContinue)
            if ($remaining.Count -eq 0) {
                break
            }

            Start-Sleep -Milliseconds 500
        } while ((Get-Date) -lt $deadline)

        if ($remaining.Count -eq 0) {
            break
        }
    }

    $remaining = @(Get-Process -Name $nessusProcessNames -ErrorAction SilentlyContinue)
    $result.StoppedProcesses = @($stoppedProcesses | Sort-Object -Unique)
    $result.RemainingProcesses = @($remaining | ForEach-Object { '{0}:{1}' -f $_.Name, $_.Id })

    if ($remaining.Count -gt 0) {
        $remainingInfo = ($remaining | ForEach-Object { '{0}:{1}' -f $_.Name, $_.Id }) -join ', '
        Write-UninstallAuditEvent -Stage 'StopAgent' -Outcome 'Refused' -Message ("Nessus processes still running: {0}" -f $remainingInfo)
        Set-UninstallExitCode -Code 1
        throw "Refusing uninstall because Nessus processes are still running: $remainingInfo"
    }

    $result.PreflightPassed = $true
    $result.SafetyChecksPassed = $true
    Write-UninstallAuditEvent -Stage 'StopAgent' -Outcome 'Success' -Message 'Nessus service/processes confirmed stopped.'

    if ($PreflightOnly) {
        if ($result.StoppedService) {
            try {
                Start-Service -Name $nessusServiceName -ErrorAction Stop
                Write-UninstallAuditEvent -Stage 'Preflight' -Outcome 'Info' -Message 'Service restarted after preflight stop.'
            }
            catch {
                Write-UninstallAuditEvent -Stage 'Preflight' -Outcome 'Warning' -Message ("Failed to restart service after preflight: {0}" -f $_.Exception.Message)
                Write-Warning ("Failed to restart '{0}' after preflight: {1}" -f $nessusServiceName, $_.Exception.Message)
            }
        }
        $result.DetailedResult = 'preflight checks passed; uninstall not executed'
        Write-UninstallAuditEvent -Stage 'Preflight' -Outcome 'Success' -Message $result.DetailedResult
        Set-UninstallExitCode -Code 0
        return $result
    }

    $arguments = @(
        '/x'
        $ProductCode
        '/qn'
        '/norestart'
        '/l*v'
        "`"$LogPath`""
    )

    if ($PSCmdlet.ShouldProcess($ProductCode, 'Uninstall Nessus Agent MSI')) {
        Write-UninstallAuditEvent -Stage 'Execute' -Outcome 'Attempting' -Message 'Invoking msiexec uninstall.'
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru
        $result.ExitCode = $process.ExitCode

        switch ($process.ExitCode) {
            0 {
                $result.Uninstalled = $true
                $result.DetailedResult = 'uninstall completed successfully'
                Write-UninstallAuditEvent -Stage 'Result' -Outcome 'Success' -Message $result.DetailedResult -ExitCode $process.ExitCode
                Set-UninstallExitCode -Code 0
            }
            1605 {
                $result.Uninstalled = $false
                $result.DetailedResult = 'product is not installed'
                Write-UninstallAuditEvent -Stage 'Result' -Outcome 'NotInstalled' -Message $result.DetailedResult -ExitCode $process.ExitCode
                Set-UninstallExitCode -Code 0
            }
            3010 {
                $result.Uninstalled = $true
                $result.DetailedResult = 'uninstall completed successfully and requires reboot'
                Write-UninstallAuditEvent -Stage 'Result' -Outcome 'SuccessRebootRequired' -Message $result.DetailedResult -ExitCode $process.ExitCode
                Set-UninstallExitCode -Code 0
            }
            default {
                $result.DetailedResult = "uninstall failed with exit code $($process.ExitCode)"
                Write-UninstallAuditEvent -Stage 'Result' -Outcome 'Failed' -Message $result.DetailedResult -ExitCode $process.ExitCode
                Set-UninstallExitCode -Code 1
                throw "msiexec.exe uninstall failed with exit code $($process.ExitCode). Review '$LogPath'."
            }
        }
    }
    else {
        $result.DetailedResult = 'uninstall skipped by WhatIf or confirmation'
        Write-UninstallAuditEvent -Stage 'Execute' -Outcome 'Skipped' -Message $result.DetailedResult
        Set-UninstallExitCode -Code 0
    }

    $result
}
