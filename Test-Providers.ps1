#requires -Version 7.2
$ErrorActionPreference = 'Stop'
$module = Import-Module (Join-Path $PSScriptRoot 'AskGPT.psd1') -Force -PassThru
$oldOpenAI = $env:OPENAI_API_KEY
$oldAzure = $env:AZURE_OPENAI_API_KEY
$oldModel = $env:OPENAI_MODEL
$directory = Join-Path ([IO.Path]::GetTempPath()) ('AskGPT-provider-test-' + [guid]::NewGuid())
try {
    $env:OPENAI_API_KEY = 'dummy-openai-key'
    $env:AZURE_OPENAI_API_KEY = 'dummy-azure-key'
    $env:OPENAI_MODEL = 'openai-only-model'
    & $module {
        param($Directory)
        $script:testConfig = Join-Path $Directory 'settings.json'
        function Get-GptConfigPath { $script:testConfig }
        function Get-GptKeyPath { param($Provider) Join-Path (Split-Path $script:testConfig) "$Provider.clixml" }
        function Assert($Condition, $Message) { if (-not $Condition) { throw "FAIL: $Message" } }
        function Invoke-RestMethod {
            param($Uri, $Method, $Headers, $Body, $ContentType, $TimeoutSec, $MaximumRedirection, $ErrorAction)
            $script:lastCall = @{ Uri=$Uri; Headers=$Headers; Body=([Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json); Redirects=$MaximumRedirection }
            @{status='completed';output=@(@{type='message';content=@(@{type='output_text';text='{"answer":"Test answer","command":null}'})})}
        }
        Assert ((Get-GptConfiguration).Provider -eq 'OpenAI') 'Existing users default to OpenAI'
        $null = Get-GptSuggestion -Question 'test'
        Assert ($script:lastCall.Uri -eq 'https://api.openai.com/v1/responses') 'OpenAI route'
        Assert ($script:lastCall.Headers.Authorization -eq 'Bearer dummy-openai-key') 'OpenAI auth'
        Assert (-not $script:lastCall.Headers.ContainsKey('api-key')) 'Azure key not sent to OpenAI'
        Set-GptProvider AzureOpenAI -Endpoint 'https://test-resource.openai.azure.com/openai/v1/' -Deployment 'my-deployment'
        Assert ((Get-GptConfiguration).AzureEndpoint -eq 'https://test-resource.openai.azure.com') 'Normalize v1 endpoint'
        $null = Get-GptSuggestion -Question 'test'
        Assert ($script:lastCall.Uri -eq 'https://test-resource.openai.azure.com/openai/v1/responses') 'Azure v1 route'
        Assert ($script:lastCall.Headers['api-key'] -eq 'dummy-azure-key') 'Azure auth'
        Assert (-not $script:lastCall.Headers.ContainsKey('Authorization')) 'OpenAI key not sent to Azure'
        Assert ($script:lastCall.Body.model -eq 'my-deployment') 'Azure uses deployment, ignores OPENAI_MODEL'
        Assert ($script:lastCall.Redirects -eq 0) 'Authenticated redirects disabled'
        $null = Get-GptSuggestion -Question 'test' -Model 'another-deployment'
        Assert ($script:lastCall.Body.model -eq 'another-deployment') 'Explicit deployment override'
        Assert ((ConvertTo-GptAzureEndpoint 'https://test-resource.services.ai.azure.com/') -eq 'https://test-resource.services.ai.azure.com') 'Foundry endpoint accepted'
        Set-GptProvider AzureOpenAI -Endpoint 'https://test-resource.cognitiveservices.azure.com/' -Deployment 'my-deployment'
        $null = Get-GptSuggestion -Question 'test'
        Assert ($script:lastCall.Uri -eq 'https://test-resource.cognitiveservices.azure.com/openai/v1/responses') 'Cognitive Services endpoint accepted and routed without changing hostname'
        $failed = $false
        try { $null = ConvertTo-GptAzureEndpoint 'https://test-resource.cognitiveservices.azure.com.evil.test/' } catch { $failed = $true }
        Assert $failed 'Reject lookalike Cognitive Services hostname'
        foreach ($endpoint in @('http://test.openai.azure.com', 'https://example.com', 'https://test.openai.azure.com.evil.test', 'https://test.openai.azure.com/?key=oops', 'https://test.openai.azure.com/openai/deployments/x', 'https://user@test.openai.azure.com')) {
            $failed = $false
            try { Set-GptProvider AzureOpenAI -Endpoint $endpoint -Deployment 'test' } catch { $failed = $true }
            Assert $failed "Reject invalid endpoint $endpoint"
        }
        Assert ((Get-GptConfiguration).AzureDeployment -eq 'my-deployment') 'Failed setup preserves settings'
        $env:AZURE_OPENAI_API_KEY = ''
        $failed = $false
        try { $null = Get-GptSuggestion -Question 'test' } catch { $failed = $_.ToString() -match 'AZURE_OPENAI_API_KEY' }
        Assert $failed 'No fallback to OpenAI key when Azure key missing'
        Set-GptProvider OpenAI
        $null = Get-GptSuggestion -Question 'test'
        Assert ($script:lastCall.Body.model -eq 'openai-only-model') 'Switch back to OpenAI'
        Set-GptProvider AzureOpenAI
        Assert ((Get-GptConfiguration).AzureDeployment -eq 'my-deployment') 'Remember Azure settings across provider switches'
        Assert ((Get-Content $script:testConfig -Raw) -notmatch 'dummy-.*key') 'Settings contain no credentials'
    } $directory
    Write-Host 'PASS: provider routing, separate credentials, persisted settings, endpoint validation and model/deployment selection.' -ForegroundColor Green
}
finally {
    $env:OPENAI_API_KEY = $oldOpenAI
    $env:AZURE_OPENAI_API_KEY = $oldAzure
    $env:OPENAI_MODEL = $oldModel
    Remove-Module $module -Force
    $file = Join-Path $directory 'settings.json'
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory }
}
