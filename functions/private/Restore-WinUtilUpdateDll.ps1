function Restore-WinUtilUpdateDll {
    <#

    .SYNOPSIS
        Restores the Windows Update DLLs that older WinUtil versions renamed

    .DESCRIPTION
        WinUtil 25.09.05 to 25.12.18 disabled updates by renaming WaaSMedicSvc.dll and wuaueng.dll
        in System32 to *_BAK.dll. A backup is renamed back only when the original DLL is missing,
        so a DLL that is already present is never overwritten. Ownership then returns to
        TrustedInstaller and the temporary Everyone grant is removed. A failure is logged per DLL
        and stops neither the other DLL nor the caller.

    #>

    foreach ($name in @("WaaSMedicSvc", "wuaueng")) {
        try {
            $dll = Join-Path $Env:SystemRoot "System32\$name.dll"
            $bak = Join-Path $Env:SystemRoot "System32\${name}_BAK.dll"

            if ((Test-Path -LiteralPath $bak) -and -not (Test-Path -LiteralPath $dll)) {
                takeown /f $bak | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "takeown failed with exit code $LASTEXITCODE." }

                icacls $bak /grant "*S-1-1-0:F" | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "icacls /grant failed with exit code $LASTEXITCODE." }

                Rename-Item -LiteralPath $bak -NewName "$name.dll" -ErrorAction Stop

                # Run both even if the owner change fails, so the Everyone grant is not left behind
                icacls $dll /setowner "NT SERVICE\TrustedInstaller" | Out-Null
                $setOwnerExitCode = $LASTEXITCODE
                icacls $dll /remove "*S-1-1-0" | Out-Null
                if ($setOwnerExitCode -ne 0 -or $LASTEXITCODE -ne 0) {
                    throw "$name.dll is back, but icacls could not reset its permissions (exit codes $setOwnerExitCode and $LASTEXITCODE)."
                }

                Write-Host "Restored $name.dll from ${name}_BAK.dll."
                Write-WinUtilLog -Component "Updates" -Message "Restored $name.dll from ${name}_BAK.dll."
            }
        } catch {
            Write-Host "Unable to restore $name.dll: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-WinUtilLog -Level "ERROR" -Component "Updates" -Message "Unable to restore $name.dll from ${name}_BAK.dll: $($_.Exception.Message)"
        }
    }
}
