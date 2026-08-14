DETROIT: BECOME HUMAN INTEL ARC STABILITY FIX 1.0.0
===================================================

SUPPORTED BUILD
---------------
Steam build 12158144 only.

Vanilla DetroitBecomeHuman.exe SHA-256:
ECF52321921387E683904E089082D76B973326FC093AF14E524056715519C1CF

Warning-fixed SHA-256:
1B31A15AC8AF8A236B3B7FB721DF439D03EB40ACAA5ECF59BC6BCF0CDF49D2AE

RECOMMENDED INSTALL - STEAM PLAY BUTTON
---------------------------------------
1. Close Detroit completely.
2. Run INSTALL_STEAM_INTEGRATION.bat once.
3. Start every session normally from Steam's Play button.

This compiles a small local wrapper named DetroitBecomeHuman.exe and keeps the
verified warning-patched game as DetroitBecomeHuman.ClawLab.real.exe. The
wrapper starts an invisible controller and exits. The controller temporarily
places the real game at the exact original path while playing so Windows Game
Bar and ClawTweaks retain the normal game identity, then restores the wrapper.
No game executable or compiled wrapper is included in this ZIP.

CLASSIC INSTALL
---------------
Run INSTALL_FIX.bat once, then start every session with LAUNCH_OPTIMIZED.bat.
Leave the launcher window open while playing.

If a persistent freeze or severe low-performance state remains, press:

Ctrl+Alt+F11

This requests the same presentation recovery observed after Alt+Tab and returns
focus directly to Detroit.

WHAT IT DOES
------------
- Removes only the unsupported-GPU dialog; no GPU vendor spoofing.
- Forces the validated 100% internal scale and in-game HDR-off safety profile.
- Validates the existing Intel pipeline-cache header without rebuilding or
  force-prefetching the cache.
- Leaves RTSS, overlays, process priority and Windows throttling untouched.
- Runs one automatic presentation reset only after a top-level completed
  chapter-progress file changes; checkpoint writes are excluded.
- Never performs an automatic reset during normal gameplay or in response to a
  freeze. Ctrl+Alt+F11 remains the manual in-scene recovery.

LIMITS
------
Prompt removal and the safe graphics path were validated on Intel Arc 140V.
An earlier asset-I/O transition detector caused three false-positive resets in
one long test and was removed. The chapter-only detector deliberately skips a
reset when no chapter-progress change is observed. The release does not claim to
remove every engine-level transition hitch or long-session performance decline.

UNINSTALL
---------
REMOVE_STEAM_INTEGRATION.bat removes only the Steam wrapper and keeps the warning
fix. UNINSTALL_FIX.bat removes integration if present, restores the verified
vanilla executable and restores saved internal-scale/HDR values. Steam Verify
integrity is an additional recovery method and overwrites the wrapper.

No game executable, cache, DLL, injector or copyrighted game asset is included.
