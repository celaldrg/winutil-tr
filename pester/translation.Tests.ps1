#===========================================================================
# Tests - Translation
#===========================================================================

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$langCases = @(
    Get-ChildItem -Path (Join-Path $repoRoot "lang") -Filter *.json -File -ErrorAction SilentlyContinue | ForEach-Object {
        @{
            Name = $_.Name
            Path = $_.FullName
        }
    }
)
$languageCases = @(
    $langCases | ForEach-Object { $_.Name.Split(".")[0] } | Sort-Object -Unique -CaseSensitive | ForEach-Object {
        @{
            Language = $_
        }
    }
)

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:langRoot = Join-Path $script:repoRoot "lang"
    $script:toolPath = Join-Path $script:repoRoot "tools\Test-WinUtilTranslation.ps1"
    $script:xamlPath = Join-Path $script:repoRoot "xaml\inputXML.xaml"
    $script:translatableConfigs = [string[]]@("tweaks", "feature", "appx", "appnavigation", "applications")
    $script:translationLog = New-Object 'System.Collections.Generic.List[string]'

    # Keep the value itself: assigning $global:sync later changes the variable Get-Variable returns
    $script:hadGlobalSync = $null -ne (Get-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue)
    $script:previousSync = $null
    if ($script:hadGlobalSync) {
        $script:previousSync = (Get-Variable -Name sync -Scope Global).Value
    }

    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilText.ps1")
    . (Join-Path $script:repoRoot "functions\private\Initialize-WinUtilLanguage.ps1")

    function script:Write-WinUtilLog {
        param($Message, $Level = "INFO", $Component, [switch]$Detail)

        $script:translationLog.Add("[$Level] $Message")
    }

    function script:Initialize-TranslationTestSync {
        param([hashtable]$Configs = @{})

        $script:sync = [Hashtable]::Synchronized(@{
            configs     = $Configs
            preferences = @{}
        })
        $global:sync = $script:sync
    }

    # Every config the way Compile.ps1 embeds it, applications keys with the WPFInstall prefix
    function script:Get-TranslationTestConfig {
        $configs = @{}
        foreach ($file in @(Get-ChildItem -Path (Join-Path $script:repoRoot "config") -Filter *.json -File)) {
            $config = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($file.BaseName -ceq "applications") {
                $prefixed = [ordered]@{}
                foreach ($entry in $config.PSObject.Properties) {
                    $prefixed["WPFInstall$($entry.Name)"] = $entry.Value
                }
                $config = [pscustomobject]$prefixed
            }
            $configs[$file.BaseName] = $config
        }
        return $configs
    }

    # Every lang file keyed by BaseName, as Compile.ps1 fills $sync.configs.translations
    function script:Get-TranslationTestPart {
        $parts = @{}
        foreach ($file in @(Get-ChildItem -Path $script:langRoot -Filter *.json -File -ErrorAction SilentlyContinue)) {
            $parts[$file.BaseName] = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        return $parts
    }

    function script:Get-TranslationTestValue {
        param($Value)

        if ($Value -is [string]) {
            return "s:$Value"
        }
        return "j:" + (ConvertTo-Json -InputObject $Value -Depth 20 -Compress)
    }

    # Display holds the text the overlay may rewrite, Data holds every other config value
    function script:Get-TranslationTestSnapshot {
        param([hashtable]$Configs)

        $snapshot = @{
            Data    = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
            Display = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
        }
        foreach ($configName in @($Configs.Keys)) {
            if ($configName -ceq "translations" -or $configName -ceq "uitext" -or $configName -ceq "uipatterns") {
                continue
            }

            $translatable = $script:translatableConfigs -ccontains $configName
            foreach ($entry in $Configs[$configName].PSObject.Properties) {
                $entryPath = "$configName/$($entry.Name)"
                if ($entry.Value -isnot [System.Management.Automation.PSCustomObject]) {
                    $snapshot.Data[$entryPath] = Get-TranslationTestValue $entry.Value
                    continue
                }

                foreach ($field in $entry.Value.PSObject.Properties) {
                    $fieldPath = "$entryPath/$($field.Name)"
                    $isText = [string]::Equals($field.Name, "Content", [StringComparison]::OrdinalIgnoreCase) -or
                        [string]::Equals($field.Name, "Description", [StringComparison]::OrdinalIgnoreCase)
                    $isCombo = [string]::Equals($field.Name, "ComboDescriptions", [StringComparison]::OrdinalIgnoreCase) -and
                        $field.Value -is [System.Management.Automation.PSCustomObject]

                    if ($translatable -and $isCombo) {
                        foreach ($combo in $field.Value.PSObject.Properties) {
                            $snapshot.Display["$fieldPath/$($combo.Name)"] = Get-TranslationTestValue $combo.Value
                        }
                    } elseif ($translatable -and $isText) {
                        $snapshot.Display[$fieldPath] = Get-TranslationTestValue $field.Value
                    } else {
                        $snapshot.Data[$fieldPath] = Get-TranslationTestValue $field.Value
                    }
                }
            }
        }
        return $snapshot
    }

    # The config pairs of one language, keyed like the Display snapshot
    function script:Get-TranslationTestPair {
        param(
            [hashtable]$Translations,
            [string]$Language
        )

        $pairs = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
        $addPair = {
            param([string]$Target, $Pair)

            if (-not $pairs.ContainsKey($Target)) {
                $pairs[$Target] = New-Object 'System.Collections.Generic.List[object]'
            }
            $pairs[$Target].Add($Pair)
        }

        foreach ($partName in @($Translations.Keys)) {
            if (-not ($partName -ceq $Language -or $partName.StartsWith("$Language.", [StringComparison]::Ordinal))) {
                continue
            }
            $configs = $Translations[$partName].configs
            if ($configs -isnot [System.Management.Automation.PSCustomObject]) {
                continue
            }

            foreach ($config in $configs.PSObject.Properties) {
                if ($script:translatableConfigs -cnotcontains $config.Name -or $config.Value -isnot [System.Management.Automation.PSCustomObject]) {
                    continue
                }

                foreach ($entry in $config.Value.PSObject.Properties) {
                    $entryKey = $entry.Name
                    if ($config.Name -ceq "applications" -and -not $entryKey.StartsWith("WPFInstall", [StringComparison]::Ordinal)) {
                        $entryKey = "WPFInstall$entryKey"
                    }
                    if ($entry.Value -isnot [System.Management.Automation.PSCustomObject]) {
                        continue
                    }

                    foreach ($field in $entry.Value.PSObject.Properties) {
                        $target = "$($config.Name)/$entryKey/$($field.Name)"
                        if ($field.Value -is [System.Management.Automation.PSCustomObject]) {
                            foreach ($combo in $field.Value.PSObject.Properties) {
                                & $addPair "$target/$($combo.Name)" $combo.Value
                            }
                        } else {
                            & $addPair $target $field.Value
                        }
                    }
                }
            }
        }
        return $pairs
    }

    function script:Get-TranslationTestItemText {
        param([System.Xml.XmlElement]$Item)

        $text = "Header=" + $Item.GetAttribute("Header") + "|Content=" + $Item.GetAttribute("Content")
        if ($Item.get_LocalName() -ceq "ComboBoxItem") {
            return $text + "|" + $Item.get_InnerXml()
        }
        foreach ($header in @($Item.SelectNodes("*[local-name()='TabItem.Header']"))) {
            $text += "|" + $header.get_InnerXml()
        }
        return $text
    }

    # The documented lang file shape, checked on its own so a broken tool cannot hide a broken file
    function script:Get-TranslationShapeIssue {
        param($Part)

        $isPair = {
            param($Pair)

            $Pair -is [array] -and $Pair.Count -eq 2 -and
                $Pair[0] -is [string] -and $Pair[0].Length -gt 0 -and
                $Pair[1] -is [string] -and $Pair[1].Length -gt 0
        }
        $fields = @{
            tweaks        = [string[]]@("Content", "Description", "ComboDescriptions")
            feature       = [string[]]@("Content", "Description")
            appx          = [string[]]@("Description")
            appnavigation = [string[]]@("Content", "Description")
            applications  = [string[]]@("description")
        }

        if ($Part -isnot [System.Management.Automation.PSCustomObject]) {
            "the root is not a JSON object"
            return
        }

        foreach ($member in $Part.PSObject.Properties) {
            if ($member.Name -ceq "ui" -or $member.Name -ceq "patterns") {
                if ($member.Value -isnot [array]) {
                    "$($member.Name) is not an array"
                    continue
                }
                for ($index = 0; $index -lt $member.Value.Count; $index++) {
                    if (-not (& $isPair $member.Value[$index])) {
                        "$($member.Name)[$index] is not a pair"
                    }
                }
                continue
            }
            if ($member.Name -cne "configs") {
                "unknown member $($member.Name)"
                continue
            }
            if ($member.Value -isnot [System.Management.Automation.PSCustomObject]) {
                "configs is not an object"
                continue
            }

            foreach ($config in $member.Value.PSObject.Properties) {
                if ($script:translatableConfigs -cnotcontains $config.Name) {
                    "unknown config $($config.Name)"
                    continue
                }
                if ($config.Value -isnot [System.Management.Automation.PSCustomObject]) {
                    "configs.$($config.Name) is not an object"
                    continue
                }

                foreach ($entry in $config.Value.PSObject.Properties) {
                    $entryPath = "configs.$($config.Name).$($entry.Name)"
                    if ($entry.Value -isnot [System.Management.Automation.PSCustomObject]) {
                        "$entryPath is not an object"
                        continue
                    }

                    foreach ($field in $entry.Value.PSObject.Properties) {
                        $fieldPath = "$entryPath.$($field.Name)"
                        if ($fields[$config.Name] -cnotcontains $field.Name) {
                            "$fieldPath is not a translatable field"
                        } elseif ($field.Name -ceq "ComboDescriptions") {
                            if ($field.Value -isnot [System.Management.Automation.PSCustomObject]) {
                                "$fieldPath is not an object"
                                continue
                            }
                            foreach ($combo in $field.Value.PSObject.Properties) {
                                if (-not (& $isPair $combo.Value)) {
                                    "$fieldPath.$($combo.Name) is not a pair"
                                }
                            }
                        } elseif (-not (& $isPair $field.Value)) {
                            "$fieldPath is not a pair"
                        }
                    }
                }
            }
        }
    }

    function script:Format-TranslationIssue {
        param($Issue)

        @($Issue | ForEach-Object { "$($_.File) $($_.Location): $($_.Message)" }) -join [Environment]::NewLine
    }

    # A minimal repository for the tool: five configs, a window and one lang file
    function script:Initialize-TranslationFixture {
        param(
            [string]$Path,
            [string]$LangJson
        )

        $files = [ordered]@{
            "config\tweaks.json"        = '{"WPFTweaksA":{"Content":"Tweak A","Description":"Does A","category":"Essential Tweaks","ComboItems":"On|Off","ComboDescriptions":{"On":"Turns A on","Off":"Turns A off"}}}'
            "config\feature.json"       = '{"WPFFeatureB":{"Content":"Feature B","category":"Features"}}'
            "config\appx.json"          = '{"AppxC":{"Content":"App C","Description":"Removes C","Category":"Apps"}}'
            "config\appnavigation.json" = '{"WPFNavD":{"Content":"Nav D","Description":"Shows D","Category":"Nav"}}'
            "config\applications.json"  = '{"appe":{"content":"App E","description":"Installs E","category":"Utilities"}}'
            "xaml\inputXML.xaml"        = '<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Demo"><StackPanel><TabControl><TabItem Header="Install" /></TabControl><Button Content="Hello" /><TextBlock>World</TextBlock><ComboBox><ComboBoxItem Content="On" /></ComboBox></StackPanel></Window>'
            "lang\tr.a.json"            = $LangJson
        }
        foreach ($relativePath in $files.Keys) {
            $filePath = Join-Path $Path $relativePath
            $null = New-Item -ItemType Directory -Path (Split-Path $filePath -Parent) -Force
            [System.IO.File]::WriteAllText($filePath, $files[$relativePath], [System.Text.UTF8Encoding]::new($false))
        }
    }
}

