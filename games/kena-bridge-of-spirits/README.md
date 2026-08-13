# Kena Intel Arc Water Flash Fix

A minimal, reversible DirectX 12 compatibility fix for the bright cyan or
white water flashes seen in *Kena: Bridge of Spirits* on affected Intel Arc
graphics systems.

## Download

[Download Kena Intel Arc Water Flash Fix 1.0.0](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/download/kena-v1.0.0/Kena-Intel-Arc-Water-Flash-Fix-1.0.0.zip)

[Release notes and SHA-256 file](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/tag/kena-v1.0.0)

The ZIP already contains the correct `Kena/Content/Paks/~Mods` installation structure.

## What it changes

The diagnosed Forest Path water uses this material instance:

```text
/Game/Mochi/MaterialLibrary/Water/UIWS/MI_WaterClean_Shallow
Foam_Opacity: 0.2 -> 0.0
```

This disables a subtle animated UIWS foam contribution. On the reference Intel
Arc system, the flashes disappeared and the tester could not identify a visible
loss of foam during normal play. Water color, transparency, waves, normals,
refraction, lighting, blend mode, and the compiled shader permutation are not
changed.

The release applies the identical `Foam_Opacity -> 0` correction to all 31
cooked UIWS surface-water instances in Steam build `10345375` that actually
enable the `Foam?` branch: 15 `M_Water_UIWS` surfaces and 16
`M_River_UIWS` surfaces. This includes still water and horizontally animated
rivers or ocean surfaces. True waterfalls and cascades use the separate
`M_Waterfall_*` family and are not included. See [Coverage](docs/COVERAGE.md)
for the exact asset list.

The result identifies the foam branch as the trigger. It does not claim to
identify the exact faulty Intel driver instruction or compiler behavior.

## Validated system

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V / Intel Arc 140V
- 32 GB RAM
- Intel Graphics driver `32.0.101.8864`
- Steam App ID `1954200`, build `10345375`
- Unreal Engine `4.27.2-60700+DEV`
- `Kena-Win64-Shipping.exe` SHA-256:
  `2AA94A7C678EAD73186D776B0D668BB993A90F2359AE76BC816887899D3E034B`

## Installation

1. Close the game.
2. Extract the release ZIP into the *Kena: Bridge of Spirits* installation
   directory, the folder that already contains the inner `Kena` directory.
3. Confirm that this file exists:

   ```text
   Kena/Content/Paks/~Mods/Kena-WindowsNoEditor_IntelArcWaterFlashFix_P.pak
   ```

4. Launch the game normally in DirectX 12.

Remove older experimental `ClawLabWater...Probe` PAK files before installing
the release. Only one water override should be active.

## Uninstallation

Close the game and delete only:

```text
Kena/Content/Paks/~Mods/Kena-WindowsNoEditor_IntelArcWaterFlashFix_P.pak
```

The official game PAK is never modified.

## Safety properties

- Data-only Unreal PAK override.
- No DLL, injector, proxy, overlay, hook, or memory modification.
- No executable or driver modification.
- No GPU vendor spoofing, OptiScaler, fakenvapi, or DirectX 11 dependency.
- No anti-cheat bypass or interaction.
- Fully reversible by removing one PAK.

## Compatibility limits

The defect and correction were visually validated on
`MI_WaterClean_Shallow` in Forest Path. The other 30 assets use the same active
foam contribution and have been structurally verified. The complete 31-asset
PAK also loaded the test save successfully, kept the confirmed water free of
flashes, and produced no obvious visual regression during the validation pass.
A complete location-by-location playthrough has not been performed. Other game
builds, GPUs, and drivers remain unverified.

Intel also documents strong light flashes on the water surface in this game as
a known graphics issue:

<https://www.intel.com/content/www/us/en/support/articles/000095373/graphics.html>

See [Technical details](docs/TECHNICAL_DETAILS.md),
[Coverage](docs/COVERAGE.md), and [Compatibility](docs/COMPATIBILITY.md) for
the evidence and current limits.

## Building the Nexus release

On Windows PowerShell or PowerShell 7:

```powershell
.\tools\Build-Release.ps1 -Version 1.0.0
```

The builder verifies the exact release PAK, stages the required game-relative
directory structure, generates a file manifest, and writes the ZIP and release
SHA-256 under `dist`.

## Credits

ClawLab performed the diagnosis, controlled material tests, real-hardware
validation, and packaging. Development was assisted collaboratively by OpenAI
Codex.

This project is not affiliated with Ember Lab, Intel, MSI, Steam, or Nexus
Mods. *Kena: Bridge of Spirits* and its assets remain the property of their
respective owners.

## License

Original scripts and documentation are available under the [MIT License](LICENSE).
The packaged material override is a game-specific interoperability mod and is
not relicensed as original game content.
