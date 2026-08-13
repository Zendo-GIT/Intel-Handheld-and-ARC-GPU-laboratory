KENA INTEL ARC WATER FLASH FIX
Version 1.0.0
================================

WHAT IT FIXES

This mod removes the bright cyan or white water flashes reproduced in Kena:
Bridge of Spirits on an affected Intel Arc system running native DirectX 12.

The successful Forest Path test changed one existing value:

  Foam_Opacity: 0.2 -> 0.0

The procedural foam layer is normally subtle. During validation, the flashes
disappeared and no visible loss of foam could be identified in ordinary play.
Water color, transparency, waves, normals, refraction, lighting, and blend mode
are unchanged.

The release applies the same Foam_Opacity -> 0 correction to all 31 UIWS
surface-water instances in the tested build that enable the Foam? branch. This
includes still water and horizontally animated river/ocean surfaces. True
waterfalls and cascades use a separate material family and are not modified.

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

Flash elimination was visually validated on MI_WaterClean_Shallow in Forest
Path. The other 30 packaged assets use the same active foam contribution and
passed structural and semantic round-trip verification. The complete PAK also
loaded the test save successfully, kept the confirmed water free of flashes,
and produced no obvious visual regression during the validation pass. A
complete location-by-location playthrough has not been performed. Other game
builds, GPUs, and drivers remain unverified.

PAK SHA-256

6B8A19873CB65EA6CA33BA8A50CC90581A32F62A6A24C20E03A245A150CAD072

CREDITS

ClawLab - diagnosis, controlled testing, real-hardware validation, and
packaging. Developed collaboratively with OpenAI Codex assistance.

This mod is not affiliated with Ember Lab, Intel, MSI, Steam, or Nexus Mods.
Kena: Bridge of Spirits and its assets remain the property of their respective
owners.
