# Detroit: Become Human Intel Arc Stability Fix

A transparent, reversible compatibility package for *Detroit: Become Human* on
Intel Arc graphics, developed and validated on the MSI Claw 8 AI+.

![Version](https://img.shields.io/badge/release-1.0.0-blue)
![Steam build](https://img.shields.io/badge/Steam_build-12158144-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## What it addresses

The package combines four narrow measures:

1. Suppresses the unsupported-GPU prompt without spoofing another GPU vendor.
2. Keeps Detroit at 100% internal resolution scale with in-game HDR disabled,
   avoiding the reproduced black/magenta/cyan/yellow corruption path.
3. Validates the existing Intel Vulkan pipeline-cache header without deleting,
   rebuilding or force-prefetching the multi-gigabyte cache.
4. Runs a chapter-only recovery guard. It arms one presentation reset when
   Detroit writes a completed chapter-progress file, waits for the game to be in
   the foreground, then performs the reset during the transition. Checkpoint
   writes are excluded. `Ctrl+Alt+F11` exposes the same reset manually.

The final launcher deliberately leaves RTSS, Vulkan overlays, process priority,
Windows power throttling and normal cache residency untouched.

An optional Steam integration compiles a small open-source wrapper locally. The
wrapper takes the filename Steam normally starts and keeps the verified patched
game as `DetroitBecomeHuman.ClawLab.real.exe`. Steam's **Play** button then runs
the complete optimized path automatically. For the duration of gameplay, a
verified handoff places the real game back at the exact original executable path
so Windows Game Bar and tools such as ClawTweaks retain their normal identity.
No game executable is distributed.

## Important result boundary

The unsupported-GPU prompt removal is validated on the supported executable.
The graphics corruption did not return when the same scenario was replayed with
100% internal scaling and the clean Vulkan launch path.

Large transition stalls still occurred in the unmodified engine even after its
first-run shader compiler had completed. An earlier asset-I/O transition detector
produced three false-positive resets during one long session and was removed.
The final automatic path never reacts to an in-game hang or asset-read spike; it
uses only top-level chapter progression. This release therefore does **not**
claim that every engine-level transition hitch or long-session performance
decline is eliminated.

## Supported build

Release 1.0.0 supports only the Steam executable from build `12158144`:

```text
Vanilla SHA-256:
ECF52321921387E683904E089082D76B973326FC093AF14E524056715519C1CF

Warning-fixed SHA-256:
1B31A15AC8AF8A236B3B7FB721DF439D03EB40ACAA5ECF59BC6BCF0CDF49D2AE
```

Unknown or updated executables are rejected without modification.

## Installation and use

### Recommended: Steam Play integration

1. Extract the release ZIP.
2. Close Detroit completely.
3. Run `INSTALL_STEAM_INTEGRATION.bat` once. This also installs the warning fix.
4. Start Detroit normally with Steam's **Play** button.

The wrapper starts an invisible controller, which remains active until Detroit
exits and then restores the Steam-facing wrapper. Run
`REMOVE_STEAM_INTEGRATION.bat` to restore the warning-patched game under its
original filename while keeping the fix installed.

### Classic launcher

Run `INSTALL_FIX.bat` once, then start each session with
`LAUNCH_OPTIMIZED.bat`. Leave its console window open until Detroit exits.

No automatic reset is attempted during normal gameplay, even if the game hangs.
If a persistent freeze or low-performance state occurs inside a scene, press
`Ctrl+Alt+F11` once. The game window briefly resets and returns to the foreground.

Run `UNINSTALL_FIX.bat` to remove Steam integration if present, restore the
verified vanilla executable, and restore the saved internal-scale/HDR values.
Steam **Verify integrity of game files** remains an additional recovery path and
will overwrite the Steam wrapper.

## Safety properties

- No game executable, shader cache, proprietary asset, DLL or injector is
  distributed.
- Exactly six bytes are changed in the supported executable.
- Complete vanilla and patched SHA-256 values are verified.
- The replacement affects only the exact `MessageBoxW` call for the unsupported
  GPU prompt and returns the same `IDOK` value as clicking **OK**.
- Only the small pipeline-cache header is read for validation; caches are never
  bundled, rewritten or force-prefetched.
- RTSS and third-party Vulkan layers are not stopped, filtered or changed.
- `steam_appid.txt` is temporary and is removed after the session; a pre-existing
  file is restored byte-for-byte.
- The optional Steam wrapper is compiled locally from source during installation,
  identified by its generated SHA-256, and never bundled in the release ZIP.
- No driver, registry, network, Steam account or anti-cheat setting is modified.

Detroit is a single-player title without an anti-cheat requirement in this
tested path. Do not reuse executable patches on protected multiplayer games.

## Technical evidence

The reproduced first-run cache contains 99,453 created pipelines and reports
1,405.405 seconds of pipeline creation. The final `VkPipelineCache.bin` is a
1.36 GB Quantic Dream cache containing the exact Intel vendor, Arc 140V device
and current driver pipeline-cache UUID. Rebuilding it was therefore rejected as
a default fix.

See [Technical details](docs/TECHNICAL_DETAILS.md),
[Compatibility](docs/COMPATIBILITY.md), and [Safety](docs/SAFETY.md).

## Building the release

```powershell
.\tools\Build-Release.ps1 -Version 1.0.0
```

The builder creates a Nexus/GitHub-ready ZIP and checksum under `dist` without
including any game file, cache, trace or executable.

## Credits

ClawLab performed the diagnosis, reverse engineering, real-hardware testing and
packaging. Development was assisted collaboratively by OpenAI Codex.

This project is not affiliated with Quantic Dream, Intel, MSI, Valve or Nexus
Mods.

## License

Original scripts and documentation are available under the [MIT License](LICENSE.txt).
