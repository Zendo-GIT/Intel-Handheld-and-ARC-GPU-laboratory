# Release guide

## Build all releases

From a Windows PowerShell prompt at the repository root:

```powershell
.\tools\Build-All-Releases.ps1
```

The command validates the repository and invokes every pinned game and system-utility release builder. Each project keeps its own ignored `dist` directory, and the final ZIPs are also collected in the root `dist` directory with individual `.sha256.txt` files and a shared `SHA256SUMS.txt` manifest.

## GitHub release naming

Use game-scoped tags so versions can evolve independently:

- `jwe3-v1.0.0`
- `kena-v1.0.0`
- `ievr-v1.0.0`
- `detroit-v1.0.0`
- `claw8-vrr-v1.0.1`

Attach only the matching ZIP and checksum from `dist`. Do not attach the entire repository, source captures, backups, or publication workspace.

## Publishing the initial releases

Push the repository first, then create these releases from the GitHub **Releases** page. The tag, title, ZIP name, and capitalization must match exactly because the README download buttons use immutable asset URLs.

| Tag | Suggested title | Assets to upload |
|---|---|---|
| `jwe3-v1.0.0` | `JWE3 Intel Arc Water Glitch Fix 1.0.0` | `JWE3-Intel-Arc-Water-Glitch-Fix-1.0.0.zip` and its `.sha256.txt` file |
| `kena-v1.0.0` | `Kena Intel Arc Water Flash Fix 1.0.0` | `Kena-Intel-Arc-Water-Flash-Fix-1.0.0.zip` and its `.sha256.txt` file |
| `ievr-v1.0.0` | `IEVR Offline Stutter Fix 1.0.0` | `IEVR-Offline-Stutter-Fix-1.0.0.zip` and its `.sha256.txt` file |
| `detroit-v1.0.0` | `Detroit Intel Arc Stability Fix 1.0.0` | `Detroit-Intel-Arc-Stability-Fix-1.0.0.zip` and its `.sha256.txt` file |
| `claw8-vrr-v1.0.1` | `MSI Claw 8 AI+ / 8 EX AI+ VRR Range Fix 1.0.1` | `MSI-Claw-8-Intel-VRR-Range-Fix-1.0.1.zip` and its `.sha256.txt` file |

For each release:

1. Select **Draft a new release**.
2. Enter the exact tag from the table and create it from `master`.
3. Use the suggested title.
4. Copy the relevant game changelog and safety warning into the description.
5. Upload only the matching ZIP and `.sha256.txt` file from the root `dist` directory.
6. Publish the release and test its direct download button from the root README.

Do not mark unrelated releases as **Latest** interchangeably. The project-scoped tags and direct asset URLs are the stable distribution identifiers.

## Nexus Mods

Nexus descriptions and checklists are maintained in each project's publication documentation, not embedded as extra main-file archives. The VRR utility includes an optional Nexus draft at `utilities/msi-claw-8-intel-vrr-range-fix/docs/NEXUS_MODS.md`; GitHub remains its canonical source and issue tracker.
