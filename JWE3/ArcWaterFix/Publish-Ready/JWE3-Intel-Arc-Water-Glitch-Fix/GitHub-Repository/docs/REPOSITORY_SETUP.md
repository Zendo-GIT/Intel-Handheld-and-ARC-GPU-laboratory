# Public repository setup

Recommended repository metadata:

- Repository name: `jwe3-intel-arc-water-fix`
- Visibility: **Public**
- Description: `Reversible Intel Arc mesh-shader fallback that fixes corrupted water in Jurassic World Evolution 3 1.4.2.0.`
- Topics: `jurassic-world-evolution-3`, `intel-arc`, `msi-claw`, `directx-12`, `mesh-shaders`, `bug-fix`, `powershell`
- Default branch: `main`

Recommended GitHub settings after creation:

- enable Issues;
- enable private vulnerability reporting and Security Advisories;
- keep Actions enabled for `.github/workflows/validate.yml`;
- add branch protection requiring the `Validate` workflow before merges;
- disable Wikis unless they will be maintained;
- use GitHub Releases for the same versioned ZIP uploaded to Nexus Mods.

## Create with GitHub CLI

From the prepared `GitHub-Repository` folder:

```powershell
git init -b main
git add .
git commit -m "Initial public release v1.0.0"
gh repo create jwe3-intel-arc-water-fix --public --source . --remote origin --push
```

Then create the release with the ZIP and hash from the adjacent `Nexus-Mods`
folder:

```powershell
gh release create v1.0.0 `
  ..\Nexus-Mods\JWE3-Intel-Arc-Water-Glitch-Fix-1.0.0.zip `
  ..\Nexus-Mods\RELEASE_SHA256.txt `
  --title "JWE3 Intel Arc Water Glitch Fix 1.0.0" `
  --notes-file CHANGELOG.md
```

Review the repository name, owner and files before running either command.
