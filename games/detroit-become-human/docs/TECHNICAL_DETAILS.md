# Technical details

## Reproduced symptoms

The Intel Arc 140V test system showed three distinct behaviors:

- an unsupported-GPU prompt at every launch;
- black, magenta, cyan and yellow corruption after using the internal resolution
  scaler below 100% during a continuous session;
- occasional multi-second freezes and severe low-performance states, especially
  when moving between scenes or chapters.

Alt+Tab consistently recovered the persistent low-performance state. Reloading
a checkpoint or returning through the menu could clear the visual corruption
without restarting the process.

## Eliminated explanations

- CPU boost off made performance worse and was rejected.
- Rendering at 80% did not prevent the freezes and exposed the corruption path.
- Returning to 100% did not repair already-corrupted resources until they were
  reloaded.
- Memory use was high but bounded: private bytes peaked around 14.3 GB, working
  set around 8.1 GB and shared GPU memory around 5.9 GB. This did not behave like
  an unbounded process leak.
- Present captures showed long GPU-wait periods with very little GPU busy work,
  not a normal fully saturated GPU frame.
- Removing third-party Vulkan layers did not remove the scene-transition stalls.

## Unsupported-GPU dialog patch

The full UTF-16 prompt text is referenced directly before one `MessageBoxW`
call. The following logic continues only when the return value equals `IDOK`.

```asm
; DetroitBecomeHuman.exe Steam build 12158144
; file offset 0x661E57
FF 15 4B 31 25 01       call qword ptr [MessageBoxW]
83 F8 01                cmp eax, IDOK
74 0A                   je continue_launch
```

Release 1.0.0 replaces only that six-byte call:

```asm
B8 01 00 00 00          mov eax, IDOK
90                      nop
83 F8 01                cmp eax, IDOK
74 0A                   je continue_launch
```

This preserves the normal accepted path and does not change Intel device
identification, Vulkan driver selection or reported GPU capabilities.

## Shader and pipeline evidence

The first-run compiler recorded:

```text
Number of created pipelines = 99453
Time spent = 1405.405336s
```

The resulting `VkPipelineCache.bin` was approximately 1.36 GB. Its Quantic Dream
container includes a standard Vulkan pipeline-cache header matching:

```text
vendorID          = 0x8086
deviceID          = 0x64A0
pipelineCacheUUID = 911a9517-991c-a618-9a15-9a1b9d1f9f2e
driverInfo        = 101.8864
```

The cache therefore belongs to the current Intel Arc 140V driver. Deleting it
would force expensive rebuilding and is not part of the default fix.

The final launcher reads only the small cache header for validation. It does not
delete, rebuild or force-prefetch shader code or pipeline data. A prototype that
prefetched approximately 2.14 GB was removed after long-session degradation was
reported; ordinary Windows and game cache management is left untouched.

## Transition Guard

The final launcher polls only the metadata of top-level `*.qdsav` files under
`Default-*\\Game\\Chapters`. A changed chapter-progress signature arms one
presentation reset after a three-second transition delay, provided Detroit has
returned to the foreground. The separate checkpoint directory is excluded, and
a 60-second cooldown prevents duplicate resets.

The earlier asset-I/O detector was rejected after all three automatic resets in
a 56-minute session came from large-read heuristics. The later hung-window guard
was also removed because an automatic focus reset during active gameplay can
open Detroit's pause menu. Process I/O and Windows responsiveness therefore
cannot trigger the final automatic path.

`Ctrl+Alt+F11` invokes the same recovery manually. The guard does not hook Vulkan,
patch runtime memory, read save contents or synthesize game input. If a chapter
transition does not update the documented progress files, the launcher safely
skips the reset instead of guessing from in-game activity.

RTSS, Vulkan overlays, process priority and Windows execution-speed throttling
are left unchanged. Clean-overlay testing did not remove the transition stalls,
so those controls were excluded from the final fix.

## Optional Steam wrapper

Steam normally starts `DetroitBecomeHuman.exe`. Steam integration keeps the
verified warning-patched game beside it as
`DetroitBecomeHuman.ClawLab.real.exe`, then installs a locally compiled launcher
under the original name. The wrapper starts the installed PowerShell controller,
passes its process ID, and exits. The child controller waits for that exit,
stores a verified recovery copy of the wrapper, and atomically places the real
game back at the original root path for the duration of gameplay. This preserves
the executable name and full path used by Windows Game Bar and ClawTweaks.

The controller launches that restored-path payload with the same working
directory and temporary AppID context used by the classic optimized launcher.
After process exit it atomically restores the wrapper. The wrapper contains no
game code and is built on the user's machine from the C# source embedded in the
public PowerShell script. Its per-install SHA-256 and the exact payload SHA-256
are stored in the integration manifest. A handoff-state file and verified
wrapper recovery copy allow an interrupted session to be repaired safely.

## Integrity values

```text
Vanilla SHA-256:
ECF52321921387E683904E089082D76B973326FC093AF14E524056715519C1CF

Patched SHA-256:
1B31A15AC8AF8A236B3B7FB721DF439D03EB40ACAA5ECF59BC6BCF0CDF49D2AE
```

Both files have identical size and differ at exactly six byte positions.
