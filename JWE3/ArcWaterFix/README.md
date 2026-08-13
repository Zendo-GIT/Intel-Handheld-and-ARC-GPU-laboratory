# Jurassic World Evolution 3 — Experimental Intel Arc Water Fix

## Confirmed scope

- Reference system: MSI Claw 8 AI+ Polar Tempest, Intel Core Ultra 7 258V,
  Intel Arc 140V, 32 GB RAM.
- Reference game: Jurassic World Evolution 3 `1.4.2.0`.
- Observed driver: Intel Graphics `32.0.101.8864`.
- Symptom: large polygonal or square regions flicker across the water and expose
  the terrain underneath.
- The issue persists without XeSS, OptiScaler, or fakenvapi and at every water
  quality setting.

## Initial diagnostic results

The Cobra Content Pack hypothesis was **rejected**: the `lod-static` and
`flat-safe` variants produced no visible change. The experimental pack was
therefore disabled, and `Content0\Environment\Water\Water.ovl` remained intact.

The game shader archive contains separate `Win64_SM60` and `Win64_SM65` paths,
including several `Water_WaterPool` and `Water_WaterVolume` shaders. Resetting
the DirectX 12 and Intel shader caches had no effect, so that hypothesis was
also rejected.

The engine stores the `f3d_mesh_shader_tier` hardware tier separately. In
`JWE3.exe` 1.4.2.0, the internal Boolean that enables mesh shaders is produced
by `setge al` at file offset `0x1CB666D`. The current fix replaces that
instruction with `xor eax,eax; nop` before the engine creates its interfaces
and pipelines. This forces the classic vertex-shader/SM60 path without changing
the Intel driver.

## Current fix: mesh-shader fallback

### Result on the reference system

**Visually validated on August 13, 2026: the mesh-shader fallback removes the
polygonal water corruption on Intel Arc 140V with driver 32.0.101.8864.**

This result confirms that the defect occurs while executing the SM65
mesh-shader path on this driver. It is not caused by the water materials, XeSS,
the shader cache, or the water quality settings. The fix remains installed on
the reference system.

The manager rejects every executable other than the tested build, creates and
verifies a backup, and supports complete restoration:

```powershell
.\tools\Manage-JWE3MeshShaderFallback.ps1 -Action Status
.\tools\Manage-JWE3MeshShaderFallback.ps1 -Action Install
.\tools\Manage-JWE3MeshShaderFallback.ps1 -Action Uninstall
```

- Official SHA-256:
  `04FA75D84683DE73AAFF7C0D5C28D8FDC5B4E900E5968022995CF84039F0A79F`
- Patched SHA-256:
  `3A172D9261075017974897A2F4EB89F16232B5E5D711B2EA77A524394BD7FAA8`
- Backup: `JWE3.exe.clawlab-original-1.4.2.0.bak`

A game update or Steam file verification may restore the official executable.
The manager will then refuse to reuse the 1.4.2.0 offsets on an unknown build.

## Diagnostic variants

Only one variant may be active at a time.

| Variant | Change | Purpose |
| --- | --- | --- |
| `lod-static` | Removes mip biases and freezes the `gst_water` detail texture animation | Conservative first test for animated blocks |
| `dither-off` | Disables dithered fading on pool materials | Isolates a dither or roughness defect |
| `opacity-safe` | Increases depth-based opacity | Masks a potentially unstable depth calculation |
| `flat-safe` | Neutralizes relief, parallax, distortion, and animation | Visually flatter fallback mode |

## Legacy FGM prototype management

Run these commands from PowerShell in this directory:

```powershell
.\tools\Manage-ArcWaterFix.ps1 -Action Status
.\tools\Manage-ArcWaterFix.ps1 -Action Install -Variant lod-static
.\tools\Manage-ArcWaterFix.ps1 -Action Disable
.\tools\Manage-ArcWaterFix.ps1 -Action Enable
.\tools\Manage-ArcWaterFix.ps1 -Action Uninstall
```

The manager refuses all modifications while `JWE3.exe` is running. Uninstalling
moves the module into `disabled-backups` instead of deleting it.

## Shader recompilation test

The DirectX cache directory `c68ef6650597d61f` was attributed to JWE3 through
its `app_id` table, which contains the path to `JWE3.exe`. The Intel cache from
the same execution window is backed up as well. None of these files is an
official game file.

```powershell
.\tools\Manage-JWE3ShaderCache.ps1 -Action Status
.\tools\Manage-JWE3ShaderCache.ps1 -Action Reset
.\tools\Manage-JWE3ShaderCache.ps1 -Action Restore
```

`Reset` moves the caches into `cache-backups`. `Restore` restores the latest
backup and preserves the cache created during the test separately.

## Rebuilding the diagnostic variants

Rebuilding requires a JWE3-compatible copy of Cobra Tools and an extraction of
the official `Water.ovl`:

```powershell
python .\tools\build_water_variants.py `
  --cobra-tools "C:\path\to\cobra-tools" `
  --water-extracted "C:\path\to\Water-extracted" `
  --output .\build
```

Official game files remain read-only during the rebuild.

## Anti-cheat safety

The legacy prototype is a Cobra resource replacement for a single-player game.
It injects no hook, overlay, or DLL. This greatly reduces risk compared with a
generic injector, but it is not a universal guarantee for other games. The
laboratory will not use this mechanism on a protected multiplayer title without
specific validation from the publisher and anti-cheat vendor.

The mesh-shader fallback is also restricted by filename, path, and hash to JWE3
1.4.2.0. It does not launch an injector, modify a running process, or install a
DLL. The local audit found no Easy Anti-Cheat, BattlEye, Vanguard, EQU8,
XIGNCODE, or GameGuard binary in the game directory. Nevertheless, an
executable patch must never be transferred to a protected game; the laboratory
rejects that use by default.

## Public release 1.0.0

`Publish-Ready/JWE3-Intel-Arc-Water-Glitch-Fix` contains:

- `Nexus-Mods`: final ZIP, SHA-256, ready-to-paste description, upload
  checklist, and a screenshot of the defect before the fix;
- `GitHub-Repository`: complete public repository with source code, README, MIT
  license, technical documentation, contribution and security policies,
  issue/PR templates, and a GitHub Actions workflow;
- `ARTIFACTS_SHA256.txt`: hash of every delivered file.

Rebuild the publication bundle with:

```powershell
.\tools\Build-PublicationBundle.ps1 -Version 1.0.0
```
