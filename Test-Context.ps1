#requires -Version 7.2
$ErrorActionPreference = 'Stop'
$module = Import-Module (Join-Path $PSScriptRoot 'AskGPT.psd1') -Force -PassThru
try {
    & $module {
        $script:provider = 'OpenAI'
        $script:replyCode = $null
        $script:choices = [Collections.Generic.Queue[string]]::new()
        function Get-GptConfiguration { [pscustomobject]@{Provider=$script:provider;AzureEndpoint='https://test.openai.azure.com';AzureDeployment='test'} }
        function Get-GptApiKey { param($Provider) 'dummy-context-key' }
        function Write-Host { param($Object,$ForegroundColor) }
        function Read-Host {
            param($Prompt)
            if (-not $script:choices.Count) { throw 'Unexpected prompt' }
            $script:choices.Dequeue()
        }
        function Invoke-RestMethod {
            param($Uri,$Method,$Headers,$Body,$ContentType,$TimeoutSec,$MaximumRedirection,$ErrorAction)
            $script:request = [Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            @{status='completed';output=@(@{type='message';content=@(@{type='output_text';text=(@{answer='Example';command=$script:replyCode}|ConvertTo-Json)})})}
        }
        function Assert($Condition,$Message) { if (-not $Condition) { throw "FAIL: $Message" } }
        function Ask($Question,$Code,[string[]]$Choices=@()) {
            $script:replyCode=$Code
            foreach ($choice in $Choices) { $script:choices.Enqueue($choice) }
            Invoke-GptQuestion -Question $Question
        }
        $result = @(Ask 'first' 'Write-Output "original"' @('e','Write-Output "edited-result"','.done','r'))
        Assert ($result[0] -eq 'edited-result') 'Execution output preserved'
        Ask 'explain that' $null
        $prior = $script:request.input[0].content
        Assert ($prior -match 'edited-result' -and $prior -match 'Executed') 'Edited command and result reach follow-up'
        Assert ($prior -notmatch 'original') 'Only reviewed edited code recorded'
        Ask 'cancel this' 'throw "must not run"' @('c')
        Ask 'what happened' $null
        Assert ($script:request.input[0].content -match 'Cancelled; not executed') 'Cancellation recorded honestly'
        $script:replyCode=$null
        Invoke-GptQuestion -Question 'private-question' -NoContext
        Assert ($script:request.input -eq 'private-question') 'NoContext does not send history'
        Ask 'continue' $null
        Assert ($script:request.input[0].content -notmatch 'private-question') 'NoContext does not store turn'
        $script:provider='AzureOpenAI'
        Ask 'azure question' $null
        Assert ($script:request.input -eq 'azure question') 'Provider isolation'
        $script:provider='OpenAI'
        Clear-GptContext
        Ask 'fresh' $null
        Assert ($script:request.input -eq 'fresh') 'Clear removes history'
        $script:replyCode=$null
        Invoke-GptQuestion -Question 'why' -NoContext -Context 'External command result: 42'
        Assert ($script:request.input[0].content -match 'result: 42') 'Explicit external context sent'
        Clear-GptContext
        $null = Ask 'long output' 'Write-Output ("x" * 8000)' @('r')
        Ask 'summarize' $null
        Assert ($script:request.input[0].content -match '"OutputTruncated":true') 'Truncation flagged'
        Assert ($script:request.input[0].content.Length -lt 7500) 'Output bounded'
        Clear-GptContext
        $failed=$false
        try { Ask 'failure' 'throw "context-test-error"' @('r') } catch { $failed=$true }
        Assert $failed 'Terminating error still reported'
        Ask 'fix it' $null
        Assert ($script:request.input[0].content -match 'context-test-error' -and $script:request.input[0].content -match 'Execution failed') 'Error reaches follow-up'
        Clear-GptContext
        foreach ($n in 1..6) { Ask "turn-$n" $null }
        Ask 'latest' $null
        Assert ($script:request.input[0].content -notmatch 'turn-1|turn-2') 'Only last four turns retained'
        Assert ($script:request.input[0].content -match 'turn-3' -and $script:request.input[0].content -match 'turn-6') 'Recent turns retained'
        Clear-GptContext
        $null = Ask 'object output' '[pscustomobject]@{Name="example";Count=42}' @('r')
        Ask 'explain object' $null
        Assert ($script:request.input[0].content -match 'example' -and $script:request.input[0].content -match '42') 'Object data captured'
        Clear-GptContext
        $null = Ask 'native failure' '& (Join-Path $PSHOME "pwsh.exe") -NoProfile -Command "exit 7"' @('r')
        Ask 'why did it fail' $null
        Assert ($script:request.input[0].content -match '"NativeExitCode":7') 'Native exit code captured'
        Assert ($script:request.input[0].content -match 'Executed with errors') 'Native failure marked'
    }
    Write-Host 'PASS: follow-ups, edited commands, output/errors, cancellation, bounded history, context clearing, opt-out and provider isolation.' -ForegroundColor Green
}
finally { Remove-Module $module -Force }