AfterAll {
    # Script scope first: where it is the global scope, the global value is restored after it
    Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    if ($script:hadGlobalSync) {
        Set-Variable -Name sync -Value $script:previousSync -Scope Global
    } else {
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe "Translation files" {
    It "ships at least one lang file" {
        @(Get-ChildItem -Path $script:langRoot -Filter *.json -File -ErrorAction SilentlyContinue).Count | Should -BeGreaterThan 0
    }

    foreach ($langCase in $langCases) {
        It "stores $($langCase.Name) as UTF-8 without BOM in the documented shape" -TestCases $langCase {
            param([string]$Name, [string]$Path)

            $bytes = [System.IO.File]::ReadAllBytes($Path)
            $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
            $hasBom | Should -BeFalse -Because "$Name must be UTF-8 without BOM"

            # A strict decoder throws on any byte sequence that is not UTF-8
            $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
            $part = $text | ConvertFrom-Json

            (@(Get-TranslationShapeIssue $part) -join [Environment]::NewLine) | Should -BeNullOrEmpty
        }

        It "compiles every pattern in $($langCase.Name) with CultureInvariant" -TestCases $langCase {
            param([string]$Name, [string]$Path)

            $part = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            $failed = foreach ($pair in $part.patterns) {
                try {
                    $null = New-Object regex($pair[0], [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
                } catch {
                    "$($pair[0]): $($_.Exception.Message)"
                }
            }

            (@($failed) -join [Environment]::NewLine) | Should -BeNullOrEmpty
        }
    }

    foreach ($languageCase in $languageCases) {
        It "has no shape, unknown, stale or conflict errors for '$($languageCase.Language)'" -TestCases $languageCase {
            param([string]$Language)

            $result = & $script:toolPath -Language $Language -RepoRoot $script:repoRoot 6>$null

            @($result.Files).Count | Should -BeGreaterThan 0
            Format-TranslationIssue $result.ShapeErrors | Should -BeNullOrEmpty
            Format-TranslationIssue $result.UnknownKeys | Should -BeNullOrEmpty
            Format-TranslationIssue $result.StalePairs | Should -BeNullOrEmpty
            Format-TranslationIssue $result.Conflicts | Should -BeNullOrEmpty
            $result.ErrorCount | Should -Be 0
        }
    }

    It "reports every kind of error in a broken fixture and fails with -Strict" {
        $fixtureRoot = Join-Path $TestDrive "broken"
        Initialize-TranslationFixture -Path $fixtureRoot -LangJson ('{"ui":[["Hello","Merhaba"],["Hello","Selam"],["Bad"]],"patterns":[["([","x"]],"extra":[],' +
            '"configs":{"tweak":{},"tweaks":{"WPFTweaksA":{"Description":["Did A","A yapildi"],"category":["Essential Tweaks","Temel"]},' +
            '"WPFTweaksMissing":{"Content":["X","Y"]}},"applications":{"WPFInstallappe":{"description":["Installs E","E kurar"]}}}}')

        $result = & $script:toolPath -Language tr -RepoRoot $fixtureRoot 6>$null

        (@($result.ShapeErrors.Location) -join "|") | Should -BeExactly "ui[2]|patterns[0]|extra|configs.tweak|configs.tweaks.WPFTweaksA.category"
        (@($result.UnknownKeys.Location) -join "|") | Should -BeExactly "configs.tweaks.WPFTweaksMissing"
        (@($result.StalePairs.Location) -join "|") | Should -BeExactly "configs.tweaks.WPFTweaksA.Description"
        $result.StalePairs[0].Current | Should -BeExactly "Does A"
        (@($result.Conflicts.Location) -join "|") | Should -BeExactly "ui[1]"
        $result.ErrorCount | Should -Be 8

        $null = & $script:toolPath -Language tr -RepoRoot $fixtureRoot -Strict 6>$null
        $LASTEXITCODE | Should -Be 1
    }

    It "passes a clean fixture, reports what is missing and succeeds with -Strict" {
        $fixtureRoot = Join-Path $TestDrive "clean"
        Initialize-TranslationFixture -Path $fixtureRoot -LangJson ('{"ui":[["Hello","Merhaba"]],"patterns":[["^Removing (.+)$","$1 kald\u0131r\u0131l\u0131yor"]],' +
            '"configs":{"tweaks":{"WPFTweaksA":{"Content":["Tweak A","Ayar A"],"Description":["Does A","A yapar"],"ComboDescriptions":{"On":["Turns A on","A a\u00e7\u0131l\u0131r"]}}},' +
            '"applications":{"appe":{"description":["Installs E","E kurar"]}}}}')

        $result = & $script:toolPath -Language tr -RepoRoot $fixtureRoot -Strict 6>$null

        $LASTEXITCODE | Should -Be 0
        $result.ErrorCount | Should -Be 0
        @($result.Coverage | Where-Object { $_.Config -ceq "tweaks" -and $_.Field -ceq "ComboDescriptions" })[0].Percent | Should -Be 50
        (@($result.MissingXaml) -join "|") | Should -BeExactly "Demo|World"
    }
}

Describe "Translation overlay" {
    BeforeAll {
        $script:originalXaml = Get-Content -LiteralPath $script:xamlPath -Raw -Encoding UTF8

        $configs = Get-TranslationTestConfig
        $configs.translations = Get-TranslationTestPart
        Initialize-TranslationTestSync -Configs $configs

        $script:before = Get-TranslationTestSnapshot -Configs $script:sync.configs
        $script:translationLog.Clear()
        $script:translatedXaml = Initialize-WinUtilLanguage -Xaml $script:originalXaml -Language tr
        $script:after = Get-TranslationTestSnapshot -Configs $script:sync.configs
        $script:configPairs = Get-TranslationTestPair -Translations $script:sync.configs.translations -Language tr
    }

    It "returns XAML that parses, without a warning" {
        ($script:translatedXaml -is [string]) | Should -BeTrue
        ([xml]$script:translatedXaml).get_DocumentElement().get_LocalName() | Should -BeExactly "Window"
        (@($script:translationLog) -cmatch '^\[WARN\]') -join [Environment]::NewLine | Should -BeNullOrEmpty
    }

    It "leaves every TabItem header and ComboBoxItem content as it was" {
        $original = [xml]$script:originalXaml
        $translated = [xml]$script:translatedXaml
        @($original.SelectNodes("//*[local-name()='TabItem']")).Count | Should -BeGreaterThan 0

        foreach ($itemName in "TabItem", "ComboBoxItem") {
            $originalItems = @($original.SelectNodes("//*[local-name()='$itemName']"))
            $translatedItems = @($translated.SelectNodes("//*[local-name()='$itemName']"))
            $translatedItems.Count | Should -Be $originalItems.Count

            for ($index = 0; $index -lt $originalItems.Count; $index++) {
                Get-TranslationTestItemText $translatedItems[$index] | Should -BeExactly (Get-TranslationTestItemText $originalItems[$index])
            }
        }
    }

    It "changes no config value except Content, Description and ComboDescriptions text" {
        $script:after.Data.Count | Should -Be $script:before.Data.Count
        $script:after.Display.Count | Should -Be $script:before.Display.Count
        @($script:before.Data.Keys | Where-Object { $_ -cmatch '/(category|Category)$' }).Count | Should -BeGreaterThan 0
        @($script:before.Data.Keys | Where-Object { $_ -cmatch '/ComboItems$' }).Count | Should -BeGreaterThan 0

        $changed = foreach ($key in $script:before.Data.Keys) {
            if (-not $script:after.Data.ContainsKey($key) -or $script:after.Data[$key] -cne $script:before.Data[$key]) {
                $key
            }
        }
        (@($changed) -join ", ") | Should -BeNullOrEmpty
    }

    It "translates config text, and only with a pair written for that text" {
        $translatedCount = 0
        $unexpected = foreach ($key in $script:before.Display.Keys) {
            $old = $script:before.Display[$key]
            $new = $script:after.Display[$key]
            if ($new -ceq $old) {
                continue
            }

            $translatedCount++
            $found = $false
            $pairs = $null
            if ($script:configPairs.TryGetValue($key, [ref]$pairs)) {
                foreach ($pair in $pairs) {
                    if ("s:$($pair[0])" -ceq $old -and "s:$($pair[1])" -ceq $new) {
                        $found = $true
                        break
                    }
                }
            }
            if (-not $found) {
                $key
            }
        }

        $translatedCount | Should -BeGreaterThan 0
        (@($unexpected) -join ", ") | Should -BeNullOrEmpty
    }

    It "stores the language in preferences" {
        $script:sync.preferences.language | Should -BeExactly "tr"
    }

    It "returns the XAML unchanged for English" {
        $result = Initialize-WinUtilLanguage -Xaml $script:originalXaml -Language en

        [string]::Equals($result, $script:originalXaml, [StringComparison]::Ordinal) | Should -BeTrue
        $script:sync.preferences.language | Should -BeExactly "en"
    }
}

Describe "Translation overlay on a small window" {
    BeforeAll {
        $part = '{"ui":[["Install","Y\u00fckle"],["Enabled","Etkin"]]}' | ConvertFrom-Json
        Initialize-TranslationTestSync -Configs @{ translations = @{ tr = $part } }

        $xaml = '<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><StackPanel><TabControl>' +
            '<TabItem Header="Install"><TextBlock Text="Install" /></TabItem><TabItem><TabItem.Header>Install</TabItem.Header></TabItem></TabControl>' +
            '<ComboBox><ComboBoxItem Content="Enabled" /><ComboBoxItem>Enabled</ComboBoxItem></ComboBox><Button Content="Enabled" /></StackPanel></Window>'
        $script:smallWindow = [xml](Initialize-WinUtilLanguage -Xaml $xaml -Language tr)
    }

    It "translates the text around the tabs and combo boxes" {
        $script:smallWindow.SelectSingleNode("//*[local-name()='TextBlock']").GetAttribute("Text") | Should -BeExactly ("Y" + [char]0x00FC + "kle")
        $script:smallWindow.SelectSingleNode("//*[local-name()='Button']").GetAttribute("Content") | Should -BeExactly "Etkin"
    }

    It "keeps TabItem headers and ComboBoxItem content in English" {
        $tabs = @($script:smallWindow.SelectNodes("//*[local-name()='TabItem']"))
        $tabs[0].GetAttribute("Header") | Should -BeExactly "Install"
        $tabs[1].SelectSingleNode("*[local-name()='TabItem.Header']").get_InnerText() | Should -BeExactly "Install"

        $items = @($script:smallWindow.SelectNodes("//*[local-name()='ComboBoxItem']"))
        $items[0].GetAttribute("Content") | Should -BeExactly "Enabled"
        $items[1].get_InnerText() | Should -BeExactly "Enabled"
    }
}

Describe "Get-WinUtilText" {
    BeforeAll {
        $part = '{"ui":[["Install","Y\u00fckle"]],"patterns":[["^Installing (.+)$","$1 y\u00fckleniyor"]]}' | ConvertFrom-Json
        Initialize-TranslationTestSync -Configs @{ translations = @{ tr = $part } }
        $null = Initialize-WinUtilLanguage -Xaml "<Grid />" -Language tr
    }

    It "returns the translation of an exact match" {
        Get-WinUtilText "Install" | Should -BeExactly ("Y" + [char]0x00FC + "kle")
    }

    It "rewrites text that matches a pattern" {
        Get-WinUtilText "Installing 7-Zip" | Should -BeExactly ("7-Zip y" + [char]0x00FC + "kleniyor")
    }

    It "passes through text without a translation" {
        Get-WinUtilText "Uninstall" | Should -BeExactly "Uninstall"
    }

    It "passes through null and empty text" {
        ($null -eq (Get-WinUtilText $null)) | Should -BeTrue
        Get-WinUtilText "" | Should -BeExactly ""
    }

    It "matches case-sensitively" {
        Get-WinUtilText "install" | Should -BeExactly "install"
        Get-WinUtilText "installing 7-Zip" | Should -BeExactly "installing 7-Zip"
    }

    It "passes text through when no table is loaded" {
        $null = Initialize-WinUtilLanguage -Xaml "<Grid />" -Language en
        Get-WinUtilText "Install" | Should -BeExactly "Install"

        Initialize-TranslationTestSync
        Get-WinUtilText "Install" | Should -BeExactly "Install"
    }
}

Describe "Compiled translations" {
    BeforeAll {
        $script:compiledPath = Join-Path $script:repoRoot "winutil.ps1"

        Push-Location $script:repoRoot
        try {
            & (Join-Path $script:repoRoot "Compile.ps1")
        } finally {
            Pop-Location
        }

        $script:compiledText = Get-Content -Path $script:compiledPath -Raw -Encoding UTF8
        $script:compiledLines = $script:compiledText -split "\r?\n"
        $script:langFiles = @(Get-ChildItem -Path $script:langRoot -Filter *.json -File -ErrorAction SilentlyContinue)
    }

    It "embeds one pure ASCII block for every lang file" {
        $headers = @($script:compiledLines | Where-Object { $_.StartsWith('$sync.configs.translations[', [StringComparison]::Ordinal) })
        $headers.Count | Should -Be $script:langFiles.Count
        (@($headers | Where-Object { $_ -cmatch '[^\x00-\x7F]' }) -join [Environment]::NewLine) | Should -BeNullOrEmpty

        # The JSON sits on the line after each header, so the whole block is checked too
        $start = [Array]::IndexOf($script:compiledLines, '$sync.configs.translations = @{}')
        $start | Should -BeGreaterOrEqual 0
        $end = $start + 1
        while ($end -lt $script:compiledLines.Count -and -not $script:compiledLines[$end].StartsWith('$inputXML = @' + "'", [StringComparison]::Ordinal)) {
            $end++
        }
        $end | Should -BeLessThan $script:compiledLines.Count

        $nonAscii = for ($index = $start; $index -lt $end; $index++) {
            if ($script:compiledLines[$index] -cmatch '[^\x00-\x7F]') {
                $index + 1
            }
        }
        (@($nonAscii) -join ", ") | Should -BeNullOrEmpty -Because "these winutil.ps1 lines must be pure ASCII"
    }

    It "embeds the same JSON as each lang file" {
        $blocks = [regex]::Matches(
            $script:compiledText,
            '(?ms)^\$sync\.configs\.translations\[''(?<name>[^'']+)''\] = @''\r?\n(?<json>.*?)\r?\n''@ \| ConvertFrom-Json'
        )
        $blocks.Count | Should -Be $script:langFiles.Count

        foreach ($block in $blocks) {
            $name = $block.Groups["name"].Value
            $sourcePath = Join-Path $script:langRoot "$name.json"
            Test-Path -LiteralPath $sourcePath | Should -BeTrue -Because "$name must come from lang/$name.json"

            $embedded = $block.Groups["json"].Value | ConvertFrom-Json | ConvertTo-Json -Depth 20 -Compress
            $source = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8 | ConvertFrom-Json | ConvertTo-Json -Depth 20 -Compress
            $embedded | Should -BeExactly $source -Because "$name must round-trip unchanged"
        }
    }

    It "places the translations after the applications config and before the window XAML" {
        $applications = [regex]::Match($script:compiledText, '(?m)^\$sync\.configs\.applications = @''')
        $start = [regex]::Match($script:compiledText, '(?m)^\$sync\.configs\.translations = @\{\}')
        $headers = [regex]::Matches($script:compiledText, '(?m)^\$sync\.configs\.translations\[')
        $window = [regex]::Match($script:compiledText, '(?m)^\$inputXML = @''')

        $applications.Success | Should -BeTrue
        $start.Success | Should -BeTrue
        $window.Success | Should -BeTrue
        $start.Index | Should -BeGreaterThan $applications.Index
        $window.Index | Should -BeGreaterThan $start.Index
        if ($headers.Count -gt 0) {
            $headers[0].Index | Should -BeGreaterThan $start.Index
            $headers[$headers.Count - 1].Index | Should -BeLessThan $window.Index
        }
    }
}
