BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $tweaks = Get-Content -Path (Join-Path $repoRoot "config/tweaks.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:deleteTempScript = @($tweaks.WPFTweaksDeleteTempFiles.InvokeScript) -join "`n"
}

Describe "Temporary files cleanup script" {
    BeforeEach {
        $script:savedTemp = $env:TEMP
        $script:savedTmp = $env:TMP

        $script:userTemp = Join-Path $TestDrive "UserTemp"
        $script:systemTemp = Join-Path $TestDrive "SystemTemp"
        New-Item -ItemType Directory -Path $script:userTemp, $script:systemTemp -Force | Out-Null
    }

    AfterEach {
        $env:TEMP = $script:savedTemp
        $env:TMP = $script:savedTmp
    }

    It "keeps the PowerShell 7 compatibility proxies and removes everything else" {
        $scriptText = $script:deleteTempScript.Replace('$Env:SystemRoot\Temp', $script:systemTemp)

        # Nothing runs until the script can only reach this test's folders: no system path, no
        # other absolute path, and no environment variable but TEMP, which is redirected below
        $reach = $scriptText.Replace($script:systemTemp, '')
        $reach.IndexOf('SystemRoot', [System.StringComparison]::OrdinalIgnoreCase) | Should -Be -1
        $reach.IndexOf(':\', [System.StringComparison]::Ordinal) | Should -Be -1
        [regex]::Matches($reach, '\$\{?[Ee][Nn][Vv]:(\w+)') | ForEach-Object { $_.Groups[1].Value } |
            Where-Object { -not [string]::Equals($_, 'Temp', [System.StringComparison]::OrdinalIgnoreCase) } |
            Should -BeNullOrEmpty

        $env:TEMP = $script:userTemp
        $env:TMP = $script:userTemp

        $proxy = Join-Path $script:userTemp "remoteIpMoProxy_Appx_1.0.0.0_localhost_x"
        $proxyFile = Join-Path $proxy "p.format.ps1xml"
        $junkFile = Join-Path $script:userTemp "junk.tmp"
        $subFolder = Join-Path $script:userTemp "sub"
        New-Item -ItemType Directory -Path $proxy, $subFolder -Force | Out-Null
        Set-Content -LiteralPath $proxyFile -Value "proxy"
        Set-Content -LiteralPath $junkFile -Value "junk"
        Set-Content -LiteralPath (Join-Path $subFolder "a.txt") -Value "a"
        Set-Content -LiteralPath (Join-Path $script:systemTemp "system.tmp") -Value "system"

        & ([scriptblock]::Create($scriptText))

        Test-Path -LiteralPath $proxy | Should -BeTrue
        Test-Path -LiteralPath $proxyFile | Should -BeTrue
        Test-Path -LiteralPath $junkFile | Should -BeFalse
        Test-Path -LiteralPath $subFolder | Should -BeFalse
        Get-ChildItem -LiteralPath $script:systemTemp -Force | Should -BeNullOrEmpty
    }
}
