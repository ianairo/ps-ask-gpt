# Security policy

## Reporting a vulnerability

Use this repository's **Security > Report a vulnerability** option when available. Do not post API keys, credential files, personal configuration, or sensitive transcripts in public issues. If private reporting is unavailable, open an issue asking the maintainer to enable a private reporting channel without including exploit details or secrets.

## Security boundaries

- Generated commands run only after an explicit Run choice. They execute with the current user's permissions; this module is not a sandbox.
- Editing returns to the review prompt. Syntax validation does not establish that code is safe.
- On Windows, saved keys use DPAPI for the current account and computer. Software running as that account can decrypt them. Encryption does not protect a compromised session.
- The selected provider receives the question and platform information. Questions may themselves contain sensitive data. Provider retention and billing policies apply.
- Environment variable keys override saved keys only for the matching provider.
- The module sends credentials only to the selected fixed OpenAI API or validated public Azure hostname; HTTP redirects are disabled.

Never commit saved keys, including encrypted `.clixml` files. If a real key is exposed, revoke or rotate it with its provider. Deleting a file from the repository does not remove it from Git history.

This project is beta. Security fixes target the latest version; older versions have no separate maintenance commitment.
