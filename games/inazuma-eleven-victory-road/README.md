# INAZUMA ELEVEN: Victory Road Offline Stutter Fix

An experimental, reversible **offline-only** fix for the recurring one-to-two-second stutter observed in *INAZUMA ELEVEN: Victory Road* on the validated MSI Claw / Intel Arc system.

## Critical safety notice

This fix modifies `nie.exe`. It is **not compatible with Easy Anti-Cheat or online play**.

- Do not launch the patched executable through Easy Anti-Cheat.
- Do not use online game features while the patch is installed.
- The installer blocks every executable inside the game directory in Windows Firewall before changing `nie.exe`.
- The uninstaller restores the exact vanilla executable before removing those firewall rules.
- This project does not include, recommend, link to, or document an anti-cheat bypass.

If you want normal EAC or online operation, run `UNINSTALL_RESTORE_ONLINE.bat` first and verify that `CHECK_STATUS.bat` reports `ORIGINAL` and `DISABLED`.

## Download

[Download IEVR Offline Stutter Fix 1.0.1](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/download/ievr-v1.0.1/IEVR-Offline-Stutter-Fix-1.0.1.zip)

[Release notes and SHA-256 file](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/tag/ievr-v1.0.1)

Downloading the package does not change the safety boundary: this remains an offline-only executable patch that is incompatible with EAC and online play.

## What the fix changes

The supported game build performs a recurring Steam/EOS status query in a secondary game thread. ETW analysis showed that this thread repeatedly wakes the main game thread during the visible hitches. The patch changes four bytes in the identified routine so that the already-established valid state is used without repeating the synchronous Steam/EOS query.

No game executable or proprietary game data is distributed. The installer will operate only when `nie.exe` exactly matches the supported vanilla SHA-256.

## Supported build

- Store: Steam
- AppID: `2799860`
- tested build ID: `24370575`
- vanilla `nie.exe` size: `33,918,464` bytes
- vanilla SHA-256: `B1FA04EA365868E5C8933ACA393366F82D0D446187E2187F2737DC4FA2ACD40C`
- patched SHA-256: `4059F004915EC3462BB7E7348283A72C8738F9A3CCEB110C1475F2ADFBE2A3DF`

Any game update may invalidate the fix. An unknown hash is rejected without modifying the executable or firewall.

## Installation

1. Close the game, EAC launcher, and game bootstrapper.
2. Extract the release ZIP to a normal writable folder.
3. Run `INSTALL_OFFLINE_FIX.bat`.
4. Approve the Windows administrator prompt.
5. Confirm that the final status is `PATCHED` and the offline firewall isolation is `ENABLED`.
6. Use only an offline environment in which Easy Anti-Cheat is not active. No such launcher is supplied or supported by this project.

The installer automatically locates the Steam library. For a nonstandard location, run:

```powershell
.\IEVR-Offline-Stutter-Fix.ps1 -Action Install -GameDirectory "D:\path\to\INAZUMA ELEVEN Victory Road"
```

## Uninstallation and vanilla recovery

1. Close the game and all launchers.
2. Run `UNINSTALL_RESTORE_ONLINE.bat`.
3. Approve the Windows administrator prompt.
4. Confirm that the final status is `ORIGINAL` and firewall isolation is `DISABLED`.

The installer stores a verified vanilla backup under:

```text
%LOCALAPPDATA%\ClawLab\IEVR-Offline-Stutter-Fix
```

If that backup is unavailable, the uninstaller can reverse the exact four-byte patch and requires the result to match the full vanilla SHA-256. It never treats an unknown executable as safe. If the game was updated while patched, use Steam's file verification and then run the uninstaller again to remove the firewall rules.

## Validated system and recommended profile

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V / Intel Arc 140V
- 32 GB RAM
- Intel Graphics driver `32.0.101.8864`
- CPU Boost enabled
- PL1 16 W / PL2 18 W
- 60 Hz display mode
- 60 FPS limit
- VRR disabled
- V-Sync forced in MSI Center M / Command Center

The patch also ran smoothly after warm-up at 120 Hz with VRR, forced V-Sync, and a 116 FPS limit, but 60 Hz / 60 FPS is the conservative recommendation.

Short-lived cold-start shader, pipeline, or asset warm-up stutter may still occur. That behavior is separate from the recurring Steam/EOS hitch addressed here.

## Validation result

In the reference 90-second captures:

| Metric | Vanilla reference | Patched reference |
|---|---:|---:|
| 99th-percentile frame time | 36.52 ms | 19.36 ms |
| Maximum frame time | 83.40 ms | 24.05 ms |
| Detected recurring hitch events | 44 | 0 |

The public claim is deliberately narrow: the recurring periodic hitch was eliminated on the exact validated system and build. Other hardware, drivers, builds, scenes, and offline launch configurations remain unverified.

## Files

- `IEVR-Offline-Stutter-Fix.ps1` — installer, status checker, backup/restoration logic, and firewall manager.
- `INSTALL_OFFLINE_FIX.bat` — install entry point.
- `UNINSTALL_RESTORE_ONLINE.bat` — restores vanilla and re-enables network access.
- `CHECK_STATUS.bat` — read-only state check.
- `docs/TECHNICAL_DETAILS.md` — ETW evidence and exact patch explanation.
- `tools/Build-Release.ps1` — reproducible release builder.

## Credits

ClawLab — diagnosis, controlled testing, real-hardware validation, and packaging. Developed collaboratively with OpenAI Codex assistance.

This project is not affiliated with LEVEL5, Valve, Epic Games, MSI, Intel, or Nexus Mods.
