# Safety

## Official mode

Official mode calls only these Intel Control Library functions:

- `ctlInit`
- `ctlEnumerateDevices`
- `ctlEnumerateDisplayOutputs`
- `ctlGetIntelArcSyncInfoForMonitor`
- `ctlGetIntelArcSyncProfile`
- `ctlSetIntelArcSyncProfile`
- `ctlClose`

The requested profile is `CTL_INTEL_ARC_SYNC_PROFILE_EXCELLENT`. The result is
accepted only when the driver reads back `EXCELLENT / 48-120 Hz`.

## Experimental mode

Experimental mode writes two binary registry values named `0` and `1` under the
validated monitor instance's `Device Parameters\EDID_OVERRIDE` key. This is the
per-block Windows mechanism documented by Microsoft. It does not write the
panel EEPROM.

Before writing, the tool requires the complete physical EDID SHA-256 and both
block checksums. After writing, it requires exact SHA-256 values for both
generated blocks. An existing unknown override is never replaced or deleted.

The 48-144 Hz mode additionally inserts one exact DisplayID 2.0 Type VII
1920x1200 timing while preserving the native 60 and 120 Hz detailed timings.
The implementation accepts only pinned complete/block hashes for 30-120 and
48-144. The rejected 30-144 signature remains recognized internally only so an
exact matching leftover can be reported and safely removed; no public action
installs it.

Administrative elevation is requested for installation so the tool can back up
and remove Intel Graphics Software's machine-wide automatic-startup entry.
Experimental EDID installation and restoration also require elevation.

## Sign-in persistence

Real-hardware testing showed the Intel driver restoring
`RECOMMENDED / 60-120 Hz` during a full Windows restart. Official installation
therefore registers one current-user scheduled task named
`ClawLab MSI Claw 8 VRR Range`.

Installation accepts only the exact machine-wide Run value named
`Intel® Graphics Software` whose command resolves to a valid Intel-signed
`IntelGraphicsSoftware.exe` with its original `-s` argument. The complete value
is backed up before removal; an unknown or changed entry is refused.

At sign-in, the task runs the readable `ClawLab-VRR-Startup.vbs` launcher
through Windows Script Host. The launcher starts the installed PowerShell script
with window style `0`, so no console flashes on screen. The script retries the
Intel display query until the driver is ready, applies and verifies the profile,
then launches the verified Intel Graphics Software command. The task is allowed
on battery power and has a three-minute execution limit.

Intel Graphics Software is not used to apply the range. Its tray process was
observed retaining stale `60-120 Hz` text until fully exited and restarted,
while direct driver queries already returned `48-120 Hz`.

## Recovery

The first original Intel profile is saved under the current user's local
ClawLab state directory and is not overwritten by repeated installation.

Normal restore verifies and removes only this package's EDID blocks, restores
the saved Intel profile, unregisters the sign-in task, removes the installed
PowerShell and VBS scripts, restores the exact Intel startup value, and asks for
a restart. Emergency restore uses the recorded exact registry path and
hard-coded block SHA-256 values. It does not load Intel Control Library and can
be used from Safe Mode.

## What it never does

- no monitor EEPROM or firmware write;
- no graphics-driver file replacement;
- no generic or heuristic EDID patch;
- no unknown EDID-override removal;
- no game executable, asset, process or memory modification;
- no DLL injection, overlay, hook or background service;
- one documented current-user scheduled task, removed by normal restore;
- one readable VBS launcher used only to prevent a console-window flash;
- one exact Intel startup value temporarily replaced and restored;
- no power-plan, BIOS, network or anti-cheat modification;
- no bundled Intel, MSI, Microsoft or CRU binary.

The optional unsupported-display collector is read-only with respect to the
display stack. It writes only a user-requested JSON report and EDID copies under
the user's Documents folder. Users should review the report before sharing it.
