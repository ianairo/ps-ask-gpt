# Publishing this repository

This folder is the repository root. Publish its contents, including `.github`, `.gitignore` and `.gitattributes`. Do not publish the parent workspace or `%LOCALAPPDATA%\AskGPT`.

## First push

1. Create an empty GitHub repository named `AskGPT` (or another name). Leave GitHub's README, license and gitignore initialization options unchecked because these files are included here.
2. Open PowerShell in this folder and run:

```powershell
git init -b main
git add .
git diff --cached --stat
git diff --cached
git commit -m "Prepare AskGPT beta release"
```

Review the staged diff before committing. `.gitignore` helps exclude keys and settings but is not a guarantee against secret exposure.

3. Copy the repository's HTTPS or SSH URL from GitHub and use it below:

```powershell
git remote add origin YOUR_REPOSITORY_URL
git push -u origin main
```

Git may prompt you to configure your author name/email or sign into GitHub. The module's API key is unrelated to GitHub authentication.

## First release

- Wait for the **PowerShell tests** workflow to pass.
- Enable private vulnerability reporting in the repository's security settings.
- With your own account, try an answer-only question and a harmless suggestion such as `?? show my PowerShell version`. Verify Run, Edit and Cancel. Verify each provider you intend to advertise as live-tested.
- Create a GitHub release tagged `v1.2.1-beta.1` and mark it as a **pre-release**. The module's numeric version remains `1.2.1`.
- Use `CHANGELOG.md` for the release notes, keeping any unverified live-provider limitations explicit. Users can download GitHub's source ZIP; no automatic publishing workflow or API secrets are needed.

The repository URL has intentionally not been embedded in documentation or manifest metadata because its destination is not yet known.
