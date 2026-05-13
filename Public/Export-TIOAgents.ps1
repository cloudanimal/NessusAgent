[CmdletBinding()]
param(
    [Parameter()][ValidateNotNullOrEmpty()][string]$ScannerId = '1',
    [Parameter()][ValidateNotNullOrEmpty()][string]$OutDir    = 'C:\Temp\Tenable',

    [Parameter()][ValidateSet('Fast','Detail')]
    [string]$Mode = 'Fast',

    [Parameter()][switch]$Detail,        # backward compatibility (forces Detail mode)
    [Parameter()][switch]$DetailTest,    # sample run (forces Detail mode)
    [Parameter()][ValidateRange(1,5000)][int]$SampleSize = 10,

    # Raw detail export (full fidelity) - default ON for Detail mode; ignored for Fast
    [Parameter()][switch]$ExportRawDetail,

    [Parameter()][ValidateRange(1,5000)][int]$Limit = 5000,
    [Parameter()][ValidateRange(0,60000)][int]$ThrottleMs = 100,

    [Parameter()][string]$AccessKey = $env:TENABLE_ACCESS_KEY,
    [Parameter()][string]$SecretKey = $env:TENABLE_SECRET_KEY
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Normalize mode
if ($Detail -or $DetailTest) { $Mode = 'Detail' }
$IsDetailMode = ($Mode -eq 'Detail')
$isDetailTestRun = [bool]$DetailTest

# Default: in Detail mode, export raw detail unless user explicitly set -ExportRawDetail:$false
if ($IsDetailMode -and -not $PSBoundParameters.ContainsKey('ExportRawDetail')) {
    $ExportRawDetail = $true
}

# -------------------------
# Helpers
# -------------------------

function Ensure-Directory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function ConvertFrom-ExportTioSecureString {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Security.SecureString]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Resolve-ExportTioSecretStorePath {
    [CmdletBinding()]
    param()

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $localConfigPath = Join-Path -Path $moduleRoot -ChildPath 'Restore-NessusAgent.local.psd1'
    if (Test-Path -LiteralPath $localConfigPath) {
        $localConfig = Import-PowerShellDataFile -LiteralPath $localConfigPath
        if ($localConfig.ContainsKey('SecretStorePath') -and -not [string]::IsNullOrWhiteSpace([string]$localConfig['SecretStorePath'])) {
            return [string]$localConfig['SecretStorePath']
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        return (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Restore-NessusAgent\secrets.clixml')
    }

    Join-Path -Path 'C:\Temp' -ChildPath 'Restore-NessusAgent\secrets.clixml'
}

function Resolve-ExportTioApiKeys {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey
    )

    $resolvedAccessKey = $AccessKey
    $resolvedSecretKey = $SecretKey

    if (-not [string]::IsNullOrWhiteSpace($resolvedAccessKey) -and -not [string]::IsNullOrWhiteSpace($resolvedSecretKey)) {
        return [pscustomobject]@{ AccessKey = $resolvedAccessKey; SecretKey = $resolvedSecretKey }
    }

    $secretStorePath = Resolve-ExportTioSecretStorePath
    if (-not [string]::IsNullOrWhiteSpace($secretStorePath) -and (Test-Path -LiteralPath $secretStorePath)) {
        $secretStore = Import-Clixml -LiteralPath $secretStorePath

        if ([string]::IsNullOrWhiteSpace($resolvedAccessKey) -and $secretStore.PSObject.Properties['TenableAccessKey']) {
            $value = $secretStore.TenableAccessKey
            if ($value -is [System.Security.SecureString]) {
                $resolvedAccessKey = ConvertFrom-ExportTioSecureString -Value $value
            }
            elseif ($value -is [string]) {
                $resolvedAccessKey = $value
            }
        }

        if ([string]::IsNullOrWhiteSpace($resolvedSecretKey) -and $secretStore.PSObject.Properties['TenableSecretKey']) {
            $value = $secretStore.TenableSecretKey
            if ($value -is [System.Security.SecureString]) {
                $resolvedSecretKey = ConvertFrom-ExportTioSecureString -Value $value
            }
            elseif ($value -is [string]) {
                $resolvedSecretKey = $value
            }
        }
    }

    [pscustomobject]@{ AccessKey = $resolvedAccessKey; SecretKey = $resolvedSecretKey }
}

function Get-SafeTimestamp {
    (Get-Date).ToString('yyyyMMdd-HHmmss')
}

function New-TioHeaders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AccessKey,
        [Parameter(Mandatory)][string]$SecretKey
    )

    if ([string]::IsNullOrWhiteSpace($AccessKey) -or [string]::IsNullOrWhiteSpace($SecretKey)) {
        throw "Missing TENABLE API keys. Provide -AccessKey/-SecretKey or set TENABLE_ACCESS_KEY/TENABLE_SECRET_KEY."
    }

    @{
        Accept      = 'application/json'
        'X-ApiKeys' = "accessKey=$AccessKey; secretKey=$SecretKey"
    }
}

