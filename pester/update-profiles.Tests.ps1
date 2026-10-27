#===========================================================================
# Tests - Windows Update Profiles
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFUpdatesdisable.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFUpdatesdefault.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFUpdatessecurity.ps1")
    . (Join-Path $script:repoRoot "functions\private\Restore-WinUtilUpdateDll.ps1")

    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }
    function Show-WinUtilMessage {
        param($Message, $Title, $Button, $Icon)
    }
    function Get-ScheduledTask {
        param($TaskPath, $ErrorAction)
    }
    function Disable-ScheduledTask {
        param(
            [Parameter(ValueFromPipeline = $true)]
            $InputObject,
            $ErrorAction
        )
        process { }
    }
    function Enable-ScheduledTask {
        param(
            [Parameter(ValueFromPipeline = $true)]
            $InputObject,
            $ErrorAction
        )
        process { }
    }
    function secedit {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            $Arguments
        )
    }
    function takeown {
        param($Option, $Target)
        throw "takeown must be mocked: $Option $Target"
    }
    function icacls {
        param($Target, $Operation, $Principal)
        throw "icacls must be mocked: $Target $Operation $Principal"
    }

    $script:updateTaskPaths = @(
        '\Microsoft\Windows\InstallService\*',
        '\Microsoft\Windows\UpdateOrchestrator\*',
        '\Microsoft\Windows\UpdateAssistant\*',
        '\Microsoft\Windows\WaaSMedic\*',
        '\Microsoft\Windows\WindowsUpdate\*',
        '\Microsoft\WindowsUpdate\*'
    )

    # The restore steps of WinUtil 25.09.05 to 25.12.18, in their original order
    $system32Path = Join-Path $Env:SystemRoot "System32"
    $script:updateDllRestoreCalls = @(
        "takeown /f $system32Path\WaaSMedicSvc_BAK.dll",
        "icacls $system32Path\WaaSMedicSvc_BAK.dll /grant *S-1-1-0:F",
        "rename $system32Path\WaaSMedicSvc_BAK.dll WaaSMedicSvc.dll",
        "icacls $system32Path\WaaSMedicSvc.dll /setowner NT SERVICE\TrustedInstaller",
        "icacls $system32Path\WaaSMedicSvc.dll /remove *S-1-1-0",
        "takeown /f $system32Path\wuaueng_BAK.dll",
        "icacls $system32Path\wuaueng_BAK.dll /grant *S-1-1-0:F",
        "rename $system32Path\wuaueng_BAK.dll wuaueng.dll",
        "icacls $system32Path\wuaueng.dll /setowner NT SERVICE\TrustedInstaller",
        "icacls $system32Path\wuaueng.dll /remove *S-1-1-0"
    )

    # When the rename fails, the backup goes back to TrustedInstaller without the Everyone grant
    $script:updateDllRollbackCalls = @(
        "takeown /f $system32Path\WaaSMedicSvc_BAK.dll",
        "icacls $system32Path\WaaSMedicSvc_BAK.dll /grant *S-1-1-0:F",
        "rename $system32Path\WaaSMedicSvc_BAK.dll WaaSMedicSvc.dll",
        "icacls $system32Path\WaaSMedicSvc_BAK.dll /setowner NT SERVICE\TrustedInstaller",
        "icacls $system32Path\WaaSMedicSvc_BAK.dll /remove *S-1-1-0",
        "takeown /f $system32Path\wuaueng_BAK.dll",
        "icacls $system32Path\wuaueng_BAK.dll /grant *S-1-1-0:F",
        "rename $system32Path\wuaueng_BAK.dll wuaueng.dll",
        "icacls $system32Path\wuaueng_BAK.dll /setowner NT SERVICE\TrustedInstaller",
        "icacls $system32Path\wuaueng_BAK.dll /remove *S-1-1-0"
    )
}

