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

    if ($Value -match '^\d+$') {
        $epoch = [datetime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
        return $epoch.AddSeconds([long]$Value).ToLocalTime()
    }

    try {
        return [datetime]::Parse($Value)
    }
    catch {
        return $null
    }
}