function Export-RawDetailJsonl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Agents,
        [Parameter(Mandatory)][string]$Path
    )

    $utf8 = New-Object System.Text.UTF8Encoding($true)
    $sw = New-Object System.IO.StreamWriter($Path, $false, $utf8)
    try {
        foreach ($a in $Agents) {
            $sw.WriteLine(($a | ConvertTo-Json -Depth 30 -Compress))
        }
    }
    finally { $sw.Close() }
}

function Export-Skipped404Csv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Skipped,
        [Parameter(Mandatory)][string]$Path
    )
    $Skipped | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
}

function Export-RunSummaryJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Summary,
        [Parameter(Mandatory)][string]$Path
    )
    ($Summary | ConvertTo-Json -Depth 6) | Out-File -FilePath $Path -Encoding UTF8
}

function ConvertTo-ExportTioScalar {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return $null }

    if ($Value -is [string] -or $Value -is [ValueType]) {
        return $Value
    }

    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString('o')
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return ($Value | ConvertTo-Json -Depth 20 -Compress)
    }

    if ($Value -is [psobject]) {
        return ($Value | ConvertTo-Json -Depth 20 -Compress)
    }

    return [string]$Value
}

function ConvertTo-TioExportRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Agent,

        [Parameter(Mandatory)]
        [hashtable]$AgentToGroups
    )

    $record = [ordered]@{
        Hostname = if ($Agent.PSObject.Properties['name']) { $Agent.name } else { $null }
        AgentId = if ($Agent.PSObject.Properties['id']) { $Agent.id } else { $null }
        Groups = if ($Agent.PSObject.Properties['id'] -and $AgentToGroups.ContainsKey([int]$Agent.id)) {
            ($AgentToGroups[[int]$Agent.id] | Sort-Object -Unique) -join ', '
        }
        else {
            ''
        }
        LastConnectUtc = if ($Agent.PSObject.Properties['last_connect']) { Convert-FromUnixSecondsSafe -Value $Agent.last_connect } else { $null }
        LastScannedUtc = if ($Agent.PSObject.Properties['last_scanned']) { Convert-FromUnixSecondsSafe -Value $Agent.last_scanned } else { $null }
    }

    foreach ($property in $Agent.PSObject.Properties) {
        $outName = [string]$property.Name
        while ((@($record.Keys | ForEach-Object { $_.ToString().ToLowerInvariant() }) -contains $outName.ToLowerInvariant())) {
            $outName = "api_$outName"
        }

        $record[$outName] = ConvertTo-ExportTioScalar -Value $property.Value
    }

    [pscustomobject]$record
}