Describe "Invoke-WPFUpdatesdisable" {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-WinUtilLog { }
        Mock Show-WinUtilMessage { "Yes" }
        Mock Test-Path { $false }
        Mock New-Item { }
        Mock Set-ItemProperty { }
        Mock Set-Service { }
        Mock Stop-Service { }
        Mock Remove-Item { }
        Mock Get-ScheduledTask {
            [pscustomobject]@{
                TaskPath = $TaskPath
            }
        }
        Mock Disable-ScheduledTask { }
    }

    It "sets update disable registry policy values" {
        Invoke-WPFUpdatesdisable

        Should -Invoke -CommandName New-Item -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and $Force -eq $true
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "NoAutoUpdate" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "AUOptions" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -and
                $Name -eq "DODownloadMode" -and
                $Type -eq "DWord" -and
                $Value -eq 0
        }
    }

    It "keeps existing policy keys instead of recreating them" {
        Mock Test-Path { $true }

        Invoke-WPFUpdatesdisable

        Should -Not -Invoke New-Item
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "NoAutoUpdate" -and
                $Value -eq 1
        }
    }

    It "disables update services and clears the SoftwareDistribution folder" {
        Invoke-WPFUpdatesdisable

        foreach ($expectedServiceName in @("BITS", "wuauserv", "UsoSvc")) {
            $expected = $expectedServiceName
            Should -Invoke -CommandName Stop-Service -Times 1 -Exactly -ParameterFilter {
                $Name -eq $expected -and $Force -eq $true
            }
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "BITS" -and $StartupType -eq "Disabled"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "wuauserv" -and $StartupType -eq "Disabled"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "UsoSvc" -and $StartupType -eq "Disabled"
        }
        Should -Invoke -CommandName Remove-Item -Times 1 -Exactly -ParameterFilter {
            $Path -eq "C:\Windows\SoftwareDistribution\*" -and
                $Recurse -eq $true -and
                $Force -eq $true
        }
    }

    It "disables update scheduled task paths" {
        Invoke-WPFUpdatesdisable

        foreach ($expectedTaskPath in $script:updateTaskPaths) {
            $expected = $expectedTaskPath
            Should -Invoke -CommandName Get-ScheduledTask -Times 1 -Exactly -ParameterFilter {
                $TaskPath -eq $expected
            }
        }
        Should -Invoke -CommandName Disable-ScheduledTask -Times $script:updateTaskPaths.Count -Exactly
    }

    It "requires confirmation before disabling updates" {
        Mock Show-WinUtilMessage { "No" }

        Invoke-WPFUpdatesdisable

        Should -Invoke Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Title -eq "Disable Windows Update?" -and
                $Button -eq "YesNo" -and
                $Icon -eq "Warning"
        }
        Should -Not -Invoke Set-ItemProperty
        Should -Not -Invoke Set-Service
        Should -Not -Invoke Remove-Item
    }
}

