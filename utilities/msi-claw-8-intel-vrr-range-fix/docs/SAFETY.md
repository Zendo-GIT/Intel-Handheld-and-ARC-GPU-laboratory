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

The startup task selects a Windows fixed refresh only for the exact 48-144
override. It first requires an enumerated 1920x1200 at 144 Hz mode and verifies
the current mode after selection. It never creates a timing at startup and does
not change the fixed refresh for official 48-120 or experimental 30-120.

Intel Graphics Software is Authenticode-validated during installation. Its
verified executable path, signer thumbprint and SHA-256 are saved. The hidden
startup process avoids PowerShell module auto-loading and requires the current
executable SHA-256 to match the saved value before launch. A changed Intel
executable is refused until the installer is rerun and validates the update.

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
Intel display query until the driver is ready, launches the verified Intel
Graphics Software command, allows display initialization to settle, then
applies and verifies the profile. The task is allowed on battery power and has
a three-minute execution limit.

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

## Profile-switch interlock

Each successful installation writes a small `managed-mode.json` record after
the profile, startup task and any EDID override have passed verification. An
installer can proceed only from a clean state or when reinstalling that exact
same mode. Every cross-profile transition is refused with instructions to run
`RESTORE_ORIGINAL_VRR.bat` first.

Exact legacy experimental overrides can be adopted only by their matching
installer. Legacy managed artifacts without a trustworthy mode record are not
guessed and require restore. An inconsistent record/override pair also requires
restore. The startup task itself refuses to operate unless its mode record and
current override agree.

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
- one documented current-user scheduled task, removed by normal restore;
- one readable VBS launcher used only to prevent a console-window flash;
- one exact Intel startup value temporarily replaced and restored;
- no power-plan, BIOS, network or anti-cheat modification;
- no bundled Intel, MSI, Microsoft or CRU binary.

The optional unsupported-display collector is read-only with respect to the
display stack. It writes only a user-requested JSON report and EDID copies under
the user's Documents folder. Users should review the report before sharing it.
