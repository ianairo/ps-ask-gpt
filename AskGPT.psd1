@{
    RootModule = 'AskGPT.psm1'
    ModuleVersion = '1.3.0'
    GUID = 'c83d064c-503a-4431-a1b7-df6f8dc11964'
    Author = 'Ian Bugeja'
    Description = 'Ask GPT from PowerShell with the ?? alias and review commands before running.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @('Invoke-GptQuestion', 'Set-GptApiKey', 'Remove-GptApiKey', 'Set-GptProvider', 'Get-GptConfiguration', 'Clear-GptContext')
    AliasesToExport = @('??')
    CmdletsToExport = @()
    VariablesToExport = @()
}
