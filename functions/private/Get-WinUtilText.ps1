function Get-WinUtilText {
    <#
    .SYNOPSIS
        Returns the interface text for an English string, in the language WinUtil started in.

    .DESCRIPTION
        Looks the text up in the exact table Initialize-WinUtilLanguage builds in
        $sync.configs.uitext. Without an exact entry, the first pattern in
        $sync.configs.uipatterns that matches rewrites it. Otherwise the text comes back
        unchanged, as it does whenever no table is loaded: English, headless runs and tests.

        It never logs and never throws, so any display site can call it.

    .PARAMETER Text
        The English text. Anything that is not a non-empty string is returned as it is.

    .EXAMPLE
        $statusText = Get-WinUtilText $statusText
    #>
    param(
        [Parameter(Position = 0)]
        $Text
    )

    # The comma keeps an array from being unrolled on the way out, and $null stays $null
    if ($Text -isnot [string] -or $Text.Length -eq 0) {
        return ,$Text
    }

    try {
        $uiText = $sync.configs.uitext
        if ($null -eq $uiText) {
            return $Text
        }

        $translated = $null
        if ($uiText.TryGetValue($Text, [ref]$translated)) {
            return $translated
        }

        foreach ($pattern in $sync.configs.uipatterns) {
            if ($pattern.Regex.IsMatch($Text)) {
                return $pattern.Regex.Replace($Text, $pattern.Replacement)
            }
        }
    } catch {
        # The English text is always a valid answer, so a display site never fails over its text
        $null = $_
    }

    return $Text
}