function ConvertTo-FlattenedTioExportRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Agent,

        [Parameter(Mandatory)]
        [hashtable]$AgentToGroups
    )

    # Start with base record (includes computed fields + all agent properties)
    $record = [ordered]@{
        Hostname = if ($Agent.PSObject.Properties['name']) { $Agent.name } else { $null }
        AgentId = if ($Agent.PSObject.Properties['id']) { $Agent.id } else { $null }
        Groups = if ($Agent.PSObject.Properties['id'] -and $AgentToGroups.ContainsKey([int]$Agent.id)) {
            ($AgentToGroups[[int]$Agent.id] | Sort-Object -Unique) -join ', '
        }
        else {
            ''
        }
        LastConnectUtc = if ($Agent.PSObject.Properties['last_connect']) { Convert-FromUnixSecondsSafe -Value $Agent.last_connect } else { $null }
        LastScannedUtc = if ($Agent.PSObject.Properties['last_scanned']) { Convert-FromUnixSecondsSafe -Value $Agent.last_scanned } else { $null }
    }

    # Extract health_events into flattened columns
    if ($Agent.PSObject.Properties['health_events'] -and $null -ne $Agent.health_events) {
        $events = @($Agent.health_events)
        $record['HealthEvents_Count'] = $events.Count

        if ($events.Count -gt 0) {
            # Current state (most recent): first event or highest severity
            $latestEvent = $events[0]
            $record['HealthEvents_CurrentState'] = if ($latestEvent.PSObject.Properties['state']) { $latestEvent.state } else { $null }
            $record['HealthEvents_CurrentStateName'] = if ($latestEvent.PSObject.Properties['state_name']) { $latestEvent.state_name } else { $null }
            $record['HealthEvents_LastEventTime'] = if ($latestEvent.PSObject.Properties['state_time']) { 
                Convert-FromUnixSecondsSafe -Value $latestEvent.state_time 
            } else { $null }

            # Count events by severity
            $stateNames = @($events | ForEach-Object { $_.state_name })
            $record['HealthEvents_HealthyCount'] = @($stateNames | Where-Object { $_ -eq 'HEALTHY' }).Count
            $record['HealthEvents_WarningCount'] = @($stateNames | Where-Object { $_ -eq 'WARNING' }).Count
            $record['HealthEvents_CriticalCount'] = @($stateNames | Where-Object { $_ -eq 'CRITICAL' }).Count
        } else {
            # No events; ensure columns exist with null
            $record['HealthEvents_CurrentState'] = $null
            $record['HealthEvents_CurrentStateName'] = $null
            $record['HealthEvents_LastEventTime'] = $null
            $record['HealthEvents_HealthyCount'] = 0
            $record['HealthEvents_WarningCount'] = 0
            $record['HealthEvents_CriticalCount'] = 0
        }
    }

    # Extract remote_settings as individual flattened properties
    if ($Agent.PSObject.Properties['remote_settings'] -and $null -ne $Agent.remote_settings) {
        $settings = $Agent.remote_settings
        if ($settings -is [psobject]) {
            foreach ($settingProp in $settings.PSObject.Properties) {
                $settingName = "RemoteSettings_$($settingProp.Name)"
                $record[$settingName] = ConvertTo-ExportTioScalar -Value $settingProp.Value
            }
        }
    }

    # restart_pending as direct column
    if ($Agent.PSObject.Properties['restart_pending']) {
        $record['RestartPending'] = $Agent.restart_pending
    }

    # Add all other agent properties (excluding those already processed)
    $excludedProps = @(
        'name', 'id', 'last_connect', 'last_scanned', 'health_events', 'remote_settings', 'restart_pending'
    )

    foreach ($property in $Agent.PSObject.Properties) {
        if ($property.Name -in $excludedProps) { continue }

        $outName = [string]$property.Name
        while ((@($record.Keys | ForEach-Object { $_.ToString().ToLowerInvariant() }) -contains $outName.ToLowerInvariant())) {
            $outName = "api_$outName"
        }

        $record[$outName] = ConvertTo-ExportTioScalar -Value $property.Value
    }

    [pscustomobject]$record
}

