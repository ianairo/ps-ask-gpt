function Get-GptConfigPath {
    Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AskGPT/settings.json'
}

function Get-GptConfiguration {
    [CmdletBinding()]
    param()
    $settings = [pscustomobject]@{ Provider = 'OpenAI'; AzureEndpoint = ''; AzureDeployment = '' }
    $path = Get-GptConfigPath
    if (Test-Path -LiteralPath $path) {
        try {
            $saved = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($saved.Provider -notin @('OpenAI', 'AzureOpenAI')) { throw 'Invalid provider' }
            $settings.Provider = $saved.Provider
            $settings.AzureEndpoint = [string]$saved.AzureEndpoint
            $settings.AzureDeployment = [string]$saved.AzureDeployment
        }
        catch { throw 'Cannot read AskGPT settings.json. Correct or remove that file and run setup again.' }
    }
    $settings
}

function ConvertTo-GptAzureEndpoint {
    param([string]$Endpoint)
    $uri = $null
    if (-not [uri]::TryCreate($Endpoint.Trim(), [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or -not $uri.IsDefaultPort -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or
        $uri.DnsSafeHost -notmatch '^[a-z0-9-]+\.(openai\.azure\.com|services\.ai\.azure\.com|cognitiveservices\.azure\.com)$' -or
        $uri.AbsolutePath.TrimEnd('/') -notin @('', '/openai/v1')) {
        throw 'Enter an Azure HTTPS resource endpoint such as https://my-resource.openai.azure.com/ (optionally ending in /openai/v1/).'
    }
    $uri.GetLeftPart([UriPartial]::Authority)
}

function Set-GptProvider {
    <# .SYNOPSIS
    Save the active provider and optional Azure resource endpoint and deployment name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][ValidateSet('OpenAI', 'AzureOpenAI')][string]$Provider,
        [string]$Endpoint,
        [string]$Deployment
    )
    $settings = Get-GptConfiguration
    if ($Provider -eq 'AzureOpenAI') {
        if (-not $PSBoundParameters.ContainsKey('Endpoint')) { $Endpoint = $settings.AzureEndpoint }
        if (-not $PSBoundParameters.ContainsKey('Deployment')) { $Deployment = $settings.AzureDeployment }
        if ([string]::IsNullOrWhiteSpace($Endpoint)) { $Endpoint = Read-Host 'Azure OpenAI resource endpoint' }
        if ([string]::IsNullOrWhiteSpace($Deployment)) { $Deployment = Read-Host 'Azure OpenAI deployment name' }
        if ([string]::IsNullOrWhiteSpace($Deployment)) { throw 'An Azure deployment name is required.' }
        $settings.AzureEndpoint = ConvertTo-GptAzureEndpoint $Endpoint
        $settings.AzureDeployment = $Deployment.Trim()
    }
    elseif ($PSBoundParameters.ContainsKey('Endpoint') -or $PSBoundParameters.ContainsKey('Deployment')) {
        throw 'Endpoint and Deployment apply only to AzureOpenAI.'
    }
    $settings.Provider = $Provider
    $path = Get-GptConfigPath
    $directory = Split-Path -Parent $path
    $null = New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop
    $temporaryPath = Join-Path $directory ([IO.Path]::GetRandomFileName())
    try {
        $settings | ConvertTo-Json | Set-Content -LiteralPath $temporaryPath -Encoding utf8 -ErrorAction Stop
        Move-Item -LiteralPath $temporaryPath -Destination $path -Force -ErrorAction Stop
    }
    finally { if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force } }
    Write-Host "Provider saved: $Provider"
}

function Get-GptKeyEnvironmentName {
    param([ValidateSet('OpenAI', 'AzureOpenAI')][string]$Provider)
    if ($Provider -eq 'AzureOpenAI') { 'AZURE_OPENAI_API_KEY' } else { 'OPENAI_API_KEY' }
}

function Get-GptKeyPath {
    param([ValidateSet('OpenAI', 'AzureOpenAI')][string]$Provider = 'OpenAI')
    if (-not $IsWindows) { throw 'Encrypted key storage requires Windows. Use OPENAI_API_KEY on other platforms.' }
    $file = if ($Provider -eq 'AzureOpenAI') { 'azure-api-key.clixml' } else { 'api-key.clixml' }
    Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) "AskGPT/$file"
}

