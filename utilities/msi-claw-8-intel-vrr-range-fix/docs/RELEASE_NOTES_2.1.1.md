# MSI Claw Intel VRR Range Fix 2.1.1

Version 2.1.1 is a stability and usability update for the public 30-120 and
official 48-120 profiles. The Intel LFC correction remains unchanged at tool
version 2.0.3.

## Cursor Refresh Helper

The helper now starts near the beginning of the sign-in task instead of waiting
for the complete Intel driver stabilization sequence. Its activity tail is 1.5
seconds, reducing repeated 30/120 or 48/120 transitions during brief mouse
pauses.

When usable visible-mouse input stops, the helper enters deep idle: its WPF
animation stops, its 1 ms Windows timer-resolution request is released, its own
working set is trimmed, and it waits in the normal message loop. The first
visible raw-mouse packet resumes the surface.

This behavior is the controller/game guard. It is driven by actual Windows
mouse and cursor state, not by the name or process of a profile manager. It
therefore works with ClawTweaks, MSI Center M, another controller utility, or no
manager. No third-party application or game process is monitored or modified.

## Clear startup and driver health

`CHECK_STATUS.bat` now starts with one overall result:

- `HEALTHY`: profile, helper and Intel LFC flags are all verified;
- `INITIALIZING`: a sign-in task is still running; wait and check again;
- `ATTENTION_REQUIRED`: the report prints the appropriate repair path.

The report compares the current Intel graphics driver with the driver recorded
at first installation. A changed driver is not automatically treated as a
failure: a currently verified configuration is reported as changed and healthy.
It also rejects an older installed helper as `VERSION_MISMATCH`, even when that
older binary still matches its own historical integrity record.

## Installation preflight and package layout

Both installers now ask the user to confirm that CRU was never used on the
current Windows installation, or that the current official `reset-all.exe` was
run and Windows restarted. ClawLab still does not download, bundle or execute
CRU.

The archive has a task-oriented layout:

- root: both installers, status, README, changelog and license;
- `RECOVERY`: normal restoration;
- `EMERGENCY`: factory reset and exact ClawLab EDID emergency removal;
- `DIAGNOSTICS`: display collection;
- `scripts`: runtime components;
- `SOURCE`: rebuildable helper source and offline integrity test.

The exact Claw 8 AI+/8 EX AI+ and A1M panel checks, profile-switch interlock,
original-state backups, anti-cheat boundary and legacy-144 recovery-only hashes
are retained.