function Export-PartialArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OutDir,
        [Parameter(Mandatory)][string]$BaseName,
        [Parameter(Mandatory)][object[]]$Agents,
        [Parameter(Mandatory)][hashtable]$AgentToGroups,
        [Parameter()][bool]$IsDetailMode = $false
    )

    if (-not $Agents -or $Agents.Count -eq 0) { return }

    $ts = Get-SafeTimestamp

    # Full fidelity partial (JSONL)
    $partialRaw = Join-Path $OutDir ("{0}_{1}_PARTIAL_RAW.jsonl" -f $BaseName, $ts)
    Export-RawDetailJsonl -Agents $Agents -Path $partialRaw
    Write-Warning "Partial RAW export written: $partialRaw"

    # Human-friendly partial report CSV: use flattened format in Detail mode
    $partialCsv = Join-Path $OutDir ("{0}_{1}_PARTIAL_REPORT.csv" -f $BaseName, $ts)
    $exportFunction = if ($IsDetailMode) { 'ConvertTo-FlattenedTioExportRecord' } else { 'ConvertTo-TioExportRecord' }
    try {
        $Agents |
            ForEach-Object { & $exportFunction -Agent $_ -AgentToGroups $AgentToGroups } |
            Export-Csv -Path $partialCsv -NoTypeInformation -Encoding UTF8
        Write-Warning "Partial REPORT export written: $partialCsv"
    } catch {
        Write-Warning "Partial REPORT CSV failed (non-fatal): $($_.Exception.Message)"
    }
}

function Convert-FromUnixSecondsSafe {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return $null }

    $text = $Value.ToString().Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    if ($text.ToLowerInvariant() -in @('never', '(null)', 'n/a')) { return $null }

    $epoch = 0L
    if (-not [long]::TryParse($text, [ref]$epoch)) { return $null }

    # Accept both seconds and milliseconds since epoch.
    if ($epoch -gt 9999999999) {
        $epoch = [math]::Floor($epoch / 1000)
    }

    try {
        return [DateTimeOffset]::FromUnixTimeSeconds($epoch).UtcDateTime
    }
    catch {
        return $null
    }
}

# -------------------------
# Progress helper (HostName-safe)
# -------------------------

function Write-ProgressVerbose {
    [CmdletBinding(DefaultParameterSetName='Progress')]
    param(
        [Parameter(ParameterSetName='Banner', Mandatory)]
        [switch]$Banner,

        [Parameter(ParameterSetName='Banner')]
        [string]$RunMode,

        [Parameter(ParameterSetName='Banner')]
        [int]$Total,

        [Parameter(ParameterSetName='Banner')]
        [string]$OutFile,

        [Parameter(ParameterSetName='Banner')]
        [switch]$IsDetailTestRun,

        [Parameter(ParameterSetName='Banner')]
        [int]$SampleSize,

        [Parameter(ParameterSetName='Progress', Mandatory)]
        [int]$Index,

        [Parameter(ParameterSetName='Progress', Mandatory)]
        [int]$TotalProgress,

        [Parameter(ParameterSetName='Progress')]
        [int]$AgentId,

        [Parameter(ParameterSetName='Progress')]
        [string]$HostName,

        [Parameter(ParameterSetName='Progress')]
        [int]$Every = 250
    )

    if ($VerbosePreference -eq 'SilentlyContinue') { return }

    $now = Get-Date

    if ($PSCmdlet.ParameterSetName -eq 'Banner') {
        $msg = "[{0:HH:mm:ss}] Start | Mode={1} | Total={2}" -f $now, $RunMode, $Total
        if ($IsDetailTestRun) { $msg += " | DetailTest=True | SampleSize=$SampleSize" }
        if ($OutFile) { $msg += " | OutFile=$OutFile" }
        Write-Verbose $msg
        return
    }

    Write-Verbose ("[{0:HH:mm:ss}] Detail {1}/{2} | AgentId={3} | HostName={4}" -f $now, $Index, $TotalProgress, $AgentId, $HostName)

    if ($Every -gt 0 -and ($Index % $Every -eq 0 -or $Index -eq $TotalProgress)) {
        $pct = [math]::Round(($Index / $TotalProgress) * 100, 1)
        Write-Verbose ("[{0:HH:mm:ss}] Progress {1}/{2} ({3}%)" -f $now, $Index, $TotalProgress, $pct)
    }
}