Describe "Invoke-WPFUpdatesdefault" {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-WinUtilLog { }
        Mock Remove-Item { }
        Mock Remove-ItemProperty { }
        Mock Get-ItemProperty {
            [pscustomobject]@{
                SettingsPageVisibility = "hide:windowsupdate"
            }
        }
        Mock Set-Service { }
        Mock Start-Service { }
        Mock Get-ScheduledTask {
            [pscustomobject]@{
                TaskPath = $TaskPath
            }
        }
        Mock Enable-ScheduledTask { }
        Mock secedit { }
        Mock Test-Path { $false }
        $script:savedExitCode = $global:LASTEXITCODE
        $script:dllCalls = [System.Collections.Generic.List[string]]::new()
        Mock Rename-Item { $script:dllCalls.Add("rename $LiteralPath $NewName") }
        Mock takeown {
            $script:dllCalls.Add("takeown $Option $Target")
            $global:LASTEXITCODE = 0
        }
        Mock icacls {
            $script:dllCalls.Add("icacls $Target $Operation $Principal")
            $global:LASTEXITCODE = 0
        }
    }

    AfterEach {
        $global:LASTEXITCODE = $script:savedExitCode
    }

    It "removes only registry values managed by WinUtil" {
        Invoke-WPFUpdatesdefault

        $expectedRegistryValues = @(
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU", "NoAutoUpdate", "AUOptions", "NoAutoRebootWithLoggedOnUsers", "AUPowerManagement"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate", "ExcludeWUDriversInQualityUpdate", "DeferFeatureUpdates", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdates", "DeferQualityUpdatesPeriodInDays"),
            @("HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings", "BranchReadinessLevel", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdatesPeriodInDays"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata", "PreventDeviceMetadataFromNetwork"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching", "DontPromptForWindowsUpdate", "DontSearchWindowsUpdate", "DriverUpdateWizardWuSearchEnabled"),
            @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config", "DODownloadMode")
        )

        foreach ($expectedEntry in $expectedRegistryValues) {
            $expectedPath = $expectedEntry[0]
            foreach ($expectedName in $expectedEntry[1..($expectedEntry.Count - 1)]) {
                $valueName = $expectedName
                Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
                    $Path -eq $expectedPath -and $Name -eq $valueName
                }
            }
        }
        Should -Not -Invoke Remove-Item
        Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -and
                $Name -eq "SettingsPageVisibility"
        }
    }

    It "preserves unrelated Settings page visibility policy" {
        Mock Get-ItemProperty {
            [pscustomobject]@{
                SettingsPageVisibility = "hide:privacy"
            }
        }

        Invoke-WPFUpdatesdefault

        Should -Not -Invoke Remove-ItemProperty -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -and
                $Name -eq "SettingsPageVisibility"
        }
    }

    It "restores update service startup types" {
        Invoke-WPFUpdatesdefault

        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "BITS" -and $StartupType -eq "Manual"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "wuauserv" -and $StartupType -eq "Manual"
        }
        Should -Invoke -CommandName Start-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "UsoSvc"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "UsoSvc" -and $StartupType -eq "Automatic"
        }
        Should -Not -Invoke Set-Service -ParameterFilter {
            $Name -eq "WaaSMedicSvc"
        }
    }

    It "enables update scheduled task paths without resetting unrelated local security policy" {
        Invoke-WPFUpdatesdefault

        foreach ($expectedTaskPath in $script:updateTaskPaths) {
            $expected = $expectedTaskPath
            Should -Invoke -CommandName Get-ScheduledTask -Times 1 -Exactly -ParameterFilter {
                $TaskPath -eq $expected
            }
        }
        Should -Invoke -CommandName Enable-ScheduledTask -Times $script:updateTaskPaths.Count -Exactly
        Should -Not -Invoke secedit
    }

    It "restores update DLLs that an older WinUtil version renamed" {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -clike "*_BAK.dll" }

        Invoke-WPFUpdatesdefault

        foreach ($expectedDllName in @("WaaSMedicSvc", "wuaueng")) {
            $expected = $expectedDllName
            Should -Invoke -CommandName Rename-Item -Times 1 -Exactly -ParameterFilter {
                $LiteralPath -clike "*\${expected}_BAK.dll" -and $NewName -ceq "$expected.dll"
            }
        }
        $script:dllCalls.ToArray() | Should -BeExactly $script:updateDllRestoreCalls
    }

    It "leaves update DLLs alone when no renamed backup exists" {
        Invoke-WPFUpdatesdefault

        foreach ($expectedDllName in @("WaaSMedicSvc", "wuaueng")) {
            $expected = $expectedDllName
            Should -Invoke -CommandName Test-Path -Times 1 -Exactly -ParameterFilter {
                $LiteralPath -clike "*\${expected}_BAK.dll"
            }
        }
        Should -Not -Invoke takeown
        Should -Not -Invoke icacls
        Should -Not -Invoke Rename-Item
    }

    It "never replaces an update DLL that is already present" {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -clike "*.dll" }

        Invoke-WPFUpdatesdefault

        foreach ($expectedDllName in @("WaaSMedicSvc", "wuaueng")) {
            $expected = $expectedDllName
            Should -Invoke -CommandName Test-Path -Times 1 -Exactly -ParameterFilter {
                $LiteralPath -clike "*\$expected.dll"
            }
        }
        Should -Not -Invoke takeown
        Should -Not -Invoke icacls
        Should -Not -Invoke Rename-Item
    }

    It "returns a backup it could not rename to TrustedInstaller and continues" {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -clike "*_BAK.dll" }
        Mock Rename-Item {
            $script:dllCalls.Add("rename $LiteralPath $NewName")
            throw "locked"
        }

        Invoke-WPFUpdatesdefault

        $script:dllCalls.ToArray() | Should -BeExactly $script:updateDllRollbackCalls
        Should -Invoke -CommandName Write-WinUtilLog -Times 2 -Exactly -ParameterFilter {
            $Level -ceq "ERROR"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -ceq "BITS" -and $StartupType -ceq "Manual"
        }
    }
}

