JWE3 INTEL ARC WATER GLITCH FIX
Version 1.0.0
================================

WHAT IT FIXES

This fix removes the large flashing polygon, square and triangle artifacts that
can cover water in Jurassic World Evolution 3 on affected Intel Arc drivers.

The issue was reproduced on:

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V / Intel Arc 140V
- Intel Graphics driver 32.0.101.8864
- Jurassic World Evolution 3 version 1.4.2.0 (Steam)

The fix forces the game to use its built-in classic vertex-shader / SM60 path
instead of the affected mesh-shader / SM65 path. It does not replace water
textures or materials.

SUPPORTED VERSION

Only the following JWE3.exe is supported:

- File version: 1.4.2.0
- Original SHA-256:
  04FA75D84683DE73AAFF7C0D5C28D8FDC5B4E900E5968022995CF84039F0A79F

The installer refuses every unknown or updated executable. This is intentional.

INSTALLATION (MANUAL ONLY)

1. Close Jurassic World Evolution 3 completely.
2. Extract this ZIP to any normal folder. Do not run it from inside the ZIP.
3. Double-click INSTALL_FIX.bat.
4. Read the result. A successful installation displays FIX_INSTALLED.
5. Launch the game normally through Steam.

Steam libraries are detected automatically. If detection fails, open
PowerShell in this folder and run:

  .\JWE3-IntelArc-WaterFix.ps1 -Action Install -GameExe "D:\SteamLibrary\steamapps\common\Jurassic World Evolution 3\JWE3.exe"

UNINSTALLATION

1. Close the game completely.
2. Double-click UNINSTALL_FIX.bat.

The installer restores the byte-identical backup it created. Steam's
"Verify integrity of game files" feature can also restore JWE3.exe.

HOW SAFE IS IT?

- No game executable or copyrighted game asset is included in this download.
- Exactly three bytes are changed in the user's local JWE3.exe.
- The original executable is backed up and its SHA-256 is verified.
- No DLL is installed or injected.
- No running process or runtime memory is modified.
- The script is readable source code and is hard-limited to JWE3.exe 1.4.2.0.
- It does not bypass or interact with anti-cheat software.

Do not reuse this executable-patching method on protected multiplayer games.

TECHNICAL DETAILS

JWE3 stores the reported D3D12 mesh shader tier and derives an internal
mesh-shader-supported flag. On game version 1.4.2.0, the flag is produced by:

  setge al

at file offset 0x1CB666D. Version 1.0.0 replaces that three-byte instruction
with:

  xor eax, eax
  nop

The following existing instruction then stores zero in the capability flag.
The game consequently selects its classic VS/SM60 shaders, including the
working water path.

Patched SHA-256:
3A172D9261075017974897A2F4EB89F16232B5E5D711B2EA77A524394BD7FAA8

KNOWN LIMITATIONS

- Only JWE3 1.4.2.0 is supported by this release.
- A game update or Steam file verification may remove the fix.
- Performance can differ because the game uses a different rendering path.
- No formal performance benchmark is claimed by this release.
- Alt-Tab-related stutter is a separate issue and is not addressed here.

TESTED RESULT

The water corruption was visually eliminated on the reference MSI Claw / Arc
140V system. XeSS, OptiScaler, fakenvapi, water quality and shader-cache resets
were separately ruled out during diagnosis.

CREDITS

ClawLab - diagnosis, reverse engineering, hardware testing and packaging.
Developed collaboratively with OpenAI Codex assistance and validated in game on
real hardware.