# -------------------------
# Fleet-safe request wrapper (404 skip + skipped list)
# -------------------------

function Invoke-TioRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter()][string]$Context = ''
    )

    # StrictMode-safe init for skipped list
    if (-not (Get-Variable -Name Skipped404 -Scope Script -ErrorAction SilentlyContinue)) {
        $script:Skipped404 = New-Object System.Collections.Generic.List[object]
    }

    try {
        return Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -Verbose:$false
    }
    catch {
        $status = $null
        try { $status = $_.Exception.Response.StatusCode.value__ } catch { }

        switch ($status) {
            404 {
                $script:Skipped404.Add([pscustomobject]@{
                    Timestamp = (Get-Date).ToString('s')
                    Status    = 404
                    Context   = $Context
                    Uri       = $Uri
                }) | Out-Null

                Write-Warning "Tenable returned 404 (resource disappeared). Skipping: $Uri"
                return $null
            }

            429 { throw "Tenable API rate-limited (429): $Uri" }
            500 { throw "Tenable API internal error (500): $Uri" }
            502 { throw "Tenable API bad gateway (502): $Uri" }
            503 { throw "Tenable API unavailable (503): $Uri" }
            504 { throw "Tenable API timeout (504): $Uri" }

            default {
                if ($status) { throw "Tenable API request failed ($status): $Uri" }
                throw "Tenable API request failed: $Uri"
            }
        }
    }
}

# -------------------------
# API (scanner-scoped)
# -------------------------

function Get-TioAgents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScannerId,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][int]$Limit
    )

    $offset = 0
    $allAgents = New-Object System.Collections.Generic.List[object]

    while ($true) {
        $uri  = "https://cloud.tenable.com/scanners/$ScannerId/agents?limit=$Limit&offset=$offset"
        $resp = Invoke-TioRequest -Uri $uri -Headers $Headers -Context 'AgentList'

        if ($null -eq $resp) { break } # safety

        foreach ($a in @($resp.agents)) { [void]$allAgents.Add($a) }

        if (-not $resp.agents -or @($resp.agents).Count -lt $Limit) { break }
        $offset += $Limit
    }

    $allAgents
}

function Get-TioAgentDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScannerId,
        [Parameter(Mandatory)][int]$AgentId,
        [Parameter(Mandatory)][hashtable]$Headers
    )

    $uri = "https://cloud.tenable.com/scanners/$ScannerId/agents/$AgentId"
    Invoke-TioRequest -Uri $uri -Headers $Headers -Context 'AgentDetail'
}

function Get-TioAgentGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScannerId,
        [Parameter(Mandatory)][hashtable]$Headers
    )

    $uri  = "https://cloud.tenable.com/scanners/$ScannerId/agent-groups"
    $resp = Invoke-TioRequest -Uri $uri -Headers $Headers -Context 'AgentGroups'

    if ($null -eq $resp) { return @() }
    @($resp.groups)
}

