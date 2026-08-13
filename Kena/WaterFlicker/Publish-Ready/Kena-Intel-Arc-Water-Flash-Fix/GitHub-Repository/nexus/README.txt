KENA INTEL ARC WATER FLASH FIX
Version 1.0.0
================================

WHAT IT FIXES

This mod removes the bright cyan or white water flashes reproduced in Kena:
Bridge of Spirits on an affected Intel Arc system running native DirectX 12.

The fix changes only one existing value on the confirmed Forest Path shallow-
water material:

  Foam_Opacity: 0.2 -> 0.0

The procedural foam layer is normally subtle. During validation, the flashes
disappeared and no visible loss of foam could be identified in ordinary play.
Water color, transparency, waves, normals, refraction, lighting, and blend mode
are unchanged.

VALIDATED SYSTEM

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V / Intel Arc 140V
- Intel Graphics driver 32.0.101.8864
- Kena Steam build 10345375
- Native DirectX 12

INSTALLATION

1. Close Kena completely.
2. Remove older experimental ClawLabWater...Probe PAK files from:

     Kena\Content\Paks\~Mods

3. Extract this ZIP into the Kena: Bridge of Spirits installation directory,
   the folder that already contains the inner Kena directory.
4. Confirm that this file exists:

     Kena\Content\Paks\~Mods\Kena-WindowsNoEditor_IntelArcWaterFlashFix_P.pak

5. Launch normally in DirectX 12.

UNINSTALLATION

Close the game and delete only:

  Kena\Content\Paks\~Mods\Kena-WindowsNoEditor_IntelArcWaterFlashFix_P.pak

The official game PAK is never edited.

SAFETY

- Data-only Unreal PAK override.
- No executable or driver modification.
- No DLL, injector, proxy, hook, overlay, or memory modification.
- No OptiScaler, fakenvapi, GPU spoofing, or DirectX 11 dependency.
- No anti-cheat bypass or interaction.
- Fully reversible by removing one file.

COMPATIBILITY AND LIMITS

Release 1.0.0 is validated only on the system and game build listed above. It
targets MI_WaterClean_Shallow, the confirmed affected Forest Path material.
Other water materials, builds, GPUs, and drivers remain unverified.

PAK SHA-256

2273313BA261F3CCC7F9D80806C0D5A1991C6AF062700F26F28E1C389FE53398

CREDITS

ClawLab - diagnosis, controlled testing, real-hardware validation, and
packaging. Developed collaboratively with OpenAI Codex assistance.

This mod is not affiliated with Ember Lab, Intel, MSI, Steam, or Nexus Mods.
Kena: Bridge of Spirits and its assets remain the property of their respective
owners.
