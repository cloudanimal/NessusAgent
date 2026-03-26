function ConvertTo-NessusDateTime {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $parsed = $null
    if ([datetime]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$parsed)) {
        return $parsed
    }

    if ([datetime]::TryParse($Value, [System.Globalization.CultureInfo]::CurrentCulture, [System.Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$parsed)) {
        return $parsed
    }

    return $null
}
