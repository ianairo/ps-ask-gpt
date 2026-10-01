# Changelog

## 1.3.0 — 2026-10-01 (beta)

- Remember the last four AskGPT turns per provider, endpoint and model/deployment in session memory.
- Include the actual edited/executed command, bounded output, errors and execution status in follow-ups.
- Add `Clear-GptContext`, `-NoContext` and explicit `-Context` for separately captured shell results.
- Add offline context regression tests. Live-provider verification remains outstanding.

## 1.2.1 — 2026-09-29 (beta)

Initial public release candidate, including:

- `??` questions with OpenAI or Azure OpenAI.
- Answers and optional PowerShell commands with Run / Edit / Cancel.
- Separate encrypted Windows key storage for both providers.
- Persisted Azure endpoint, deployment name and provider selection.
- Public Azure OpenAI, Foundry and Cognitive Services endpoint formats.
- Offline behavior, provider-routing and DPAPI tests.
- MIT license, contribution and security guidance, and Windows GitHub Actions CI.

Live requests against OpenAI and Azure have not been verified as part of this release preparation. Hosted CI has not run until the repository is pushed to GitHub.
