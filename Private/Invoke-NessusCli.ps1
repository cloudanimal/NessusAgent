function Invoke-NessusCli {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe',

        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    $resolvedPath = Resolve-NessusCliPath -Path $Path
    $rawLines = @(& $resolvedPath @ArgumentList 2>&1)
    $exitCode = $LASTEXITCODE

    [pscustomobject]@{
        Path = $resolvedPath
        ArgumentList = @($ArgumentList)
        ExitCode = $exitCode
        Output = @($rawLines)
        OutputText = ($rawLines -join [Environment]::NewLine)
    }
}