Describe "Invoke-WPFUpdatessecurity" {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-WinUtilLog { }
        Mock Test-Path { $false }
        Mock New-Item { }
        Mock Set-ItemProperty { }
        Mock Remove-ItemProperty { }
        Mock Get-ItemProperty { }
        Mock Set-Service { }
        Mock Start-Service { }
        Mock Get-ScheduledTask {
            [pscustomobject]@{
                TaskPath = $TaskPath
            }
        }
        Mock Enable-ScheduledTask { }
        $script:savedExitCode = $global:LASTEXITCODE
        $script:dllCalls = [System.Collections.Generic.List[string]]::new()
        Mock Rename-Item { $script:dllCalls.Add("rename $LiteralPath $NewName") }
        Mock takeown {
            $script:dllCalls.Add("takeown $Option $Target")
            $global:LASTEXITCODE = 0
        }
        Mock icacls {
            $script:dllCalls.Add("icacls $Target $Operation $Principal")
            $global:LASTEXITCODE = 0
        }
    }

    AfterEach {
        $global:LASTEXITCODE = $script:savedExitCode
    }

    It "restores update availability before applying recommended settings" {
        Invoke-WPFUpdatessecurity

        Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "NoAutoUpdate"
        }
        Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -and
                $Name -eq "DODownloadMode"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "BITS" -and $StartupType -eq "Manual"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "wuauserv" -and $StartupType -eq "Manual"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "UsoSvc" -and $StartupType -eq "Automatic"
        }
        Should -Invoke -CommandName Start-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "UsoSvc"
        }
        foreach ($expectedTaskPath in $script:updateTaskPaths) {
            $expected = $expectedTaskPath
            Should -Invoke -CommandName Get-ScheduledTask -Times 1 -Exactly -ParameterFilter {
                $TaskPath -eq $expected
            }
        }
        Should -Invoke -CommandName Enable-ScheduledTask -Times $script:updateTaskPaths.Count -Exactly
    }

    It "restores update DLLs that an older WinUtil version renamed" {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -clike "*_BAK.dll" }

        Invoke-WPFUpdatessecurity

        foreach ($expectedDllName in @("WaaSMedicSvc", "wuaueng")) {
            $expected = $expectedDllName
            Should -Invoke -CommandName Rename-Item -Times 1 -Exactly -ParameterFilter {
                $LiteralPath -clike "*\${expected}_BAK.dll" -and $NewName -ceq "$expected.dll"
            }
        }
        $script:dllCalls.ToArray() | Should -BeExactly $script:updateDllRestoreCalls
    }

    It "disables driver metadata and Windows Update driver search" {
        Invoke-WPFUpdatessecurity

        Should -Invoke -CommandName New-Item -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -and $Force -eq $true
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -and
                $Name -eq "PreventDeviceMetadataFromNetwork" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -and
                $Name -eq "DontPromptForWindowsUpdate" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -and
                $Name -eq "DontSearchWindowsUpdate" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -and
                $Name -eq "DriverUpdateWizardWuSearchEnabled" -and
                $Type -eq "DWord" -and
                $Value -eq 0
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -and
                $Name -eq "ExcludeWUDriversInQualityUpdate" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
    }

    It "sets recommended update deferral and installation notification policy values" {
        Invoke-WPFUpdatessecurity

        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -and
                $Name -eq "DeferFeatureUpdates" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -and
                $Name -eq "DeferFeatureUpdatesPeriodInDays" -and
                $Type -eq "DWord" -and
                $Value -eq 365
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -and
                $Name -eq "DeferQualityUpdates" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -and
                $Name -eq "DeferQualityUpdatesPeriodInDays" -and
                $Type -eq "DWord" -and
                $Value -eq 4
        }
        Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "NoAutoRebootWithLoggedOnUsers"
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "AUOptions" -and
                $Type -eq "DWord" -and
                $Value -eq 3
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "AUPowerManagement" -and
                $Type -eq "DWord" -and
                $Value -eq 0
        }
    }

    It "keeps existing policy keys instead of recreating them" {
        Mock Test-Path { $true }

        Invoke-WPFUpdatessecurity

        Should -Not -Invoke New-Item
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -and
                $Name -eq "DeferFeatureUpdates" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "AUOptions" -and
                $Value -eq 3
        }
    }

    It "clears a leftover Win11 Creator update block" {
        Mock Get-ItemProperty {
            [pscustomobject]@{ WUServer = "http://localhost:8080" }
        } -ParameterFilter { $Name -eq "WUServer" }

        Invoke-WPFUpdatessecurity

        foreach ($expectedValue in @(
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate", "DisableWindowsUpdateAccess"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate", "WUServer"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate", "WUStatusServer"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU", "UseWUServer")
        )) {
            $expected = $expectedValue
            Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $Path -eq $expected[0] -and $Name -eq $expected[1]
            }
        }
    }

    It "keeps a real WSUS server" {
        Mock Get-ItemProperty {
            [pscustomobject]@{ WUServer = "http://wsus.example.local:8530" }
        } -ParameterFilter { $Name -eq "WUServer" }

        Invoke-WPFUpdatessecurity

        Should -Not -Invoke Remove-ItemProperty -ParameterFilter {
            $Name -in @("WUServer", "WUStatusServer", "UseWUServer")
        }
    }

    It "removes legacy WinUtil deferral values from the unsupported UX settings path" {
        Invoke-WPFUpdatessecurity

        foreach ($expectedValueName in @("BranchReadinessLevel", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdatesPeriodInDays")) {
            $expected = $expectedValueName
            Should -Invoke Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $Path -eq "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -and
                    $Name -eq $expected
            }
        }
    }
}
