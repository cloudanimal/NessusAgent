function Resolve-NessusCliPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = 'C:\Program Files\Tenable\Nessus Agent\nessuscli.exe'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "nessuscli.exe was not found at '$Path'."
    }

    $Path
}
