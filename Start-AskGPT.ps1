# Run this from an existing PowerShell 7.2+ terminal.
# Saves the key encrypted with Windows DPAPI on first use.
#requires -Version 7.2
param([ValidateSet('OpenAI', 'AzureOpenAI')][string]$Provider)
$module = Import-Module (Join-Path $PSScriptRoot 'AskGPT.psd1') -Global -Force -PassThru
if ($Provider) { Set-GptProvider $Provider }
& $module {
    if (-not (Test-Path -LiteralPath (Get-GptConfigPath))) {
        $choice = Read-Host 'Provider: [1] OpenAI (default)  [2] Azure OpenAI'
        switch ($choice.Trim()) {
            { $_ -in '', '1' } { Set-GptProvider OpenAI }
            '2' { Set-GptProvider AzureOpenAI }
            default { throw 'Choose 1 or 2. Run setup again.' }
        }
    }
    $provider = (Get-GptConfiguration).Provider
    $environmentName = Get-GptKeyEnvironmentName $provider
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($environmentName)) -and
        -not (Test-Path -LiteralPath (Get-GptKeyPath -Provider $provider))) {
        Set-GptApiKey -Provider $provider
    }
    $null = Get-GptApiKey -Provider $provider
}
Write-Host 'Ready. Try: ?? show the five processes using the most memory' -ForegroundColor Green
