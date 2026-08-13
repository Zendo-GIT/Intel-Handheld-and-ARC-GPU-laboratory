# Release guide

## Build all releases

From a Windows PowerShell prompt at the repository root:

```powershell
.\tools\Build-All-Releases.ps1
```

The command validates the repository and invokes each game's pinned release builder. Each project keeps its own ignored `dist` directory, and the three final ZIPs are also collected in the root `dist` directory with a shared `SHA256SUMS.txt` manifest.

## GitHub release naming

Use game-scoped tags so versions can evolve independently:

- `jwe3-v1.0.0`
- `kena-v1.0.0`
- `ievr-v1.0.0`

Attach only the matching ZIP and checksum from `dist`. Do not attach the entire repository, source captures, backups, or publication workspace.

## Nexus Mods

Nexus descriptions and checklists are maintained in the laboratory publication bundle, not embedded as extra main-file archives. The GitHub game folders contain the technical and installation documentation required to review each release.
