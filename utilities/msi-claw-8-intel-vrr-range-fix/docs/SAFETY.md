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

## Custom EDID ranges

Custom range installation writes two binary registry values named `0` and `1` under the
validated monitor instance's `Device Parameters\EDID_OVERRIDE` key. This is the
per-block Windows mechanism documented by Microsoft. It does not write the
panel EEPROM.

Before writing, the tool requires the complete physical EDID SHA-256 and both
block checksums. After writing, it requires exact SHA-256 values for both
generated blocks. An existing unknown override is never replaced or deleted.

Version 2.0.1 can install the pinned 30-120 transformation or the separate
pinned 48-144 transformation. The latter inserts one validated 1920x1200 at
144 Hz timing and the startup task selects it only when the exact managed
`CLAWLAB_48_144` or `CLAWLAB_30_144` state is present. Fixed 144 Hz was stable
on tested panels, but this does not guarantee operational VRR at 144 Hz. The
30-144 range visibly flickered on the reference panel and is exposed only by a
guarded, prominently warned trial.

Intel Graphics Software is Authenticode-validated during installation. Its
verified executable path, signer thumbprint, file version and SHA-256 are
saved. If an Intel driver package later replaces the executable, version 2.0.1
detects the identity change and renews the saved values only after a fresh
Windows Authenticode validation confirms a valid Intel signature at the exact
canonical path with the original `-s` argument. The hash is read again before
the atomic trust-record update and again before launch. An unsigned, invalid,
relocated or concurrently changing file is refused.

Administrative elevation is requested for installation so the tool can back up
and remove Intel Graphics Software's machine-wide automatic-startup entry.
Custom EDID installation and restoration also require elevation.

## Shared Intel LFC x2 correction

Every installer also runs the readable `MSI-Claw-Intel-LFC-Fix.ps1`. It
requires the exact validated panel, one of the four managed-mode records, the
corresponding pinned EDID state, exactly one active Intel display adapter, and
direct readback of the selected range before it can change the Intel flags.

The script uses Windows D3DKMT with Intel's driver-private VRR display escape to
read and change the driver's low- and high-FPS solution flags. This is not the
public Intel Control Library API and is not presented as an Intel-supported
feature. It also does not load either the legacy Intel Graphics Command Center
or current Intel Graphics Software application assemblies.

Before changing the flags, the script saves both original values under the
current user's local ClawLab state. It disables both as one combination, reads
them back, and verifies that the selected range did not change. Any failed
verification restores the saved values. The project deliberately makes no
claim about which individual flag is responsible for the observed x2 behavior.
Direct behavior was validated at 30-120 Hz; the same guarded mechanism is
installed for 48-120, 48-144 and 30-144 with their own exact range checks.

Disabling Intel's low-FPS solution removes LFC below the selected 30 or 48 Hz
floor. A game running below that floor can still tear or stutter.

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
Intel display query until the driver is ready, launches the verified Intel
Graphics Software command, allows display initialization to settle, then
applies and verifies the profile. The task is allowed on battery power and has
a three-minute execution limit.

The shared LFC correction registers a second current-user task named
`ClawLab MSI Claw Intel LFC Fix`. Its VBS launcher is also windowless. It waits
for display initialization, invokes the installed range reapply, disables both
saved Intel solution flags, verifies the complete selected range, and exits. It
is a one-shot logon action, not a resident process or periodic watchdog.

Intel Graphics Software is not used to apply the range. Its tray process was
observed retaining stale `60-120 Hz` text until fully exited and restarted,
while direct driver queries already returned `48-120 Hz`.

## Recovery

The first original Intel profile is saved under the current user's local
ClawLab state directory and is not overwritten by repeated installation.

Normal restore first returns both saved Intel solution flags, then verifies and
removes only this package's EDID blocks, restores the saved Intel profile,
unregisters both sign-in tasks, removes the installed PowerShell and VBS
scripts, restores the exact Intel startup value, and asks for a restart.
Emergency restore uses the recorded exact registry path and
hard-coded block SHA-256 values. It does not load Intel Control Library and can
be used from Safe Mode.

## Profile-switch interlock

Each successful installation writes a small `managed-mode.json` record after
the profile, startup task and any EDID override have passed verification. An
installer can proceed only from a clean state or when reinstalling that exact
same mode. Every cross-profile transition is refused with instructions to run
`RESTORE_ORIGINAL_VRR.bat` first.

An exact legacy 30-120, 48-144 or 30-144 override can be adopted only by its
matching installer.
Legacy managed artifacts without a trustworthy mode record are not guessed and
require restore. An inconsistent record/override pair also requires restore.
The startup task itself refuses to operate unless its mode record and current
override agree.

## Guarded 144 Hz confirmation

Both 144 Hz installers register one temporary highest-privilege current-user
task. At the next sign-in it waits for the main task to expose and verify the
requested 48-144 or 30-144 range, observes it for 20 seconds, then displays a
system-modal Yes/No confirmation. The dialog has a 30-second timeout.

Yes keeps the range and deletes the temporary task and its files. No, closing
the dialog, or timing out invokes the normal verified restore path, first
selects 1920x1200 at 120 Hz, removes the exact EDID override and managed state,
then schedules a Windows restart to reload the physical EDID. Failure to verify
the requested range also triggers rollback. A restore failure does not delete
the recovery state and tells the user to run `RESTORE_ORIGINAL_VRR.bat`.

## Factory recovery

`FACTORY_RESET_CLAWLAB_VRR.bat` is a last-resort recovery for mixed or damaged
ClawLab state. It is restricted to the exact validated panel and refuses an
unknown EDID override. It can remove only the three pinned ClawLab override
signatures retained by the recovery code. Partial or cross-profile block pairs
are recoverable only when every block that is present independently matches a
pinned ClawLab block hash. One unknown block makes the entire reset refuse.

The reset requires an enumerated 1920x1200 at 120 Hz mode, selects Intel
`RECOMMENDED`, removes the ClawLab task/scripts/state, and restores Intel
Graphics Software startup. If the saved entry is unusable, the fallback command
is accepted only when the executable is at Intel's expected factory path and
has a valid Intel Authenticode signature. A restart is required to reload the
physical EDID.

## What it never does

- no monitor EEPROM or firmware write;
- no graphics-driver file replacement;
- no generic or heuristic EDID patch;
- no unknown EDID-override removal;
- no game executable, asset, process or memory modification;
- no DLL injection, overlay, hook or background service;
- two documented current-user one-shot scheduled tasks, removed by normal restore;
- two readable VBS launchers used only to prevent a console-window flash;
- one exact Intel startup value temporarily replaced and restored;
- no power-plan, BIOS, network or anti-cheat modification;
- no bundled Intel, MSI, Microsoft or CRU binary.

The optional unsupported-display collector is read-only with respect to the
display stack. It writes only a user-requested JSON report and EDID copies under
the user's Documents folder. Users should review the report before sharing it.
