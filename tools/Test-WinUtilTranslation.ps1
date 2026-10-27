<#
.SYNOPSIS
    Checks the WinUtil translation files in lang/ against the current sources.

.DESCRIPTION
    A maintainer tool. Compile.ps1 does not read tools/*.ps1, so this script is never part
    of winutil.ps1.

    It reads the five translatable configs in config/, xaml/inputXML.xaml and the files
    lang/<Language>.json and lang/<Language>.*.json, all as UTF-8, and reports:
    - shape errors: a file that does not parse, a root that is not an object, an unknown
      top-level member, a ui or patterns item that is not a pair of two non-empty strings,
      a pattern that does not compile, an unknown config name, an entry that is not an
      object, and a field the config does not translate. Field names are case-sensitive,
      exactly as in the source;
    - unknown keys: entry keys that config/<name>.json does not have, compared without the
      WPFInstall prefix for applications, and ComboDescriptions keys the entry does not have;
    - stale pairs: config pairs whose English side is no longer -ceq the current source
      value, so the overlay leaves that text in English;
    - missing translations: the coverage of every translatable config field, and the window
      strings the overlay looks up that have no ui pair;
    - conflicts: the same English (ui), pattern (patterns) or config text paired with a
      different translation. Only the first pair is ever used.

    It prints a summary and returns a [pscustomobject] with the lists.

.PARAMETER Language
    The language code in the lang file names. Default 'tr'.

.PARAMETER RepoRoot
    The repository root. Default: the parent folder of tools.

.PARAMETER Strict
    Exits with code 1 when there is any shape, unknown, stale or conflict error, and with 0
    when there is none.

.EXAMPLE
    .\tools\Test-WinUtilTranslation.ps1

.EXAMPLE
    .\tools\Test-WinUtilTranslation.ps1 -Language tr -Strict
#>
param(
    [string]$Language = 'tr',
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'

$code = 'tr'
if (-not [string]::IsNullOrWhiteSpace($Language)) {
    $code = $Language.Trim().ToLowerInvariant()
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath

# The fields Initialize-WinUtilLanguage may rewrite, per config, as the lang file format allows them
$configNames = @('tweaks', 'feature', 'appx', 'appnavigation', 'applications')
$translatableFields = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
$translatableFields['tweaks'] = [string[]]@('Content', 'Description', 'ComboDescriptions')
$translatableFields['feature'] = [string[]]@('Content', 'Description')
$translatableFields['appx'] = [string[]]@('Description')
$translatableFields['appnavigation'] = [string[]]@('Content', 'Description')
$translatableFields['applications'] = [string[]]@('description')

# Window text that must stay English: Invoke-WinUtilISO.ps1 compares the Win11 Creator status box with it
$keepEnglish = [string[]]@('Ready. Please select a Windows 11 ISO to begin.')

$files = New-Object 'System.Collections.Generic.List[string]'
$shapeErrors = New-Object 'System.Collections.Generic.List[object]'
$unknownKeys = New-Object 'System.Collections.Generic.List[object]'
$stalePairs = New-Object 'System.Collections.Generic.List[object]'
$conflicts = New-Object 'System.Collections.Generic.List[object]'
$coverage = New-Object 'System.Collections.Generic.List[object]'
$missingConfig = New-Object 'System.Collections.Generic.List[object]'
$missingXaml = New-Object 'System.Collections.Generic.List[string]'

$newIssue = {
    param([string]$File, [string]$Location, [string]$Message)

    [pscustomobject]@{
        File     = $File
        Location = $Location
        Message  = $Message
    }
}

# A pair is exactly [English, translation], two non-empty strings, as Initialize-WinUtilLanguage reads it
$isPair = {
    param($Pair)

    $Pair -is [array] -and $Pair.Count -eq 2 -and
        $Pair[0] -is [string] -and $Pair[0].Length -gt 0 -and
        $Pair[1] -is [string] -and $Pair[1].Length -gt 0
}

# The property with exactly this name, or $null. PSObject lookups alone ignore case.
$getProperty = {
    param($Object, [string]$Name)

    if ($Object -is [System.Management.Automation.PSCustomObject]) {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -ne $property -and $property.Name -ceq $Name) {
            return $property
        }
    }
    return $null
}

$sources = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
foreach ($configName in $configNames) {
    $configPath = Join-Path (Join-Path $RepoRoot 'config') "$configName.json"
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Config file not found: $configPath"
    }

    $entries = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entryProperty in $config.PSObject.Properties) {
        $entries[$entryProperty.Name] = $entryProperty.Value
    }
    $sources[$configName] = $entries
}

$uiPairs = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
$patternPairs = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
$configPairs = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)

# Keeps the first pair for a key and reports a later one that translates it differently
$addFirstPair = {
    param($Table, [string]$Key, $Pair, [string]$File, [string]$Location)

    $first = $null
    if ($Table.TryGetValue($Key, [ref]$first)) {
        if ($first.Translation -cne $Pair[1]) {
            $conflicts.Add((& $newIssue $File $Location "'$Key' is translated differently in $($first.File) $($first.Location); only that first pair is used"))
        }
        return
    }
    $Table.Add($Key, [pscustomobject]@{ Translation = $Pair[1]; File = $File; Location = $Location })
}

# Checks a config pair against the source text and keeps it under its target for coverage and conflicts
$checkConfigPair = {
    param([string]$Target, $Current, $Pair, [string]$File, [string]$Location)

    if (-not ($Current -is [string] -and $Current -ceq $Pair[0])) {
        $stalePairs.Add([pscustomobject]@{
            File     = $File
            Location = $Location
            Message  = 'the English side is not the current source text, so this text stays English'
            English  = $Pair[0]
            Current  = $Current
        })
    }

    $records = $null
    if (-not $configPairs.TryGetValue($Target, [ref]$records)) {
        $records = New-Object 'System.Collections.Generic.List[object]'
        $configPairs.Add($Target, $records)
    }
    foreach ($record in $records) {
        if ($record.English -ceq $Pair[0] -and $record.Translation -cne $Pair[1]) {
            $conflicts.Add((& $newIssue $File $Location "the same English is translated differently in $($record.File) $($record.Location); only the first pair is used"))
            break
        }
    }
    $records.Add([pscustomobject]@{ English = $Pair[0]; Translation = $Pair[1]; File = $File; Location = $Location })
}

# The parts Initialize-WinUtilLanguage loads for this language, in the same ordinal order
$langRoot = Join-Path $RepoRoot 'lang'
$partNames = New-Object 'System.Collections.Generic.List[string]'
$partFiles = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
if (Test-Path -LiteralPath $langRoot -PathType Container) {
    foreach ($langFile in @(Get-ChildItem -LiteralPath $langRoot -Filter '*.json' -File)) {
        $baseName = $langFile.BaseName
        if ($baseName -ceq $code -or $baseName.StartsWith("$code.", [StringComparison]::Ordinal)) {
            $partNames.Add($baseName)
            $partFiles[$baseName] = $langFile
        }
    }
}
$partNames.Sort([StringComparer]::Ordinal)
if ($partNames.Count -eq 0) {
    throw "No translation files for '$code' in $langRoot; expected $code.json or $code.*.json."
}

foreach ($partName in $partNames) {
    $langFile = $partFiles[$partName]
    $fileName = $langFile.Name
    $files.Add($fileName)

    try {
        $part = Get-Content -LiteralPath $langFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $shapeErrors.Add((& $newIssue $fileName '' "does not parse as JSON: $($_.Exception.Message)"))
        continue
    }

    if ($part -isnot [System.Management.Automation.PSCustomObject]) {
        $shapeErrors.Add((& $newIssue $fileName '' 'the root is not a JSON object'))
        continue
    }

    foreach ($member in $part.PSObject.Properties) {
        $memberName = $member.Name

        if ($memberName -ceq 'ui' -or $memberName -ceq 'patterns') {
            $items = $member.Value
            if ($items -isnot [array]) {
                $shapeErrors.Add((& $newIssue $fileName $memberName 'is not an array of pairs'))
                continue
            }

            for ($index = 0; $index -lt $items.Count; $index++) {
                $pair = $items[$index]
                $location = "$memberName[$index]"
                if (-not (& $isPair $pair)) {
                    $shapeErrors.Add((& $newIssue $fileName $location 'is not a pair of two non-empty strings'))
                    continue
                }

                if ($memberName -ceq 'ui') {
                    & $addFirstPair $uiPairs $pair[0] $pair $fileName $location
                    continue
                }

                try {
                    $null = New-Object regex($pair[0], [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
                } catch {
                    $shapeErrors.Add((& $newIssue $fileName $location "the pattern does not compile: $($_.Exception.Message)"))
                    continue
                }
                & $addFirstPair $patternPairs $pair[0] $pair $fileName $location
            }
            continue
        }

        if ($memberName -cne 'configs') {
            $shapeErrors.Add((& $newIssue $fileName $memberName 'is not a known member; use ui, patterns or configs'))
            continue
        }

        if ($member.Value -isnot [System.Management.Automation.PSCustomObject]) {
            $shapeErrors.Add((& $newIssue $fileName 'configs' 'is not an object'))
            continue
        }

        foreach ($configProperty in $member.Value.PSObject.Properties) {
            $configName = $configProperty.Name
            $configLocation = "configs.$configName"
            if (-not $sources.ContainsKey($configName)) {
                $shapeErrors.Add((& $newIssue $fileName $configLocation "is not a translatable config; use $($configNames -join ', ')"))
                continue
            }
            if ($configProperty.Value -isnot [System.Management.Automation.PSCustomObject]) {
                $shapeErrors.Add((& $newIssue $fileName $configLocation 'is not an object'))
                continue
            }

            $allowedFields = [string[]]$translatableFields[$configName]
            foreach ($entryProperty in $configProperty.Value.PSObject.Properties) {
                $entryKey = $entryProperty.Name
                $entryLocation = "$configLocation.$entryKey"
                if ($entryProperty.Value -isnot [System.Management.Automation.PSCustomObject]) {
                    $shapeErrors.Add((& $newIssue $fileName $entryLocation 'is not an object'))
                    continue
                }

                # Lang files use the source key; only the compiled applications keys carry the WPFInstall prefix
                $sourceKey = $entryKey
                if ($configName -ceq 'applications' -and $entryKey.StartsWith('WPFInstall', [StringComparison]::Ordinal)) {
                    $sourceKey = $entryKey.Substring(10)
                }
                $sourceEntry = $null
                $knownEntry = $sources[$configName].TryGetValue($sourceKey, [ref]$sourceEntry)
                if (-not $knownEntry) {
                    $unknownKeys.Add((& $newIssue $fileName $entryLocation "config/$configName.json has no entry '$sourceKey'"))
                }

                foreach ($fieldProperty in $entryProperty.Value.PSObject.Properties) {
                    $fieldName = $fieldProperty.Name
                    $fieldLocation = "$entryLocation.$fieldName"
                    if ([Array]::IndexOf($allowedFields, $fieldName) -lt 0) {
                        $shapeErrors.Add((& $newIssue $fileName $fieldLocation "is not a translatable field of $configName; use $($allowedFields -join ', ')"))
                        continue
                    }

                    $target = "$configName/$sourceKey/$fieldName"
                    if ($fieldName -ceq 'ComboDescriptions') {
                        if ($fieldProperty.Value -isnot [System.Management.Automation.PSCustomObject]) {
                            $shapeErrors.Add((& $newIssue $fileName $fieldLocation 'is not an object of pairs keyed by ComboItem value'))
                            continue
                        }

                        $sourceCombos = $null
                        if ($knownEntry) {
                            $sourceField = & $getProperty $sourceEntry $fieldName
                            if ($null -ne $sourceField) {
                                $sourceCombos = $sourceField.Value
                            }
                        }

                        foreach ($comboProperty in $fieldProperty.Value.PSObject.Properties) {
                            $comboLocation = "$fieldLocation.$($comboProperty.Name)"
                            $pair = $comboProperty.Value
                            if (-not (& $isPair $pair)) {
                                $shapeErrors.Add((& $newIssue $fileName $comboLocation 'is not a pair of two non-empty strings'))
                                continue
                            }
                            if (-not $knownEntry) {
                                continue
                            }

                            $sourceCombo = & $getProperty $sourceCombos $comboProperty.Name
                            if ($null -eq $sourceCombo) {
                                $unknownKeys.Add((& $newIssue $fileName $comboLocation "$sourceKey has no ComboDescriptions key '$($comboProperty.Name)'"))
                                continue
                            }
                            & $checkConfigPair "$target/$($comboProperty.Name)" $sourceCombo.Value $pair $fileName $comboLocation
                        }
                        continue
                    }

                    $pair = $fieldProperty.Value
                    if (-not (& $isPair $pair)) {
                        $shapeErrors.Add((& $newIssue $fileName $fieldLocation 'is not a pair of two non-empty strings'))
                        continue
                    }
                    if (-not $knownEntry) {
                        continue
                    }

                    $current = $null
                    $sourceField = & $getProperty $sourceEntry $fieldName
                    if ($null -ne $sourceField) {
                        $current = $sourceField.Value
                    }
                    & $checkConfigPair $target $current $pair $fileName $fieldLocation
                }
            }
        }
    }
}

$newCoverage = {
    param([string]$Config, [string]$Field, [int]$Total, [int]$Translated)

    $percent = 100.0
    if ($Total -gt 0) {
        $percent = [math]::Round(100.0 * $Translated / $Total, 1)
    }
    [pscustomobject]@{
        Config     = $Config
        Field      = $Field
        Translated = $Translated
        Total      = $Total
        Percent    = $percent
    }
}

$hasCurrentPair = {
    param([string]$Target, [string]$English)

    $records = $null
    if ($configPairs.TryGetValue($Target, [ref]$records)) {
        foreach ($record in $records) {
            if ($record.English -ceq $English) {
                return $true
            }
        }
    }
    return $false
}

foreach ($configName in $configNames) {
    foreach ($fieldName in [string[]]$translatableFields[$configName]) {
        $total = 0
        $translated = 0
        foreach ($entryKey in $sources[$configName].Keys) {
            $sourceField = & $getProperty $sources[$configName][$entryKey] $fieldName
            if ($null -eq $sourceField) {
                continue
            }

            # Each text is [field label, target, English]: the field itself, or each ComboDescriptions value
            $texts = New-Object 'System.Collections.Generic.List[object]'
            if ($fieldName -ceq 'ComboDescriptions') {
                if ($sourceField.Value -is [System.Management.Automation.PSCustomObject]) {
                    foreach ($comboProperty in $sourceField.Value.PSObject.Properties) {
                        $texts.Add(@("$fieldName.$($comboProperty.Name)", "$configName/$entryKey/$fieldName/$($comboProperty.Name)", $comboProperty.Value))
                    }
                }
            } else {
                $texts.Add(@($fieldName, "$configName/$entryKey/$fieldName", $sourceField.Value))
            }

            foreach ($text in $texts) {
                if ($text[2] -isnot [string] -or $text[2].Length -eq 0) {
                    continue
                }

                $total++
                if (& $hasCurrentPair $text[1] $text[2]) {
                    $translated++
                } else {
                    $missingConfig.Add([pscustomobject]@{ Config = $configName; Key = $entryKey; Field = $text[0]; English = $text[2] })
                }
            }
        }
        $coverage.Add((& $newCoverage $configName $fieldName $total $translated))
    }
}

# The window strings Initialize-WinUtilLanguage looks up, once each. Text without a letter
# (icon glyphs, numbers) and text that must stay English are left out.
$xamlPath = Join-Path (Join-Path $RepoRoot 'xaml') 'inputXML.xaml'
[xml]$document = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
$xamlTexts = New-Object 'System.Collections.Generic.List[string]'
$seenTexts = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$addXamlText = {
    param([string]$Text)

    if ($Text.Length -gt 0 -and $Text -cmatch '\p{L}' -and [Array]::IndexOf($keepEnglish, $Text) -lt 0 -and $seenTexts.Add($Text)) {
        $xamlTexts.Add($Text)
    }
}

foreach ($attribute in @($document.SelectNodes("//@*[local-name()='Content' or local-name()='Text' or local-name()='ToolTip' or local-name()='Header' or local-name()='Title']"))) {
    $value = $attribute.get_Value()
    $attributeName = $attribute.get_LocalName()
    $ownerName = $attribute.get_OwnerElement().get_LocalName()
    if ($value.StartsWith('{', [StringComparison]::Ordinal) -or
        ($ownerName -ceq 'TabItem' -and $attributeName -ceq 'Header') -or
        ($ownerName -ceq 'ComboBoxItem' -and $attributeName -ceq 'Content')) {
        continue
    }
    & $addXamlText $value
}

# An access-key label such as <Underline>I</Underline>nstall is looked up as a whole
$labelTest = "*[local-name()='Underline'] and count(*) = 1 and text()[normalize-space()]"
foreach ($textNode in @($document.SelectNodes('//text()'))) {
    $parent = $textNode.get_ParentNode()
    $parentName = $parent.get_LocalName()
    if ($parentName -ceq 'ComboBoxItem' -or $parentName -ceq 'TabItem.Header') {
        continue
    }
    if ($null -ne $parent.SelectSingleNode("self::*[$labelTest]") -or
        ($parentName -ceq 'Underline' -and $null -ne $parent.SelectSingleNode("parent::*[$labelTest]"))) {
        continue
    }
    & $addXamlText $textNode.get_Value().Trim()
}

foreach ($label in @($document.SelectNodes("//*[$labelTest]"))) {
    if ($label.get_LocalName() -cne 'ComboBoxItem') {
        & $addXamlText $label.get_InnerText().Trim()
    }
}

foreach ($text in $xamlTexts) {
    if (-not $uiPairs.ContainsKey($text)) {
        $missingXaml.Add($text)
    }
}
$coverage.Add((& $newCoverage 'xaml' 'ui' $xamlTexts.Count ($xamlTexts.Count - $missingXaml.Count)))

$errorCount = $shapeErrors.Count + $unknownKeys.Count + $stalePairs.Count + $conflicts.Count
$invariant = [System.Globalization.CultureInfo]::InvariantCulture

Write-Host "WinUtil translation check for '$code': $($files.Count) file(s): $($files -join ', ')"
Write-Host ''
Write-Host 'Coverage (translated / total):'
foreach ($row in $coverage) {
    Write-Host ([string]::Format($invariant, '  {0,-14}{1,-19}{2,5} / {3,-5}{4,7:0.0}%', [object[]]@($row.Config, $row.Field, $row.Translated, $row.Total, $row.Percent)))
}

foreach ($section in @(
        @('Shape errors', $shapeErrors),
        @('Unknown keys', $unknownKeys),
        @('Stale pairs', $stalePairs),
        @('Conflicts', $conflicts)
    )) {
    Write-Host ''
    Write-Host "$($section[0]): $($section[1].Count)"
    foreach ($issue in $section[1]) {
        $where = $issue.File
        if ($issue.Location) {
            $where = "$where $($issue.Location)"
        }
        Write-Host "  ${where}: $($issue.Message)"
        if ($null -ne $issue.PSObject.Properties['English']) {
            Write-Host "      lang:   $($issue.English)"
            Write-Host "      source: $($issue.Current)"
        }
    }
}

Write-Host ''
Write-Host "Window text without a ui pair: $($missingXaml.Count)"
foreach ($text in $missingXaml) {
    Write-Host ('  "' + ($text -creplace "`r?`n", '\n') + '"')
}
Write-Host "Config text without a pair: $($missingConfig.Count) (listed in MissingConfig)"
Write-Host ''
if ($errorCount -eq 0) {
    Write-Host 'No shape, unknown, stale or conflict errors.'
} else {
    Write-Host "$errorCount shape, unknown, stale or conflict error(s)."
}

[pscustomobject]@{
    Language      = $code
    Files         = $files.ToArray()
    ShapeErrors   = $shapeErrors.ToArray()
    UnknownKeys   = $unknownKeys.ToArray()
    StalePairs    = $stalePairs.ToArray()
    Conflicts     = $conflicts.ToArray()
    Coverage      = $coverage.ToArray()
    MissingConfig = $missingConfig.ToArray()
    MissingXaml   = $missingXaml.ToArray()
    ErrorCount    = $errorCount
}

if ($Strict) {
    if ($errorCount -gt 0) {
        exit 1
    }
    exit 0
}
