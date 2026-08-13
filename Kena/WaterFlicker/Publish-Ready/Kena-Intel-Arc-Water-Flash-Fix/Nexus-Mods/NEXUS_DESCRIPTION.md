# Kena Intel Arc Water Flash Fix

Removes the bright cyan/white flashes affecting water in *Kena: Bridge of
Spirits* on the validated Intel Arc system while keeping the game on native
DirectX 12.

## What the mod does

The confirmed Forest Path material was fixed by changing `Foam_Opacity` from
`0.2` to `0.0`. This disables a subtle procedural foam contribution that
triggered the flashing on the affected Intel rendering path. During
validation, the flashes disappeared and no visible loss of foam could be
identified in normal play.

Version 1.0.0 applies the same correction to all 31 UIWS surface-water
instances in the tested build that enable the `Foam?` branch. This includes
still water and horizontally animated river/ocean surfaces. True waterfalls
and cascades use a separate material family and are not touched.

It does not change water color, transparency, waves, normals, refraction,
lighting, or blend mode.

## Installation

Close the game and extract the ZIP into the game installation directory. The
PAK must end up at:

```text
Kena/Content/Paks/~Mods/Kena-WindowsNoEditor_IntelArcWaterFlashFix_P.pak
```

Remove any older `ClawLabWater...Probe` PAK first, then launch normally in
DirectX 12.

## Uninstallation

Close the game and remove the PAK above. No official game file is modified.

## Validated on

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V / Intel Arc 140V
- Intel Graphics driver 32.0.101.8864
- Steam build 10345375
- Native DirectX 12

## Safety

This is a data-only Unreal PAK. It contains no DLL, executable, injector,
proxy, hook, overlay, memory modification, GPU spoof, or anti-cheat bypass.
OptiScaler, fakenvapi, DirectX 11, and a driver rollback are not required.

## Current limits

Flash elimination was visually validated on `MI_WaterClean_Shallow` in Forest
Path. The other 30 packaged assets use the same active foam contribution and
passed structural and semantic round-trip verification. The complete PAK also
loaded the test save successfully, kept the confirmed water free of flashes,
and produced no obvious visual regression during the validation pass. A
complete location-by-location playthrough has not been performed. Other game
builds, GPUs, and drivers remain unverified.

## Credits

ClawLab — diagnosis, controlled testing, real-hardware validation, and
packaging. Developed collaboratively with OpenAI Codex assistance.
