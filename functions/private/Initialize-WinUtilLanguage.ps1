function Initialize-WinUtilLanguage {
    <#
    .SYNOPSIS
        Loads the interface language and returns the window XAML in that language.

    .DESCRIPTION
        The language is -Language, else $env:WINUTIL_LANG, else 'tr', and is kept in
        $sync.preferences.language. 'en' loads nothing: Get-WinUtilText then passes every string
        through, and the XAML comes back exactly as it was given.

        Any other language reads each embedded part for it ('tr' and 'tr.*' in
        $sync.configs.translations, in ordinal order) and then:
        - fills $sync.configs.uitext, exact English to translated text with the first pair
          winning, and $sync.configs.uipatterns, the ordered rewrites Get-WinUtilText tries next;
        - rewrites config Content, Description and ComboDescriptions values in place, but only
          where the value is still the English the pair was written for, so text that changed
          since stays English instead of showing an outdated translation;
        - translates the window XAML. TabItem headers stay English because Invoke-WPFTab
          switches on them, and ComboBoxItem content stays as it is because it holds registry
          state values.

        A stage that fails is logged and leaves its part in English, so the window always loads.

    .PARAMETER Xaml
        The window XAML as text.

    .PARAMETER Language
        A language code such as 'tr' or 'en'. Empty means $env:WINUTIL_LANG, then 'tr'.

    .OUTPUTS
        System.String. The XAML to load.

    .EXAMPLE
        $inputXML = Initialize-WinUtilLanguage -Xaml $inputXML -Language $Language
    #>
    param(
        [string]$Xaml,
        [string]$Language
    )

    if ($null -eq $sync) {
        return $Xaml
    }

    $code = $Language
    if ([string]::IsNullOrWhiteSpace($code)) {
        $code = $env:WINUTIL_LANG
    }
    if ([string]::IsNullOrWhiteSpace($code)) {
        $code = "tr"
    }
    $code = $code.Trim().ToLowerInvariant()

    if ($null -eq $sync.preferences) {
        $sync.preferences = @{}
    }
    $sync.preferences.language = $code

    # Start from no table, so a later call for 'en' leaves nothing of an earlier language behind
    if ($null -ne $sync.configs) {
        $sync.configs.uitext = $null
        $sync.configs.uipatterns = $null
    }

    if ($code -ceq "en") {
        return $Xaml
    }

    $partNames = New-Object 'System.Collections.Generic.List[string]'
    if ($null -ne $sync.configs -and $sync.configs.translations -is [System.Collections.IDictionary]) {
        foreach ($partName in $sync.configs.translations.Keys) {
            if ($partName -is [string] -and ($partName -ceq $code -or $partName.StartsWith("$code.", [StringComparison]::Ordinal))) {
                $partNames.Add($partName)
            }
        }
    }
    $partNames.Sort([StringComparer]::Ordinal)

    if ($partNames.Count -eq 0) {
        Write-WinUtilLog -Level "WARN" -Component "Language" -Message "No translations are embedded for language '$code'; the interface stays in English."
        $sync.preferences.language = "en"
        return $Xaml
    }

    # A pair is exactly [English, translation], two non-empty strings. Anything else is skipped.
    $isPair = {
        param($pair)
        $pair -is [array] -and $pair.Count -eq 2 -and
            $pair[0] -is [string] -and $pair[0].Length -gt 0 -and
            $pair[1] -is [string] -and $pair[1].Length -gt 0
    }

    $parts = New-Object 'System.Collections.Generic.List[object]'
    try {
        $uiText = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
        $uiPatterns = New-Object 'System.Collections.Generic.List[object]'

        foreach ($partName in $partNames) {
            $part = $sync.configs.translations[$partName]
            if ($part -isnot [System.Management.Automation.PSCustomObject]) {
                Write-WinUtilLog -Level "WARN" -Component "Language" -Message "Translation part '$partName' is not a JSON object and was skipped."
                continue
            }
            $parts.Add($part)

            foreach ($pair in $part.ui) {
                if ((& $isPair $pair) -and -not $uiText.ContainsKey($pair[0])) {
                    $uiText.Add($pair[0], $pair[1])
                }
            }

            foreach ($pair in $part.patterns) {
                if (-not (& $isPair $pair)) {
                    continue
                }

                try {
                    $regex = New-Object regex($pair[0], [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
                    $uiPatterns.Add([pscustomobject]@{ Regex = $regex; Replacement = $pair[1] })
                } catch {
                    Write-WinUtilLog -Level "WARN" -Component "Language" -Message "Translation part '$partName' has an invalid pattern, skipped: $($pair[0])"
                }
            }
        }

        $sync.configs.uitext = $uiText
        $sync.configs.uipatterns = $uiPatterns
    } catch {
        Write-WinUtilLog -Level "WARN" -Component "Language" -Message "Could not load the '$code' translations; the interface stays in English: $($_.Exception.Message)"
        $sync.configs.uitext = $null
        $sync.configs.uipatterns = $null
        $sync.preferences.language = "en"
        return $Xaml
    }

    # Config text is patched in place. The applications and appx lookup tables main.ps1 builds
    # hold the same objects, so they read the translation too.
    $configNames = @("tweaks", "feature", "appx", "appnavigation", "applications")
    $applied = 0
    $stale = 0
    try {
        foreach ($part in $parts) {
            if ($part.configs -isnot [System.Management.Automation.PSCustomObject]) {
                continue
            }

            foreach ($configProperty in $part.configs.PSObject.Properties) {
                $configName = $configProperty.Name
                if ($configProperty.Value -isnot [System.Management.Automation.PSCustomObject]) {
                    continue
                }

                $target = $null
                if ($configNames -ccontains $configName) {
                    $target = $sync.configs[$configName]
                }

                foreach ($entryProperty in $configProperty.Value.PSObject.Properties) {
                    if ($entryProperty.Value -isnot [System.Management.Automation.PSCustomObject]) {
                        continue
                    }

                    # Compiled application keys carry the WPFInstall prefix; lang files use the source key
                    $entryKey = $entryProperty.Name
                    if ($configName -ceq "applications" -and -not $entryKey.StartsWith("WPFInstall", [StringComparison]::Ordinal)) {
                        $entryKey = "WPFInstall$entryKey"
                    }

                    $entry = $null
                    if ($target -is [System.Management.Automation.PSCustomObject]) {
                        $entryMatch = $target.PSObject.Properties[$entryKey]
                        if ($null -ne $entryMatch -and $entryMatch.Name -ceq $entryKey) {
                            $entry = $entryMatch.Value
                        }
                    }

                    foreach ($fieldProperty in $entryProperty.Value.PSObject.Properties) {
                        $fieldName = $fieldProperty.Name
                        $field = $null
                        if ($entry -is [System.Management.Automation.PSCustomObject]) {
                            $field = $entry.PSObject.Properties[$fieldName]
                        }

                        if ([string]::Equals($fieldName, "ComboDescriptions", [StringComparison]::OrdinalIgnoreCase)) {
                            if ($fieldProperty.Value -isnot [System.Management.Automation.PSCustomObject]) {
                                continue
                            }

                            $combos = $null
                            if ($null -ne $field -and $field.Value -is [System.Management.Automation.PSCustomObject]) {
                                $combos = $field.Value
                            }

                            # The keys are ComboItem values and are never translated, only the text
                            foreach ($comboProperty in $fieldProperty.Value.PSObject.Properties) {
                                $pair = $comboProperty.Value
                                if (-not (& $isPair $pair)) {
                                    continue
                                }

                                $combo = $null
                                if ($null -ne $combos) {
                                    $combo = $combos.PSObject.Properties[$comboProperty.Name]
                                }

                                if ($null -ne $combo -and $combo.Name -ceq $comboProperty.Name -and $combo.Value -is [string] -and $combo.Value -ceq $pair[0]) {
                                    $combo.Value = $pair[1]
                                    $applied++
                                } else {
                                    $stale++
                                }
                            }
                            continue
                        }

                        # Content and Description only: category, ComboItems and the rest are data
                        if (-not ([string]::Equals($fieldName, "Content", [StringComparison]::OrdinalIgnoreCase) -or
                                [string]::Equals($fieldName, "Description", [StringComparison]::OrdinalIgnoreCase))) {
                            continue
                        }

                        $pair = $fieldProperty.Value
                        if (-not (& $isPair $pair)) {
                            continue
                        }

                        if ($null -ne $field -and $field.Value -is [string] -and $field.Value -ceq $pair[0]) {
                            $field.Value = $pair[1]
                            $applied++
                        } else {
                            $stale++
                        }
                    }
                }
            }
        }

        Write-WinUtilLog -Component "Language" -Message "Language '$code': $($parts.Count) part(s), $($uiText.Count) text(s), $($uiPatterns.Count) pattern(s); config text applied $applied, stale $stale."
    } catch {
        Write-WinUtilLog -Level "WARN" -Component "Language" -Message "Could not translate the '$code' config text: $($_.Exception.Message)"
    }

    try {
        [xml]$document = $Xaml
        $translated = $null

        foreach ($attribute in @($document.SelectNodes("//@*[local-name()='Content' or local-name()='Text' or local-name()='ToolTip' or local-name()='Header' or local-name()='Title']"))) {
            $value = $attribute.get_Value()
            if ($value.StartsWith("{", [StringComparison]::Ordinal)) {
                continue
            }

            $attributeName = $attribute.get_LocalName()
            $ownerName = $attribute.get_OwnerElement().get_LocalName()
            if (($ownerName -ceq "TabItem" -and $attributeName -ceq "Header") -or ($ownerName -ceq "ComboBoxItem" -and $attributeName -ceq "Content")) {
                continue
            }

            if ($uiText.TryGetValue($value, [ref]$translated)) {
                # A leading brace would make XAML read the text as a markup extension
                if ($translated.StartsWith("{", [StringComparison]::Ordinal)) {
                    $translated = "{}$translated"
                }
                $attribute.set_Value($translated)
            }
        }

        # An access-key label is text with one underlined letter, as in <Underline>I</Underline>nstall.
        # It is looked up as a whole, so its pieces are left to the loop after this one.
        $labelTest = "*[local-name()='Underline'] and count(*) = 1 and text()[normalize-space()]"

        foreach ($textNode in @($document.SelectNodes("//text()"))) {
            $parent = $textNode.get_ParentNode()
            $parentName = $parent.get_LocalName()
            if ($parentName -ceq "ComboBoxItem" -or $parentName -ceq "TabItem.Header") {
                continue
            }
            if ($null -ne $parent.SelectSingleNode("self::*[$labelTest]") -or
                ($parentName -ceq "Underline" -and $null -ne $parent.SelectSingleNode("parent::*[$labelTest]"))) {
                continue
            }

            $value = $textNode.get_Value()
            $trimmed = $value.Trim()
            if ($trimmed.Length -gt 0 -and $uiText.TryGetValue($trimmed, [ref]$translated)) {
                $leading = $value.Substring(0, $value.Length - $value.TrimStart().Length)
                $trailing = $value.Substring($value.TrimEnd().Length)
                $textNode.set_Value($leading + $translated + $trailing)
            }
        }

        foreach ($label in @($document.SelectNodes("//*[$labelTest]"))) {
            if ($label.get_LocalName() -ceq "ComboBoxItem" -or -not $uiText.TryGetValue($label.get_InnerText().Trim(), [ref]$translated)) {
                continue
            }

            $underline = $label.SelectSingleNode("*[local-name()='Underline']")
            $letter = $underline.get_InnerText().Trim()
            while ($label.get_HasChildNodes()) {
                [void]$label.RemoveChild($label.get_FirstChild())
            }

            # Underline the same letter when the translation has it, otherwise show plain text
            $index = -1
            if ($letter.Length -gt 0) {
                $index = $translated.IndexOf($letter, [StringComparison]::OrdinalIgnoreCase)
            }
            if ($index -lt 0) {
                [void]$label.AppendChild($document.CreateTextNode($translated))
                continue
            }

            if ($index -gt 0) {
                [void]$label.AppendChild($document.CreateTextNode($translated.Substring(0, $index)))
            }
            $newUnderline = $document.CreateElement($underline.get_Prefix(), $underline.get_LocalName(), $underline.get_NamespaceURI())
            [void]$newUnderline.AppendChild($document.CreateTextNode($translated.Substring($index, $letter.Length)))
            [void]$label.AppendChild($newUnderline)
            if ($index + $letter.Length -lt $translated.Length) {
                [void]$label.AppendChild($document.CreateTextNode($translated.Substring($index + $letter.Length)))
            }
        }

        return $document.OuterXml
    } catch {
        Write-WinUtilLog -Level "WARN" -Component "Language" -Message "Could not translate the window; it stays in English: $($_.Exception.Message)"
        return $Xaml
    }
}
