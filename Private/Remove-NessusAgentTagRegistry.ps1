function Remove-NessusAgentTagRegistry {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param()

    $isWindowsPlatform = $env:OS -eq 'Windows_NT'
    if (-not $isWindowsPlatform) {
        return $null
    }

    $tagRegistryPath = 'HKLM:\SOFTWARE\Tenable\TAG'
    if (-not (Test-Path -LiteralPath $tagRegistryPath)) {
        return [pscustomobject]@{
            Path = $tagRegistryPath
            Removed = $false
            Result = 'NotFound'
        }
    }

    if ($PSCmdlet.ShouldProcess($tagRegistryPath, 'Remove Tenable TAG registry key before relink')) {
        Remove-Item -LiteralPath $tagRegistryPath -Recurse -Force -ErrorAction Stop
        return [pscustomobject]@{
            Path = $tagRegistryPath
            Removed = $true
            Result = 'Removed'
        }
    }

    [pscustomobject]@{
        Path = $tagRegistryPath
        Removed = $false
        Result = 'Skipped'
    }
}
