# Contributing

Use PowerShell 7.2 or later on Windows. No API key or external PowerShell test module is required for the offline suite:

```powershell
./Test-All.ps1
```

Tests use dummy keys and temporary settings. The DPAPI tests need a Windows user profile and may not run inside a restricted sandbox. Run tests in a separate terminal: the suite imports and removes the module while mocking private functions.

For behavior changes, add tests for the relevant user flow. Preserve explicit confirmation before execution, review after editing, provider credential separation, endpoint validation, and compatibility with previously saved OpenAI keys. Keep examples generic and never include real credentials, resource names or user paths.

Describe what changed and how it was verified in your pull request. Mark live API checks separately from mocked tests. Live testing is optional, uses your own account, and may incur charges; never add production API credentials to CI.
