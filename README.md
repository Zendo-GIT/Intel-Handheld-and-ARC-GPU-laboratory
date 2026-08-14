# MSI Claw Game Optimization Lab

Game-specific compatibility fixes and evidence-driven performance investigations for MSI Claw handhelds, with a focus on Intel Arc graphics.

The laboratory publishes narrow, reversible fixes for defects that cannot be solved reliably through ordinary in-game settings. Every release documents the exact affected build, validation hardware, technical scope, restoration path, and anti-cheat boundary.

## Download a fix

Each project is distributed as an independent GitHub Release asset. You do not need to clone the repository or download the complete laboratory.

| Game | Direct download | Release page |
|---|---|---|
| Jurassic World Evolution 3 | [Download fix 1.0.0](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/download/jwe3-v1.0.0/JWE3-Intel-Arc-Water-Glitch-Fix-1.0.0.zip) | [jwe3-v1.0.0](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/tag/jwe3-v1.0.0) |
| Kena: Bridge of Spirits | [Download fix 1.0.0](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/download/kena-v1.0.0/Kena-Intel-Arc-Water-Flash-Fix-1.0.0.zip) | [kena-v1.0.0](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/tag/kena-v1.0.0) |
| INAZUMA ELEVEN: Victory Road | [Download offline fix 1.0.0](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/download/ievr-v1.0.0/IEVR-Offline-Stutter-Fix-1.0.0.zip) | [ievr-v1.0.0](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/tag/ievr-v1.0.0) |
| Detroit: Become Human | [Download stability fix 1.0.0](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/download/detroit-v1.0.0/Detroit-Intel-Arc-Stability-Fix-1.0.0.zip) | [detroit-v1.0.0](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/tag/detroit-v1.0.0) |

Read the linked game documentation before installation. The Inazuma fix is offline-only and must be uninstalled before EAC or online use.

## Published projects

| Game | Problem | Fix | Status | Safety model |
|---|---|---|---|---|
| [Jurassic World Evolution 3](games/jurassic-world-evolution-3/README.md) | Polygonal, flashing, or missing lake water on Intel Arc | Forces the engine's existing VS/SM60 fallback instead of the broken mesh-shader path | 1.0.0 validated | Local executable patch; normal Steam launch; no anti-cheat interaction |
| [Kena: Bridge of Spirits](games/kena-bridge-of-spirits/README.md) | Cyan/white flashing on calm and surface water under native DX12 | Data-only Unreal PAK neutralizing the active procedural foam contribution | 1.0.0 validated | Data-only PAK; no executable modification |
| [INAZUMA ELEVEN: Victory Road](games/inazuma-eleven-victory-road/README.md) | Recurring one-to-two-second Steam/EOS synchronization hitch | Four-byte synchronization-path patch with automatic game-network isolation | 1.0.0 validated | **Offline only; incompatible with EAC and online play** |
| [Detroit: Become Human](games/detroit-become-human/README.md) | Unsupported-GPU prompt, scaler corruption and persistent transition stalls on Intel Arc | Exact dialog suppression, safe graphics path, cache validation and chapter-only presentation recovery | 1.0.0 reference-platform validation | Six-byte patch plus optional locally compiled Steam wrapper; no DLL injection |

## Start here

Open the folder for the game you want to fix and read its safety and compatibility sections before downloading or building anything. The projects deliberately use different mechanisms because the underlying defects are different.

```text
games/
├── jurassic-world-evolution-3/
├── kena-bridge-of-spirits/
├── inazuma-eleven-victory-road/
└── detroit-become-human/
```

Each game folder contains its own installer or PAK, technical documentation, changelog, compatibility matrix, and reproducible release builder.

## Laboratory principles

- Diagnose before modifying.
- Prefer the smallest game-local change that removes the reproduced defect.
- Reject unknown builds instead of applying heuristic executable patches.
- Preserve and verify vanilla recovery for every official file modification.
- Separate periodic engine stalls, cold-start shader warm-up, Alt+Tab effects, and ordinary GPU saturation.
- Never require a global graphics-driver rollback for one game when a verified local fix is possible.
- Never bundle proprietary game executables, unmodified game assets, trainers, injectors, launchers, or anti-cheat bypasses.
- Describe observed results without claiming compatibility that was not tested.

## Anti-cheat policy

Fixes for games with anti-cheat receive a separate safety assessment. A technique that is acceptable for an unprotected single-player title is not automatically acceptable for a protected game.

The Inazuma patch is an explicit offline-only research result. It modifies the protected executable, cannot be called EAC-compatible, and must be removed before normal EAC or online use. Its installer blocks game-directory executables before patching and restores a verified vanilla executable before returning their network access. The project does not provide or link to an anti-cheat bypass.

See [Anti-cheat policy](docs/ANTI_CHEAT_POLICY.md) and each game's own documentation.

## Reference platform

Primary real-hardware validation was performed on:

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V
- Intel Arc 140V
- 32 GB RAM
- Intel Graphics driver `32.0.101.8864`
- Windows 11

This reference does not imply that every fix is exclusive to that model. It defines what was actually tested.

## Repository versus releases

The repository contains readable source, documentation, and reproducible release tooling. End users should normally download the game-specific ZIP from GitHub Releases or Nexus Mods rather than clone the entire laboratory.

Run the shared release builder from the repository root to reproduce all current packages:

```powershell
.\tools\Build-All-Releases.ps1
```

Generated archives are written inside each game's ignored `dist` directory and collected in the root `dist` directory with a shared checksum manifest. See [Release guide](docs/RELEASES.md).

## Independence

This laboratory is self-contained and does not modify external system-profile or optimization applications. Any global power, display, or driver setting mentioned in a game guide is a manually validated companion profile, not a dependency on another project.

## Credits

ClawLab — diagnosis, controlled testing, real-hardware validation, implementation, and packaging. Developed collaboratively with OpenAI Codex assistance.

This project is not affiliated with or endorsed by the game publishers, Valve, Epic Games, MSI, Intel, Microsoft, or Nexus Mods. Game names and trademarks belong to their respective owners.
