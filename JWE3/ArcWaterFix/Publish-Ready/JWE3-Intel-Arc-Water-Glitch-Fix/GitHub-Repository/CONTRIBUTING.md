# Contributing

Contributions are welcome when they preserve the project's strict safety and
evidence requirements.

## Before opening an issue

Run `CHECK_STATUS.bat` and include:

- GPU model;
- Intel graphics driver version;
- JWE3 file version;
- displayed `CurrentSha256`;
- Steam or another store;
- a screenshot or short video of the artifact;
- whether release 1.0.0 changed the symptom.

Never upload `JWE3.exe`, shader archives, extracted shaders or other proprietary
game assets. Hashes and small disassembly excerpts are sufficient.

## Pull requests

A pull request that adds support for another game version must include:

1. the new original executable SHA-256;
2. the new patched-copy SHA-256;
3. the expected original and replacement bytes;
4. evidence that the new offset controls the same mesh-shader capability flag;
5. an install/uninstall round-trip test;
6. an in-game visual validation on affected hardware;
7. updated documentation and changelog.

Do not copy offsets from an older game version without re-analysis. The public
installer must continue refusing every unknown hash.

## Coding rules

- Keep the installer readable PowerShell source.
- Do not add injection, hooking, DLL proxying or runtime memory patching.
- Do not add telemetry or network access.
- Restrict all file writes to the explicitly resolved JWE3 installation.
- Preserve a verified, reversible backup path.
- Do not make unsupported FPS or compatibility claims.

Run the local release builder before submitting:

```powershell
.\tools\Build-Release.ps1 -Version 1.0.0
```