function Set-GptApiKey {
    <# .SYNOPSIS
    Prompt for and save an API key encrypted for the current Windows user.
    #>
    [CmdletBinding()]
    param([ValidateSet('OpenAI', 'AzureOpenAI')][string]$Provider = (Get-GptConfiguration).Provider)
    $path = Get-GptKeyPath -Provider $Provider
    $key = Read-Host "$Provider API key (saved encrypted for your Windows account)" -AsSecureString
    try {
        if ($null -eq $key -or $key.Length -eq 0) { throw 'No key entered. The saved key was not changed.' }
        $directory = Split-Path -Parent $path
        $null = New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop
        $temporaryPath = Join-Path $directory ([IO.Path]::GetRandomFileName())
        try {
            # SecureString serialization uses Windows DPAPI, not plaintext or a bundled encryption key.
            $key | Export-Clixml -LiteralPath $temporaryPath -ErrorAction Stop
            Move-Item -LiteralPath $temporaryPath -Destination $path -Force -ErrorAction Stop
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
        }
        Write-Host 'API key saved encrypted. Future sessions will load it automatically.' -ForegroundColor Green
        $environmentName = Get-GptKeyEnvironmentName $Provider
        if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($environmentName))) {
            Write-Warning "$environmentName is set and takes precedence. Remove that environment variable to use the saved key."
        }
    }
    finally { if ($null -ne $key) { $key.Dispose() } }
}

function Remove-GptApiKey {
    <# .SYNOPSIS
    Delete the saved encrypted key. Does not revoke it at OpenAI or change environment variables.
    #>
    [CmdletBinding()]
    param([ValidateSet('OpenAI', 'AzureOpenAI')][string]$Provider = (Get-GptConfiguration).Provider)
    $path = Get-GptKeyPath -Provider $Provider
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
    Write-Host "Saved $Provider key removed. Environment variables remain unchanged."
}

function Get-GptApiKey {
    param([ValidateSet('OpenAI', 'AzureOpenAI')][string]$Provider = (Get-GptConfiguration).Provider)
    $environmentName = Get-GptKeyEnvironmentName $Provider
    $environmentKey = [Environment]::GetEnvironmentVariable($environmentName)
    if (-not [string]::IsNullOrWhiteSpace($environmentKey)) { return $environmentKey }
    if (-not $IsWindows) { throw "Set $environmentName before asking a question." }
    $path = Get-GptKeyPath -Provider $Provider
    if (-not (Test-Path -LiteralPath $path)) { throw "Run Set-GptApiKey -Provider $Provider once to save your key, or set $environmentName." }
    $key = $null
    try {
        $key = Import-Clixml -LiteralPath $path -ErrorAction Stop
        if ($key -isnot [Security.SecureString] -or $key.Length -eq 0) { throw 'Invalid key file' }
        # Plaintext exists only in memory for the authenticated request, never in an environment variable.
        [Net.NetworkCredential]::new('', $key).Password
    }
    catch { throw "Cannot decrypt the saved $Provider API key. Run Set-GptApiKey -Provider $Provider to save it again under this Windows account." }
    finally { if ($key -is [Security.SecureString]) { $key.Dispose() } }
}

function ConvertTo-VisibleText {
    param([string]$Text)
    # Prevent terminal escape sequences from hiding or rewriting reviewed code.
    [regex]::Replace($Text, '[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]', {
        param($Match)
        if ($Match.Value -in @("`r", "`n", "`t")) { return $Match.Value }
        '\u{0:X4}' -f [int][char]$Match.Value
    })
}

