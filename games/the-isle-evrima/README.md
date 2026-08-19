# The Isle: Evrima MSI Claw Performance Fix

A transparent, reversible configuration profile for the severe rendering,
16:10 presentation and performance problems observed in *The Isle: Evrima* on
the MSI Claw 8 AI+ with Intel Arc 140V graphics.

![Version](https://img.shields.io/badge/release-1.0.0-blue)
![Game](https://img.shields.io/badge/Evrima-0.21.784-orange)
![Method](https://img.shields.io/badge/method-configuration--only-green)
![License](https://img.shields.io/badge/license-MIT-green)

## Download

[Download The Isle: Evrima MSI Claw Performance Fix 1.0.0](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/download/the-isle-v1.0.0/The-Isle-Evrima-MSI-Claw-Performance-Fix-1.0.0.zip)

[Release notes and SHA-256 file](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/tag/the-isle-v1.0.0)

## What it fixes

The validated profile addresses three separate problems:

- severe blocky, smeared or corrupted-looking textures and shader output;
- a broken 16:10 presentation path that rendered or cropped the interface as if
  the 1920x1200 display were a smaller 16:9 or 1280x800 surface;
- very low performance caused by unsuitable hidden Unreal Engine scalability,
  streaming and shader-precache behavior on the reference Claw.

The profile keeps the display output at 1920x1200 so VRR remains available,
while rendering the 3D scene at 40 percent, approximately 768x480. All
scalability groups are set to Low or disabled except View Distance, which is
Medium.

## Important limitation

This release does **not** eliminate every stutter. The game's own log still
records blocking shader/PSO preloads during some map and scene transitions,
including measured stalls of roughly 0.4 to 0.75 seconds. The game also forces
both D3D12 PSO disk-cache switches off before user configuration is loaded.

An attempted early disk-cache override was rejected because this shipping
build ignored it. It is not included in the release. Eliminating the remaining
engine-level stalls would require a more intrusive method that is outside the
public Easy Anti-Cheat-safe design boundary of this project.

## Validated configuration

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V
- Intel Arc 140V
- 32 GB RAM
- Intel Graphics driver `32.0.101.8974` WHQL
- Windows 11 at 150 percent desktop scaling
- The Isle: Evrima `0.21.784`
- Steam build ID `24664737`
- Internal 1920x1200 panel and native DX12 path

Other devices, game builds, drivers and display layouts are unverified. The
installer refuses an unknown Steam build rather than silently applying an old
profile.

## Installation

1. Launch Evrima once and select 1920x1200, then close the game.
2. Download and extract the release ZIP.
3. Run `INSTALL_FIX.bat`.
4. Confirm that the final state is `FIX_INSTALLED`.
5. Launch the game normally through Steam with Easy Anti-Cheat enabled.

No administrator rights are required.

## Configuration lock

The installer makes both `Engine.ini` and `GameUserSettings.ini` read-only.
This is intentional: Evrima otherwise rewrites hidden scalability values,
including foliage quality, after a session.

While the fix is installed:

- graphics changes made in the game will not persist;
- input-binding changes stored in `GameUserSettings.ini` will not persist;
- do not manually delete the ClawLab backup directory.

Run `UNINSTALL_FIX.bat` before changing graphics or input settings. The
uninstaller restores the exact pre-install files and their original attributes.
You may then configure the game and reinstall the profile.

## Removal and recovery

1. Close the game completely.
2. Run `UNINSTALL_FIX.bat`.
3. Confirm that the status is `NOT_INSTALLED`.

The exact pre-install files are stored under:

```text
%LOCALAPPDATA%\ClawLab\The-Isle-Evrima-Claw-Fix
```

Do not delete that directory before uninstalling. If it was deleted manually,
use Steam's file verification and remove or regenerate the files under
`%LOCALAPPDATA%\TheIsle\Saved\Config\WindowsClient` as appropriate. Steam file
verification does not normally restore per-user LocalAppData configuration.

## Anti-cheat boundary

This fix is **compatible by design** with the laboratory's public anti-cheat
policy:

- it changes only the current user's Unreal Engine INI files;
- it does not modify the game directory, executable, DLLs, PAKs or EAC files;
- it does not inject, hook, spoof hardware, patch memory or automate gameplay;
- it does not disable, bypass or interfere with Easy Anti-Cheat;
- the game continues to launch normally through Steam.

This is a technical design classification, not an endorsement or guarantee
from Epic Games, Easy Anti-Cheat or The Isle's developers. Stop using the
profile if a future game update or official policy rejects configuration
overrides.

## Optional system profile

The public fix does not install or modify ClawTweaks, Clawptimize, MSI Center,
Windows power plans or the ClawLab VRR utility. On the validated device, the
following manual companion settings were useful:

- approximately 25 W sustained package power;
- CPU boost enabled;
- maximum processor state at 100 percent;
- a performance-oriented Windows power mode;
- a sensible frame cap chosen for the workload and VRR range.

These settings are recommendations, not dependencies. More TDP did not remove
the game's shader-transition stalls.

## Files

- `The-Isle-Evrima-Claw-Fix.ps1` — install, status and exact restore logic.
- `INSTALL_FIX.bat` — installation entry point.
- `UNINSTALL_FIX.bat` — restores the original configuration.
- `CHECK_STATUS.bat` — read-only health check.
- `docs/TECHNICAL_DETAILS.md` — evidence, settings and known limits.
- `tools/Build-Release.ps1` — reproducible release builder.

## Building the release

From PowerShell:

```powershell
.\tools\Build-Release.ps1 -Version 1.0.0
```

The builder parses and tests the PowerShell source, rejects executables,
libraries, captures, backups and nested archives, then creates a checksummed
ZIP under `dist`.

## Credits and disclosure

ClawLab performed the diagnosis, controlled testing, real-hardware validation
and packaging. Development was assisted collaboratively by OpenAI Codex; all
public claims were checked against the packaged source and observed game logs.

This project is not affiliated with or endorsed by Afterthought LLC, Epic
Games, Easy Anti-Cheat, Valve, Intel, MSI or Nexus Mods.

## License

Original scripts and documentation are available under the [MIT License](../../LICENSE).
The game and all game assets remain the property of their respective owners.