function Get-TioAgentGroupMembers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScannerId,
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter()][ValidateRange(1,5000)][int]$Limit = 5000
    )

    $offset = 0
    $allMembers = New-Object System.Collections.Generic.List[object]

    while ($true) {
        $uri  = "https://cloud.tenable.com/scanners/$ScannerId/agent-groups/$GroupId/agents?limit=$Limit&offset=$offset"
        $resp = Invoke-TioRequest -Uri $uri -Headers $Headers -Context 'AgentGroupMembers'

        if ($null -eq $resp) { break }

        $chunk = @($resp.agents)
        foreach ($m in $chunk) { [void]$allMembers.Add($m) }

        if ($chunk.Count -lt $Limit) { break }
        $offset += $Limit
    }

    $allMembers
}

# -------------------------
# Main
# -------------------------

Ensure-Directory -Path $OutDir
$resolvedApiKeys = Resolve-ExportTioApiKeys -AccessKey $AccessKey -SecretKey $SecretKey
$AccessKey = $resolvedApiKeys.AccessKey
$SecretKey = $resolvedApiKeys.SecretKey
$headers = New-TioHeaders -AccessKey $AccessKey -SecretKey $SecretKey

# Reset per-run skipped list so repeated invocations in the same session do not leak state.
$script:Skipped404 = New-Object System.Collections.Generic.List[object]

if ($IsDetailMode -and -not $isDetailTestRun) {
    Write-Warning "Detail mode without -DetailTest will run per-agent detail calls for ALL agents."
}

$agents = @()
$agentToGroups = @{}

$baseName = "TioAgentInventory_{0}_Scanner{1}" -f $Mode, $ScannerId
if ($isDetailTestRun) { $baseName += "_DETAILTEST$SampleSize" }

$outCsv     = Join-Path $OutDir ($baseName + '.csv')
$outRaw     = Join-Path $OutDir ($baseName + '_RAW.jsonl')
$skippedCsv = Join-Path $OutDir ($baseName + '_Skipped404.csv')
$summaryJs  = Join-Path $OutDir ($baseName + '_RunSummary.json')

$runStart = Get-Date

