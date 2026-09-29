#requires -Version 7.2
$ErrorActionPreference = 'Stop'
$module = Import-Module (Join-Path $PSScriptRoot 'AskGPT.psd1') -Force -PassThru
$oldKey = $env:OPENAI_API_KEY
try {
    $env:OPENAI_API_KEY = 'offline-test-key'
    & $module {
        function Get-GptConfiguration { [pscustomobject]@{ Provider = 'OpenAI' } }
        function Get-GptKeyPath { Join-Path ([IO.Path]::GetTempPath()) ('AskGPT-offline-' + [guid]::NewGuid() + '.clixml') }
        $script:reads = [Collections.Generic.Queue[string]]::new()
        $script:transcript = [Collections.Generic.List[string]]::new()
        $script:mode = 'normal'
        function Read-Host {
            param($Prompt)
            if ($script:reads.Count -eq 0) { throw "Unexpected prompt: $Prompt" }
            $script:reads.Dequeue()
        }
        function Write-Host {
            param([Parameter(Position=0)]$Object, $ForegroundColor)
            $script:transcript.Add([string]$Object)
        }
        function Invoke-RestMethod {
            param($Uri, $Method, $Headers, $ContentType, $Body, $TimeoutSec, $MaximumRedirection, $ErrorAction)
            $script:request = [Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            if ($Uri -ne 'https://api.openai.com/v1/responses') { throw 'Wrong endpoint' }
            if ($script:mode -eq 'network') { throw 'Simulated network failure' }
            $content = @{type='output_text'; text=(@{answer='Test explanation';command=$script:code} | ConvertTo-Json)}
            switch ($script:mode) {
                'refusal' { $content = @{type='refusal'; refusal='No'} }
                'malformed' { $content.text = 'not json' }
                'shape' { $content.text = '{"answer":"Missing command"}' }
            }
            @{status=$(if ($script:mode -eq 'incomplete') {'incomplete'} else {'completed'});output=@(@{type='message';content=@($content)})}
        }
        function Assert($Condition, $Message) { if (-not $Condition) { throw "FAIL: $Message" } }
        function Scenario($Code, [string[]]$Inputs) {
            $script:code = $Code
            $script:reads.Clear()
            $script:transcript.Clear()
            foreach ($entry in $Inputs) { $script:reads.Enqueue($entry) }
            $result = @(?? how does this work?)
            Assert ($script:reads.Count -eq 0) 'All expected prompts consumed'
            return ,$result
        }
        $result = Scenario 'throw "Executed without permission"' @('')
        Assert ($result.Count -eq 0) 'Enter cancels'
        Assert ($script:request.input -eq 'how does this work?') 'Unquoted question preserved'
        Assert ($script:request.store -eq $false) 'Response storage disabled'
        Assert ($script:request.text.format.strict -eq $true) 'Structured output enabled'
        $result = Scenario 'Write-Output "approved"' @('r')
        Assert ($result[0] -eq 'approved') 'Run executes reviewed command'
        $result = Scenario 'throw "Original executed"' @('e', 'Write-Output "edited"', '.done', 'r')
        Assert ($result[0] -eq 'edited') 'Edit executes only edited code after Run'
        Assert ($script:transcript.Contains('Write-Output "edited"')) 'Edited code displayed'
        $result = Scenario 'throw "Original executed"' @('e', 'throw "Edit executed"', '.done', 'c')
        Assert ($result.Count -eq 0) 'Edit then Cancel does not execute'
        $result = Scenario 'Write-Output "kept"' @('e', '.cancel', 'r')
        Assert ($result[0] -eq 'kept') 'Cancel editing preserves original'
        $result = Scenario 'Write-Output (' @('r', 'c')
        Assert (($script:transcript -join '') -match 'Invalid PowerShell') 'Invalid syntax blocked'
        $result = Scenario "Write-Output 'hidden$([char]27)'" @('r', 'c')
        Assert (($script:transcript -join '') -match 'hidden control') 'Terminal controls blocked'
        $result = Scenario $null @()
        Assert ($result.Count -eq 0) 'Answer-only response has no execution prompt'
        $result = Scenario 'throw "Executed"' @('yes', 'c')
        Assert ($result.Count -eq 0) 'Unknown choice cannot execute'
        foreach ($mode in @('refusal', 'malformed', 'shape', 'incomplete', 'network')) {
            $script:mode = $mode
            $failed = $false
            try { $null = Scenario 'throw "Executed"' @() } catch { $failed = $true }
            Assert $failed "Reject $mode response"
        }
        $script:mode = 'normal'
        $env:OPENAI_API_KEY = ''
        $failed = $false
        try { $null = Scenario $null @() } catch { $failed = $_.ToString() -match 'OPENAI_API_KEY' }
        Assert $failed 'Missing key produces setup guidance'
    }
    Write-Host 'PASS: 15 offline scenarios, including run/edit/cancel, invalid code, API errors and missing key.' -ForegroundColor Green
}
finally {
    $env:OPENAI_API_KEY = $oldKey
    Remove-Module $module -Force
}
