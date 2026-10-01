# AskGPT for PowerShell

Ask questions with `??`, read GPT's explanation, and choose Run, Edit or Cancel for suggested code.

**Beta:** Windows with PowerShell 7.2+. Offline tests pass; live OpenAI and Azure requests have not yet been verified for this release. No PowerShell Gallery installation is currently provided.

```text
PS> ?? show my PowerShell version

Command:
$PSVersionTable.PSVersion

[R] Run  [E] Edit  [C] Cancel (default):
```

Illustrative output; answers and commands vary by model.

## Start

Requires PowerShell 7.2 or later and either an OpenAI API key or an Azure OpenAI resource key. Download and extract this repository's ZIP (or clone it), keep the folder in a stable location, and open a PowerShell 7 terminal in that folder. Run `Start-AskGPT.ps1`. First setup lets you select a provider, enter any Azure connection details, and save a hidden key encrypted. Future sessions load the saved provider and its key automatically. Existing saved OpenAI keys remain compatible.

```powershell
& './Start-AskGPT.ps1'
?? show the five processes using the most memory
?? how does this work?
?? 'What does $PSVersionTable mean?'
```

Use single quotes for questions containing PowerShell syntax such as `$`, `|`, `;`, parentheses or quotes. Ordinary unquoted words are joined with spaces. This is a PowerShell command, not a raw natural-language input mode: PowerShell parses your input first. Questions starting with a dash or matching named parameters should be supplied as `-Question 'your question'`.

## Review and execute

- **R** runs exactly the displayed code with your current permissions and location, after a syntax check.
- **E** lets you enter replacement code line by line. Enter `.done` to finish or `.cancel` to keep the original. The new code is displayed for another Run / Edit / Cancel decision; editing does not execute it.
- **C** or Enter cancels. Ctrl+C interrupts the operation.
- Answers without a suggested command just print the explanation.

GPT can make mistakes. Review code before choosing Run. Execution is not sandboxed and can change files or settings. No automatic elevation is performed. Variable and function definitions run in a child scope and do not persist in your caller scope; filesystem and other side effects do persist.

## Follow-up questions and command results

AskGPT remembers the last four interactions for each provider, endpoint and model/deployment in the current PowerShell session. It includes questions, answers, the final reviewed command, execution status, standard output and errors in the next request. For example:

```powershell
?? show the five processes using the most memory
# Choose R to run the suggestion.
?? show that in megabytes
?? explain the first result
```

Context stays in memory and is forgotten when the module is reloaded or the terminal closes. Each turn keeps up to 6,000 characters of output and 4,000 characters each of question, answer and command; truncation is marked. Cancelled commands are explicitly marked as not executed. Execution still requires Run each time. Host-only display, progress, warning and information streams are not captured as results.

**Command results may contain sensitive data.** Captured output is sent to the selected provider on your next contextual question. The current provider's API key is redacted from context, but other secrets are not automatically detected. Use these controls:

```powershell
Clear-GptContext                       # Forget all providers' session context
?? 'A standalone question' -NoContext # Neither read nor save automatic context for this turn
```

PowerShell history does not retain output from commands run outside AskGPT. You can explicitly supply previously captured output or command text:

```powershell
Get-Process | Select-Object -First 5 | Tee-Object -Variable recentResult
?? 'Explain these results' -Context ($recentResult | Out-String)

# Include the last normal shell command's text (not its results):
$lastCommand = (Get-History -Count 1).CommandLine
?? 'Explain this command' -Context $lastCommand
```

Explicit `-Context` is limited to 12,000 characters and is sent only with that request, even when `-NoContext` is used. Its contents are not automatically saved for later turns. AskGPT never reruns a previous command to recover output.

## Configuration

### Choose OpenAI or Azure OpenAI

Run the launcher with your chosen provider. For Azure it prompts for the resource endpoint, deployment name and key when they are not already configured:

```powershell
& './Start-AskGPT.ps1' -Provider AzureOpenAI
# Or:
& './Start-AskGPT.ps1' -Provider OpenAI
```

After importing the module, you can also configure it directly:

```powershell
Set-GptProvider AzureOpenAI -Endpoint 'https://YOUR-RESOURCE.openai.azure.com/' -Deployment 'YOUR-DEPLOYMENT-NAME'
Set-GptApiKey -Provider AzureOpenAI
?? show the five processes using the most memory

# Switch back; existing keys and Azure connection settings are retained:
Set-GptProvider OpenAI
Get-GptConfiguration
```

Replace the example resource and deployment names with yours. Azure needs a deployed model and region that support both the Responses API and Structured Outputs. The deployment name can differ from the underlying model name. This module uses Azure's `/openai/v1/responses` endpoint with the `api-key` header; no dated `api-version` setting is needed. Accepted endpoints are HTTPS public Azure resource URLs ending in `.openai.azure.com`, `.services.ai.azure.com`, or `.cognitiveservices.azure.com`, optionally with `/openai/v1/`. Use the endpoint shown for your resource in Azure; accepting a hostname does not establish that its resource/deployment supports Responses. Custom gateways and sovereign-cloud endpoints are not supported by this version.

