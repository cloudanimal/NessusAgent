function Get-NessusAgentGroupFromCsv {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$CsvPath,

        [Parameter()]
        [string]$ComputerName = $env:COMPUTERNAME
    )

    $resolvedCsvPath = Resolve-NessusAgentCsvPath -CsvPath $CsvPath
    $rows = @(Import-Csv -LiteralPath $resolvedCsvPath)
    if (-not $rows) {
        throw "CSV file '$resolvedCsvPath' did not contain any rows."
    }

    $nameColumns = @(
        'name',
        'agent name',
        'hostname',
        'host name',
        'dns name',
        'dns',
        'computername',
        'computer name',
        'netbios name',
        'netbios'
    )

    $groupColumns = @(
        'groups',
        'group',
        'agent groups',
        'agent group'
    )

    $normalizedComputerName = $ComputerName.Trim().ToLowerInvariant()
    $match = $null

    foreach ($row in $rows) {
        foreach ($property in $row.PSObject.Properties) {
            $propertyName = $property.Name.Trim().ToLowerInvariant()
            if ($propertyName -notin $nameColumns) {
                continue
            }

            $candidateValue = [string]$property.Value
            if ([string]::IsNullOrWhiteSpace($candidateValue)) {
                continue
            }

            $candidateNames = @(
                $candidateValue.Trim().ToLowerInvariant()
            )

            if ($candidateValue.Contains('.')) {
                $candidateNames += $candidateValue.Split('.')[0].Trim().ToLowerInvariant()
            }

            if ($normalizedComputerName -in $candidateNames) {
                $match = $row
                break
            }
        }

        if ($match) {
            break
        }
    }

    if (-not $match) {
        throw "Could not find computer '$ComputerName' in CSV file '$resolvedCsvPath'."
    }

    $groupValue = $null
    foreach ($property in $match.PSObject.Properties) {
        $propertyName = $property.Name.Trim().ToLowerInvariant()
        if ($propertyName -in $groupColumns) {
            $groupValue = [string]$property.Value
            if (-not [string]::IsNullOrWhiteSpace($groupValue)) {
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($groupValue)) {
        throw "Could not find a group value for computer '$ComputerName' in CSV file '$resolvedCsvPath'."
    }

    [pscustomobject]@{
        ComputerName = $ComputerName
        CsvPath = $resolvedCsvPath
        Group = $groupValue.Trim()
        Row = $match
    }
}
