#requires -Version 7.2
# Uses a dummy key in a unique temporary folder, never the user's saved credential.
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'These DPAPI tests require Windows.' }
$module = Import-Module (Join-Path $PSScriptRoot 'AskGPT.psd1') -Force -PassThru
$oldKey = $env:OPENAI_API_KEY
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('AskGPT-test-' + [guid]::NewGuid())
try {
    $env:OPENAI_API_KEY = ''
    & $module {
        param($Directory)
        function Get-GptConfiguration { [pscustomobject]@{ Provider = 'OpenAI' } }
        $script:testKeyPath = Join-Path $Directory 'api-key.clixml'
        function Get-GptKeyPath { param($Provider) if ($Provider -eq 'AzureOpenAI') { Join-Path (Split-Path $script:testKeyPath) 'azure-api-key.clixml' } else { $script:testKeyPath } }
        function Read-Host { param($Prompt, [switch]$AsSecureString) ConvertTo-SecureString 'dummy-api-key-for-offline-test' -AsPlainText -Force }
        function Assert($Condition, $Message) { if (-not $Condition) { throw "FAIL: $Message" } }
        Set-GptApiKey
        Assert ((Get-Content -LiteralPath $script:testKeyPath -Raw) -notmatch 'dummy-api-key') 'No plaintext in key file'
        Assert ((Get-GptApiKey) -eq 'dummy-api-key-for-offline-test') 'Decrypt saved key'
        Assert ([string]::IsNullOrEmpty($env:OPENAI_API_KEY)) 'Saved key not copied to environment'
        $oldAzureKey = $env:AZURE_OPENAI_API_KEY
        try {
            $env:AZURE_OPENAI_API_KEY = ''
            Set-GptApiKey -Provider AzureOpenAI
            Assert ((Get-GptApiKey -Provider AzureOpenAI) -eq 'dummy-api-key-for-offline-test') 'Azure key round trip'
            Remove-GptApiKey -Provider AzureOpenAI
            Assert ((Get-GptApiKey -Provider OpenAI) -eq 'dummy-api-key-for-offline-test') 'Removing Azure key preserves OpenAI key'
        }
        finally { $env:AZURE_OPENAI_API_KEY = $oldAzureKey }
        # A fresh process running as this user must also be able to decrypt it.
        $env:ASKGPT_TEST_FILE = $script:testKeyPath
        try {
            & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -Command '$key = Import-Clixml -LiteralPath $env:ASKGPT_TEST_FILE; if ([Net.NetworkCredential]::new("", $key).Password -ne "dummy-api-key-for-offline-test") { exit 1 }; $key.Dispose()'
            Assert ($LASTEXITCODE -eq 0) 'Decrypt in a new PowerShell process'
        }
        finally { Remove-Item Env:ASKGPT_TEST_FILE }
        $env:OPENAI_API_KEY = 'dummy-environment-override'
        Assert ((Get-GptApiKey) -eq 'dummy-environment-override') 'Environment override'
        $env:OPENAI_API_KEY = ''
        function Read-Host { param($Prompt, [switch]$AsSecureString) [Security.SecureString]::new() }
        $rejected = $false
        try { Set-GptApiKey } catch { $rejected = $true }
        Assert $rejected 'Reject empty key'
        Assert ((Get-GptApiKey) -eq 'dummy-api-key-for-offline-test') 'Empty entry preserves existing key'
        'invalid credential' | Set-Content -LiteralPath $script:testKeyPath
        $rejected = $false
        try { $null = Get-GptApiKey } catch { $rejected = $_.ToString() -match 'Cannot decrypt' }
        Assert $rejected 'Corrupt credential fails with recovery guidance'
        Remove-GptApiKey
        Assert (-not (Test-Path -LiteralPath $script:testKeyPath)) 'Remove saved key'
    } $testDirectory
    Write-Host 'PASS: encrypted storage, fresh-process recovery, override, empty/corrupt key handling and removal.' -ForegroundColor Green
}
finally {
    $env:OPENAI_API_KEY = $oldKey
    Remove-Module $module -Force
    # Delete only the known test file and then the empty unique test directory.
    $testFile = Join-Path $testDirectory 'api-key.clixml'
    if (Test-Path -LiteralPath $testFile) { Remove-Item -LiteralPath $testFile -Force }
    $azureTestFile = Join-Path $testDirectory 'azure-api-key.clixml'
    if (Test-Path -LiteralPath $azureTestFile) { Remove-Item -LiteralPath $azureTestFile -Force }
    if (Test-Path -LiteralPath $testDirectory) { Remove-Item -LiteralPath $testDirectory }
}
