# Kena Intel Arc Water Flash Fix

Removes the bright cyan/white flashes affecting water in *Kena: Bridge of
Spirits* on the validated Intel Arc system while keeping the game on native
DirectX 12.

## What the mod does

The mod changes one parameter on the confirmed Forest Path shallow-water
material: `Foam_Opacity` is changed from `0.2` to `0.0`. This disables a subtle
procedural foam contribution that triggered the flashing on the affected Intel
rendering path. During validation, the flashes disappeared and no visible loss
of foam could be identified in normal play.

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

Version 1.0.0 targets the confirmed `MI_WaterClean_Shallow` material. Other
water materials, game builds, GPUs, and drivers remain unverified.

## Credits

ClawLab — diagnosis, controlled testing, real-hardware validation, and
packaging. Developed collaboratively with OpenAI Codex assistance.
