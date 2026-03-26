function Resolve-NessusAgentCsvPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$CsvPath
    )

    if ($CsvPath) {
        if (-not (Test-Path -LiteralPath $CsvPath)) {
            throw "CSV file was not found at '$CsvPath'."
        }

        return $CsvPath
    }

    $searchRoot = Split-Path -Parent $PSScriptRoot
    $csvFile = Get-ChildItem -LiteralPath $searchRoot -Filter '*.csv' -File | Select-Object -First 1
    if (-not $csvFile) {
        throw "No CSV file was found in '$searchRoot'."
    }

    $csvFile.FullName
}
