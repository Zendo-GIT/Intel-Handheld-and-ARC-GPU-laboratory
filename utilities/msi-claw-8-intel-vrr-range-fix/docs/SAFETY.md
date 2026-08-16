# Safety and reversibility

## Supported public profiles

Version 2.1.1 installs only corrected 30-120 and official Intel/MSI 48-120.
Both require one exact catalogued panel identity, pinned EDID state, one active Intel output
and exact driver range readback before the shared LFC flags can change.

The Claw A1M / Claw 7 AI+ definition uses a different one-block EDID path from
the Claw 8 family. The installer refuses cross-panel hashes and never invents
or writes an extension block for this shared Tianma panel. Exact EDID
transformation is release-tested; real A1M and Claw 7 AI+ display and driver
behavior remains community-validation pending for each model.

The 30-120 profile uses a reversible Windows EDID override. It does not write
monitor firmware. The 48-120 profile does not modify EDID.

## Removed 144 Hz profiles

No 144 Hz installer, confirmation task or installation action is included.
Exact hashes from older releases remain only for detection and recovery.
Version 2.1.1 refuses to reapply or persist a retired 144 Hz state and directs
the user to `RECOVERY\RESTORE_ORIGINAL_VRR.bat`.

Normal restore first selects a safe 120 Hz Windows mode when a legacy 144 Hz
override is detected, restores Intel solution flags and profile, removes the
known override and unregisters ClawLab tasks. Factory and Safe Mode recovery
retain the same exact-hash protection.

## Intel LFC correction

The readable `MSI-Claw-Intel-LFC-Fix.ps1` uses a global Windows D3DKMT Intel
display request. Before changing anything it saves the original low/high-FPS
solution flags and binds that backup to the managed profile. Failed readback
restores the saved values.

The task runs once at sign-in and exits. It is not a resident watcher. The tool
does not access a game process, game file, anti-cheat, overlay or network stack.
ClawTweaks is optional: no file, process or task from it is required when that
application is absent.

## Cursor Refresh Helper

The separate `ClawLab-Cursor-Refresh-Helper.exe` is a current-user, event-driven
desktop component. It receives standard Raw Input messages and animates a nearly
transparent 2x2 WPF/DWM surface at the extreme lower-right corner only while a
visible mouse cursor moves. It performs no continuous polling; its 8 ms animation
timer is stopped 1.5 seconds after input ends. At the same transition it releases
the 1 ms timer-resolution request, trims only its own working set and waits in
the standard Windows message loop.

The animation is suppressed when the system cursor is hidden and remains active
inside Windows Xbox Full Screen Experience. The helper neither injects into nor
hooks, opens, enumerates or reads game processes. It contains no driver interface and does not
change the LFC flags, VRR profile or EDID. Restore stops the exact installed
binary, verifies its path, and removes it with its integrity record.

No ClawTweaks, MSI Center M or other profile-manager process is inspected. A
controller/game profile simply stops producing usable visible-mouse activity,
which naturally leaves the helper in deep idle until the mouse returns.

## Third-party overrides

Any historical CRU use requires a mandatory pre-install cleanup: obtain the
current archive from the official
[CRU release page](https://www.monitortests.com/forum/Thread-Custom-Resolution-Utility-CRU),
run its included `reset-all.exe`, and restart Windows. This applies regardless
of when CRU was used or whether it currently appears inactive.

ClawLab does not bundle or execute CRU. CRU and other unknown `EDID_OVERRIDE`
data are refused and never removed by ClawLab itself. Use each original
third-party tool to reset its own configuration, restart Windows, then collect
diagnostics or install ClawLab.

## Profile switching

Run `RECOVERY\RESTORE_ORIGINAL_VRR.bat` successfully and restart before selecting the
other supported profile. Same-mode repair remains allowed. Unknown or mixed
state requires the factory recovery path; unknown third-party data is still
left untouched.