function Get-GptSuggestion {
    param([string]$Question, [string]$Model)
    $settings = Get-GptConfiguration
    $provider = $settings.Provider
    if ($provider -eq 'AzureOpenAI') {
        $uri = (ConvertTo-GptAzureEndpoint $settings.AzureEndpoint) + '/openai/v1/responses'
        if ([string]::IsNullOrWhiteSpace($Model)) { $Model = $settings.AzureDeployment }
        if ([string]::IsNullOrWhiteSpace($Model)) { throw 'Run Set-GptProvider AzureOpenAI to configure your deployment.' }
    }
    else {
        $uri = 'https://api.openai.com/v1/responses'
        if ([string]::IsNullOrWhiteSpace($Model)) { $Model = if ($env:OPENAI_MODEL) { $env:OPENAI_MODEL } else { 'gpt-4.1-mini' } }
    }
    $apiKey = Get-GptApiKey -Provider $provider
    $headers = if ($provider -eq 'AzureOpenAI') { @{ 'api-key' = $apiKey } } else { @{ Authorization = "Bearer $apiKey" } }
    $schema = @{
        type = 'object'
        properties = @{
            answer = @{ type = 'string' }
            command = @{ type = @('string', 'null') }
        }
        required = @('answer', 'command')
        additionalProperties = $false
    }
    $body = @{
        model = $Model
        store = $false
        instructions = @"
You are a concise PowerShell assistant. The user is using PowerShell $($PSVersionTable.PSVersion) on $([System.Runtime.InteropServices.RuntimeInformation]::OSDescription).
Answer the user's question. When useful, provide one PowerShell command or script in command, without Markdown fences. Otherwise set command to null.
Explain what the command does and mention material side effects or required privileges. Prefer read-only commands when they answer the question.
If essential details are missing, ask for them in answer and set command to null. Never invent paths or use placeholders in runnable commands.
Do not claim to have run commands or inspected the computer. Only the question and platform information are supplied.
Use readable PowerShell, not encoded or obfuscated commands. Never request automatic execution or bypass the user's review.
"@
        input = $Question
        text = @{ format = @{ type = 'json_schema'; name = 'powershell_answer'; strict = $true; schema = $schema } }
        max_output_tokens = 4096
    } | ConvertTo-Json -Depth 12 -Compress
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post `
            -Headers $headers `
            -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) `
            -TimeoutSec 120 -MaximumRedirection 0 -ErrorAction Stop
    }
    catch {
        $status = $_.Exception.Response.StatusCode
        if ($null -ne $status) {
            throw "$provider request failed (HTTP $([int]$status)). Check your API key, endpoint, model/deployment access, billing or rate limits."
        }
        throw "$provider request failed. Check your connection and endpoint; the request may have timed out."
    }
    finally { $apiKey = $null; $headers = $null }
    if ($response.status -ne 'completed') { throw 'OpenAI returned an incomplete response. Nothing was executed; try again.' }
    $parts = @()
    foreach ($item in $response.output) {
        if ($item.type -eq 'message') {
            foreach ($content in $item.content) {
                if ($content.type -eq 'refusal') { throw 'GPT declined this request. Nothing was executed.' }
                if ($content.type -eq 'output_text') { $parts += $content.text }
            }
        }
    }
    try { $result = ($parts -join '') | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'OpenAI returned invalid JSON. Nothing was executed.' }
    if ($null -eq $result -or $result.answer -isnot [string] -or
        'command' -notin $result.PSObject.Properties.Name -or
        ($null -ne $result.command -and $result.command -isnot [string])) {
        throw 'OpenAI returned an unexpected answer format. Nothing was executed.'
    }
    $result
}

function Read-GptCommandEdit {
    param([string]$Command)
    Write-Host 'Enter replacement code, one line at a time. Type .done on its own line to finish, or .cancel to keep the original.'
    $lines = [Collections.Generic.List[string]]::new()
    while ($true) {
        $line = Read-Host 'edit'
        if ($null -eq $line -or $line -eq '.cancel') { return $Command }
        if ($line -eq '.done') { return ($lines -join "`n") }
        $lines.Add($line)
    }
}

function Invoke-GptQuestion {
    <#
    .SYNOPSIS
    Ask GPT a question and review optional PowerShell code before execution.
    .EXAMPLE
    ?? show the five processes using the most memory
    .EXAMPLE
    ?? 'What does $PSVersionTable mean?'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Question,
        [string]$Model
    )
    $text = ($Question -join ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { $text = Read-Host 'Ask GPT' }
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    Write-Host 'Asking GPT...' -ForegroundColor DarkGray
    $suggestion = Get-GptSuggestion -Question $text -Model $Model
    Write-Host "`n$(ConvertTo-VisibleText $suggestion.answer)"
    $command = $suggestion.command
    if ([string]::IsNullOrWhiteSpace($command)) { return }

    while ($true) {
        Write-Host "`nCommand:" -ForegroundColor Cyan
        Write-Host (ConvertTo-VisibleText $command) -ForegroundColor Yellow
        Write-Host ''
        $choice = Read-Host '[R] Run  [E] Edit  [C] Cancel (default)'
        switch ($choice.Trim().ToLowerInvariant()) {
            { $_ -in 'r', 'run' } {
                if ([string]::IsNullOrWhiteSpace($command)) { Write-Host 'No command to run.'; return }
                if ($command -match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F\p{Cf}\p{Zl}\p{Zp}]') {
                    Write-Host 'Command contains hidden control characters. Edit it before running.' -ForegroundColor Red
                    continue
                }
                $tokens = $null
                $parseErrors = $null
                $ast = [Management.Automation.Language.Parser]::ParseInput($command, [ref]$tokens, [ref]$parseErrors)
                if ($parseErrors.Count -gt 0) {
                    Write-Host "Invalid PowerShell: $(ConvertTo-VisibleText ($parseErrors.Message -join '; '))" -ForegroundColor Red
                    continue
                }
                # This is the only execution point, reached only after explicit Run.
                # Child scope: variable/function definitions do not persist in the caller.
                & $ast.GetScriptBlock()
                return
            }
            { $_ -in 'e', 'edit' } { $command = Read-GptCommandEdit -Command $command }
            { $_ -in '', 'c', 'cancel' } { Write-Host 'Cancelled.'; return }
            default { Write-Host 'Choose R, E, or C.' }
        }
    }
}

Set-Alias -Name '??' -Value Invoke-GptQuestion
Export-ModuleMember -Function Invoke-GptQuestion, Set-GptApiKey, Remove-GptApiKey, Set-GptProvider, Get-GptConfiguration -Alias '??'