The provider choice and Azure connection details persist in `%LOCALAPPDATA%\AskGPT\settings.json`. Keys are stored separately, encrypted. There is no automatic provider fallback. `OPENAI_API_KEY` overrides only the OpenAI saved key; `AZURE_OPENAI_API_KEY` overrides only the Azure saved key. `OPENAI_MODEL` applies only to OpenAI; on Azure, `-Model` is an optional deployment-name override for that question.

Azure reference: https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/responses

### Saved API key (Windows)

OpenAI's key is stored at `%LOCALAPPDATA%\AskGPT\api-key.clixml`; Azure's key is stored separately in `azure-api-key.clixml` in the same folder. Both are encrypted using Windows DPAPI for your Windows account on this computer. Keys are not saved in your PowerShell profile, source code, shell history or a persistent environment variable. Other programs running as your Windows account can also decrypt them; this protects storage, not a compromised account. Plaintext is needed briefly in memory when making the API request.

```powershell
Set-GptApiKey     # Enter or replace the active provider's saved key
Remove-GptApiKey  # Delete the active provider's saved key (does not revoke it)
# Or manage either provider explicitly:
Set-GptApiKey -Provider AzureOpenAI
Remove-GptApiKey -Provider OpenAI
```

If you already have an `OPENAI_API_KEY` variable, run `Set-GptApiKey` to save a key explicitly. To use the saved key in the current terminal, run `Remove-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue`. Persistent environment settings, if any, must be removed separately. Move to another computer or Windows account? Run `Set-GptApiKey` there again. Non-Windows users can import the module and use `OPENAI_API_KEY`; encrypted file storage is intentionally Windows-only.

Storage reference: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/export-clixml

The default model is `gpt-4.1-mini`. Select another Responses API model that supports Structured Outputs:

```powershell
$env:OPENAI_MODEL = 'your-model-id'
?? 'List running services'
# Or choose for one question:
Invoke-GptQuestion -Question 'List running services' -Model 'your-model-id'
```

Your question, PowerShell version, OS description, recent AskGPT context (unless `-NoContext`) and any explicit `-Context` are sent to the selected provider. The module does not automatically collect files, shell history, working-directory contents or environment variables for its prompt. Commands you approve can print such data, and that output can become context. Requests use `store: false` and locally replayed history rather than provider-side conversation IDs; this is not a claim of zero provider retention. API calls use the selected provider's account or Azure resource.

## Load automatically (optional)

Keep this folder in a stable location. Add `Import-Module 'FULL-PATH-TO-AskGPT/AskGPT.psd1'` to your PowerShell `$PROFILE`. After saving your key once, `??` will retrieve it automatically whenever needed. Keep the key itself out of your profile and source files. Importing replaces any existing `??` alias but leaves `?` unchanged.

From the module folder, this block adds the correct absolute path to your profile without adding it twice:

```powershell
$modulePath = (Resolve-Path './AskGPT.psd1').Path.Replace("'", "''")
$importLine = "Import-Module '$modulePath'"
New-Item -ItemType Directory -Path (Split-Path $PROFILE) -Force | Out-Null
if (!(Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE | Out-Null }
if ($importLine -notin (Get-Content $PROFILE)) { Add-Content $PROFILE -Value "`n$importLine" }
```

To uninstall, remove that import line from your profile and delete the module folder. Run `Remove-GptApiKey -Provider OpenAI` and `Remove-GptApiKey -Provider AzureOpenAI` first if you also want to delete saved credentials. Provider settings remain in `%LOCALAPPDATA%\AskGPT\settings.json` until you remove that file.

## Troubleshooting

- **`??` is not recognized:** run the launcher in this terminal or import `AskGPT.psd1` explicitly.
- **Scripts are blocked:** check `Get-ExecutionPolicy -List` and follow your organization's policy. Downloaded files may require unblocking after review. This module does not change execution policy.
- **Authentication or deployment error:** check the selected provider with `Get-GptConfiguration`; ensure the key matches the resource and that the deployment supports Responses and Structured Outputs.
- **Saved key cannot be decrypted:** run `Set-GptApiKey` again on this Windows account and computer.

## Verification

Run `./Test-AskGPT.ps1` and `./Test-Providers.ps1` for offline tests. These simulate API responses and keyboard input, test provider routing and the confirmation boundary, and run only harmless test commands. `./Test-KeyStorage.ps1` tests DPAPI with dummy keys and needs access to your Windows user profile. All tests use isolated test settings. A real API request needs your key and model/deployment access.

API implementation reference: https://developers.openai.com/api/docs/guides/structured-outputs

Run all checks in one command with `./Test-All.ps1`. GitHub Actions runs the same suite on Windows without live API keys.

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and [CHANGELOG.md](CHANGELOG.md). Released under the [MIT license](LICENSE). Maintainers can use [PUBLISHING.md](PUBLISHING.md) for the first push and beta release.
