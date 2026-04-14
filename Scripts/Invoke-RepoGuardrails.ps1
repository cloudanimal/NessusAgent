[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Invoke-RepoGit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]]$Arguments
    )

    & git @Arguments
}

function Invoke-RepoGuardrails {
    [CmdletBinding()]
    param()

    if ($env:BYPASS_REPO_GUARD -eq '1') {
        Write-Host 'Repo guard bypassed by BYPASS_REPO_GUARD=1'
        return 0
    }

    $patterns = @(
        @{ Name = 'Internal IPv4'; Regex = '\b(?:10\.(?:\d{1,3}\.){2}\d{1,3}|192\.168\.(?:\d{1,3})\.(?:\d{1,3})|172\.(?:1[6-9]|2\d|3[0-1])\.(?:\d{1,3})\.(?:\d{1,3}))\b' },
        @{ Name = 'Potential API key assignment'; Regex = '(?i)\b(?:access|secret)[-_ ]?key\b\s*[:=]\s*[A-Za-z0-9]{16,}' },
        @{ Name = 'X-ApiKeys header'; Regex = '(?i)X-ApiKeys\s*["'']?\s*[:=]' },
        @{ Name = 'Internal host naming pattern'; Regex = '(?i)\b[A-Z]{2,6}-[A-Z0-9]{3,}\b' },
        @{ Name = 'Internal FQDN pattern'; Regex = '(?i)\b[a-z0-9-]+\.(?:corp|local|internal|lan)\b' }
    )

    $stagedFiles = @(Invoke-RepoGit @('diff', '--cached', '--name-only', '--diff-filter=ACMR'))
    if ($stagedFiles.Count -eq 0) {
        return 0
    }

    $skipPaths = @(
        '.githooks/pre-commit',
        'Scripts/Invoke-RepoGuardrails.ps1',
        'Tests/Invoke-RepoGuardrails.Tests.ps1'
    )

    $violations = New-Object System.Collections.Generic.List[string]

    foreach ($path in $stagedFiles) {
        if (-not $path) { continue }
        if ($skipPaths -contains $path) { continue }

        $ext = [System.IO.Path]::GetExtension($path)
        if ($ext -in @('.png','.jpg','.jpeg','.gif','.webp','.pdf','.zip','.exe','.dll','.pfx','.cer')) {
            continue
        }

        $diffLines = @(Invoke-RepoGit @('diff', '--cached', '--unified=0', '--', $path))
        if ($diffLines.Count -eq 0) { continue }

        $addedLines = @($diffLines | Where-Object { $_ -like '+*' -and $_ -notlike '+++*' } | ForEach-Object { $_.Substring(1) })
        if ($addedLines.Count -eq 0) { continue }

        $addedContent = ($addedLines -join [Environment]::NewLine)

        foreach ($p in $patterns) {
            if ($addedContent -match $p.Regex) {
                $violations.Add($path + ' -> ' + $p.Name) | Out-Null
            }
        }
    }

    if ($violations.Count -gt 0) {
        Write-Host ''
        Write-Host 'Commit blocked by repo guard.' -ForegroundColor Red
        Write-Host 'Potential sensitive content detected in staged changes:' -ForegroundColor Yellow
        $violations | Sort-Object -Unique | ForEach-Object { Write-Host (' - ' + $_) }
        Write-Host ''
        Write-Host 'Remove or mask sensitive values, then commit again.' -ForegroundColor Yellow
        Write-Host 'If this is a false positive, set BYPASS_REPO_GUARD=1 for one commit.' -ForegroundColor Yellow
        return 1
    }

    return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-RepoGuardrails)
}
