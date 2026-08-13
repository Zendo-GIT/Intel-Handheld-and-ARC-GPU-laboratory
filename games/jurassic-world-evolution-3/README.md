# JWE3 Intel Arc Water Glitch Fix

A transparent, reversible compatibility fix for the severe polygonal water
corruption affecting *Jurassic World Evolution 3* on some Intel Arc drivers.

![Version](https://img.shields.io/badge/release-1.0.0-blue)
![Game](https://img.shields.io/badge/JWE3-1.4.2.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Download

[Download JWE3 Intel Arc Water Glitch Fix 1.0.0](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/download/jwe3-v1.0.0/JWE3-Intel-Arc-Water-Glitch-Fix-1.0.0.zip)

[Release notes and SHA-256 file](https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/releases/tag/jwe3-v1.0.0)

The installer rejects every executable other than the supported build documented below.

## What it fixes

Affected systems can display large flashing squares, triangles and holes across
lakes. On the validated system, the problem came from JWE3's mesh-shader/SM65
rendering path. Forcing the game to use its existing classic vertex-shader/SM60
path removed the corruption in the same save and camera location.

Validated on:

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V / Intel Arc 140V
- Intel Graphics driver 32.0.101.8864
- JWE3 1.4.2.0 from Steam

No FPS improvement is claimed. Alt-Tab-related stutter is a separate issue.

## Supported executable

Release 1.0.0 supports only this original `JWE3.exe`:

```text
Version: 1.4.2.0
SHA-256: 04FA75D84683DE73AAFF7C0D5C28D8FDC5B4E900E5968022995CF84039F0A79F
```

Every other executable is rejected without modification.

## Installation

1. Download and extract the release ZIP.
2. Close JWE3 completely.
3. Run `INSTALL_FIX.bat`.
4. Confirm that the status is `FIX_INSTALLED`.
5. Launch normally through Steam.

Run `UNINSTALL_FIX.bat` to restore the verified original backup. Steam's
**Verify integrity of game files** feature can also restore the executable.

This is a manual installer and is not a Vortex-compatible package.

## Safety properties

- No game executable, shader, texture or other copyrighted game asset is
  distributed.
- Exactly three bytes are changed in the user's local executable.
- The original and patched SHA-256 values are verified transactionally.
- No DLL, hook, overlay or injector is installed.
- No running process or runtime memory is modified.
- The source is readable and restricted to JWE3 1.4.2.0.
- The fix does not bypass or interact with anti-cheat software.

Do not reuse executable patches on protected multiplayer games.

## Technical summary

At file offset `0x1CB666D`, JWE3 1.4.2.0 derives its internal mesh-shader
capability flag using:

```asm
setge al        ; 0F 9D C0
```

The fix replaces that instruction with:

```asm
xor eax, eax    ; 31 C0
nop             ; 90
```

The following original instruction stores zero in the capability flag. The
engine then creates and uses its classic VS/SM60 rendering path.

See [Technical details](docs/TECHNICAL_DETAILS.md) and
[Compatibility](docs/COMPATIBILITY.md) for the evidence and current limits.

## Building the Nexus release

On Windows PowerShell or PowerShell 7:

```powershell
.\tools\Build-Release.ps1 -Version 1.0.0
```

The builder validates the source, rejects game binaries and nested archives,
then produces the ZIP and `RELEASE_SHA256.txt` under `dist`.

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing support for another
game version. Never upload or commit a game executable. Security concerns should
follow [SECURITY.md](SECURITY.md).

## Credits and disclosure

ClawLab performed the diagnosis, reverse engineering, real-hardware testing and
packaging. Development was assisted collaboratively by OpenAI Codex; all public
claims were checked against the packaged source and the real in-game result.

This project is not affiliated with Frontier Developments, Universal Products &
Experiences, Intel, MSI, Steam or Nexus Mods.

## License

Original scripts and documentation are available under the [MIT License](LICENSE).
The game and all game assets remain the property of their respective owners.
