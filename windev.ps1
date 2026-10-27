# Runs the pre-release version of winutil

$latestTag = (Invoke-RestMethod https://api.github.com/repos/celaldrg/winutil-tr/tags).Name | Select-Object -First 1
$uri = "https://github.com/celaldrg/winutil-tr/releases/download/$latestTag/winutil.ps1"
$scriptPath = Join-Path $env:TEMP "winutil-$latestTag.ps1"

Invoke-WebRequest -Uri $uri -OutFile $scriptPath -UseBasicParsing -ErrorAction Stop

$executable = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
$currentPowerShell = Join-Path $PSHOME $executable
& $currentPowerShell -ExecutionPolicy Bypass -NoProfile -File $scriptPath