try {
    # Step 1: agent list
    $agents = @(Get-TioAgents -ScannerId $ScannerId -Headers $headers -Limit $Limit)

    if ($isDetailTestRun) {
        $agents = @($agents | Select-Object -First $SampleSize)
    }

    Write-ProgressVerbose -Banner -Total $agents.Count -RunMode $Mode -OutFile $outCsv -IsDetailTestRun:$isDetailTestRun -SampleSize $SampleSize

    # Step 2: detail enrichment
    $enrichedCount = 0
    if ($IsDetailMode) {
        $i = 0
        foreach ($agent in $agents) {
            $i++
            $agentIdInt = [int]$agent.id

            $agentDetail = Get-TioAgentDetails -ScannerId $ScannerId -AgentId $agentIdInt -Headers $headers

            if ($null -ne $agentDetail) {
                foreach ($p in $agentDetail.PSObject.Properties) {
                    $agent | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
                }
                $enrichedCount++
            } else {
                # 404 skipped; keep base agent record
            }

            $every = if ($isDetailTestRun) { 1 } else { 250 }
            Write-ProgressVerbose -Index $i -TotalProgress $agents.Count -AgentId $agentIdInt -HostName $agent.name -Every $every

            if ($ThrottleMs -gt 0) { Start-Sleep -Milliseconds $ThrottleMs }
        }
    }

    # Step 3: group resolution (scanner-scoped)
    $groups = Get-TioAgentGroups -ScannerId $ScannerId -Headers $headers

    $sampleIdSet = $null
    if ($isDetailTestRun) {
        $sampleIdSet = New-Object 'System.Collections.Generic.HashSet[int]'
        foreach ($id in ($agents | ForEach-Object { [int]$_.id })) { [void]$sampleIdSet.Add($id) }
    }

    foreach ($grp in $groups) {
        if ($null -eq $grp -or $null -eq $grp.id) { continue }

        $members = Get-TioAgentGroupMembers -ScannerId $ScannerId -GroupId ([string]$grp.id) -Headers $headers -Limit $Limit
        foreach ($mem in $members) {
            $mid = [int]$mem.id
            if ($isDetailTestRun -and -not $sampleIdSet.Contains($mid)) { continue }

            if (-not $agentToGroups.ContainsKey($mid)) { $agentToGroups[$mid] = @() }
            $agentToGroups[$mid] += $grp.name
        }
    }

    # Raw detail export: every property on each enriched agent object (Detail / DetailTest)
    if ($IsDetailMode -and $ExportRawDetail) {
        Export-RawDetailJsonl -Agents $agents -Path $outRaw
        Write-Host "Raw detail export complete: $outRaw"
    }

    # Report CSV export: use flattened format in Detail mode, scalar format in Fast mode
    $exportFunction = if ($IsDetailMode) { 'ConvertTo-FlattenedTioExportRecord' } else { 'ConvertTo-TioExportRecord' }
    $agents |
        ForEach-Object { & $exportFunction -Agent $_ -AgentToGroups $agentToGroups } |
        Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8

    Write-Host "CSV export complete: $outCsv"

    # Skipped 404 report
    if (Get-Variable -Name Skipped404 -Scope Script -ErrorAction SilentlyContinue) {
        if ($script:Skipped404.Count -gt 0) {
            Export-Skipped404Csv -Skipped @($script:Skipped404) -Path $skippedCsv
            Write-Host "Skipped 404 report written: $skippedCsv"
        }
    }

    # Run summary
    $runEnd = Get-Date
    $skipped404Count = if (Get-Variable -Name Skipped404 -Scope Script -ErrorAction SilentlyContinue) { $script:Skipped404.Count } else { 0 }

    $summary = @{
        ScannerId        = $ScannerId
        Mode             = $Mode
        DetailTest       = $isDetailTestRun
        SampleSize       = $(if ($isDetailTestRun) { $SampleSize } else { $null })
        TotalAgents      = $agents.Count
        EnrichedCount    = $enrichedCount
        Skipped404Count  = $skipped404Count
        ExportedCsv      = $outCsv
        ExportedRawJsonl = $(if ($IsDetailMode -and $ExportRawDetail) { $outRaw } else { $null })
        StartedAt        = $runStart.ToString('s')
        EndedAt          = $runEnd.ToString('s')
        DurationSeconds  = [int]($runEnd - $runStart).TotalSeconds
    }

    Export-RunSummaryJson -Summary $summary -Path $summaryJs
    Write-Host "Run summary written: $summaryJs"
}
catch {
    # Log the original error BEFORE any cleanup so it is always visible
    Write-Warning "Export failed: $($_.Exception.Message)"
    Write-Warning "At: $($_.InvocationInfo.PositionMessage)"

    # Optional nice-to-have: produce partial JSONL + partial report CSV on crash
    Export-PartialArtifacts -OutDir $OutDir -BaseName $baseName -Agents $agents -AgentToGroups $agentToGroups -IsDetailMode $IsDetailMode

    # Also write Skipped404 if any exist even on failure
    if (Get-Variable -Name Skipped404 -Scope Script -ErrorAction SilentlyContinue) {
        if ($script:Skipped404.Count -gt 0) {
            Export-Skipped404Csv -Skipped @($script:Skipped404) -Path $skippedCsv
            Write-Warning "Skipped 404 report written (failure path): $skippedCsv"
        }
    }

    throw
}

# Fast (contains group info)
# .\Export-TIOAgents.ps1 -ScannerId 1 -OutDir C:\Temp\Tenable -AccessKey $ak -SecretKey $sk -Mode Fast
# .\Invoke-RestoreNessusAgent.ps1 -CsvPath C:\Temp\Tenable\TioAgentInventory_Fast_Scanner1.csv -Key '<LINKING_KEY>'

## Detail
# .\Export-TIOAgents.ps1 -ScannerId 1 -OutDir C:\Temp\Tenable -AccessKey $ak -SecretKey $sk -Mode Detail