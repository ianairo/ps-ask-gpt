#requires -Version 7.2
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'The full test suite requires Windows for DPAPI key storage.' }

$null = Test-ModuleManifest (Join-Path $PSScriptRoot 'AskGPT.psd1') -ErrorAction Stop
foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object Extension -In '.ps1', '.psm1', '.psd1') {
    $tokens = $null
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw "Invalid PowerShell in $($file.Name): $($parseErrors.Message -join '; ')" }
}

foreach ($test in 'Test-AskGPT.ps1', 'Test-Providers.ps1', 'Test-KeyStorage.ps1') {
    # Separate processes isolate module mocks and environment changes from each other.
    & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $PSScriptRoot $test)
    if ($LASTEXITCODE -ne 0) { throw "$test failed with exit code $LASTEXITCODE" }
}
Write-Host 'PASS: module validation, syntax checks and all offline suites.' -ForegroundColor Green
