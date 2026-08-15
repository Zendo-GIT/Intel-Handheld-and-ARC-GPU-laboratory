# Safety and reversibility

## Supported public profiles

Version 2.0.2 installs only corrected 30-120 and official Intel/MSI 48-120.
Both require exact panel identity, pinned EDID state, one active Intel output
and exact driver range readback before the shared LFC flags can change.

The 30-120 profile uses a reversible Windows EDID override. It does not write
monitor firmware. The 48-120 profile does not modify EDID.

## Removed 144 Hz profiles

No 144 Hz installer, confirmation task or installation action is included.
Exact hashes from older releases remain only for detection and recovery.
Version 2.0.2 refuses to reapply or persist a retired 144 Hz state and directs
the user to `RESTORE_ORIGINAL_VRR.bat`.

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

## Third-party overrides

CRU and other unknown `EDID_OVERRIDE` data are refused and never removed. Use
the original third-party tool to reset its own configuration, restart Windows,
then collect diagnostics or install ClawLab.

## Profile switching

Run `RESTORE_ORIGINAL_VRR.bat` successfully and restart before selecting the
other supported profile. Same-mode repair remains allowed. Unknown or mixed
state requires the factory recovery path; unknown third-party data is still
left untouched.
