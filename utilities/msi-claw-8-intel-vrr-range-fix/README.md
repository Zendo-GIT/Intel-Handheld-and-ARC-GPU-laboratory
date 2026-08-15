# MSI Claw 8 AI+ / 8 EX AI+ Intel VRR Range Fix

![Version](https://img.shields.io/badge/release-2.0.2-blue)
![Profiles](https://img.shields.io/badge/profiles-30--120_%2F_48--120_Hz-green)
![144 Hz](https://img.shields.io/badge/144_Hz-removed-red)

Version 2.0.2 provides two deliberately separate profiles for the exact
validated `CSW0801 / PN8007QB1-2` internal panel:

- `INSTALL_30_120_VRR.bat`: default ClawLab 30-120 Hz profile;
- `INSTALL_48_120_VRR.bat`: official Intel/MSI 48-120 Hz profile.

Both include the shared Intel LFC x2 correction. The 48-144 and 30-144 profiles
were removed and cannot be installed or persisted by this release.

See [release notes](docs/RELEASE_NOTES_2.0.2.md),
[compatibility](docs/COMPATIBILITY.md) and [safety](docs/SAFETY.md).

## What the correction addresses

Affected Intel systems can multiply refresh inside the intended direct-VRR
range, for example `60 FPS -> 120 Hz` or `68 FPS -> 136 Hz`. The shared module:

- verifies the exact managed mode, EDID and active range;
- saves the original Intel low/high-FPS solution flags;
- disables both flags as one empirically tested combination;
- reads the flags and selected range back from the driver;
- reapplies once at sign-in through a windowless task;
- installs no continuous watcher and never accesses a game process.

Removal of the observed x2 behavior was validated on real hardware at 30-120
Hz. The same guarded flag operation is included in official 48-120. Disabling
Intel's low-FPS solution means refresh multiplication below the selected 30 or
48 Hz floor is unavailable.

## Profile choices

### Default: 30-120 Hz

This uses a reversible Windows EDID override to change the validated panel's
minimum from 48 to 30 Hz. It is outside MSI's official floor and may flicker on
individual units. The physical panel firmware is never modified.

### Official: 48-120 Hz

This keeps the native panel EDID and selects Intel Control Library's
`EXCELLENT` Arc Sync profile, then requires exact 48-120 Hz readback.

## Installation

1. Extract the ZIP completely.
2. Close games and display-control applications.
3. Remove any CRU or unknown third-party EDID override with the tool that
   created it, then restart Windows.
4. If another ClawLab profile is installed, run
   `RESTORE_ORIGINAL_VRR.bat` and restart first.
5. Run exactly one installer: `INSTALL_30_120_VRR.bat` or
   `INSTALL_48_120_VRR.bat`.
6. Accept the restart prompt and run `CHECK_STATUS.bat` after sign-in.

Cross-profile installation is refused. Reinstalling the same supported mode is
allowed for repair or package updates.

Version 2.0.2 also supports systems where Intel Graphics Software has no
machine Run entry. That original absence is saved and restored exactly; do not
create a fake `Intel-LFC-Fix` directory as a workaround.

## Status

The VRR block should report the selected managed mode and
`ProfileSwitchGuard: CONSISTENT`. The LFC block should report:

```text
CLAWLAB_LFC_FIX_ACTIVE
LowFpsSolutionEnabled  = False
HighFpsSolutionEnabled = False
StartupPersistence     = INSTALLED_ONE_SHOT_AT_LOGON
LfcFixActive            = True
```

Intel Graphics Software may display cached range text. `CHECK_STATUS.bat`
queries the Intel driver directly and is authoritative.

## Restore and recovery

`RESTORE_ORIGINAL_VRR.bat` restores the saved Intel solution flags, Arc Sync
profile, ClawLab EDID, tasks, scripts and original Intel startup state.

`RESTORE_INTEL_LFC_DEFAULTS.bat` restores only the Intel low/high-FPS flags and
leaves the selected 30-120 or 48-120 range intact.

If an older release installed 48-144 or 30-144, version 2.0.2 recognizes those
exact hashes only for recovery. Run `RESTORE_ORIGINAL_VRR.bat`; do not attempt
to keep or reapply the retired mode. `FACTORY_RESET_CLAWLAB_VRR.bat` and
`EMERGENCY_REMOVE_CLAWLAB_EDID.bat` also retain exact legacy recovery support.

Unknown CRU or third-party EDID overrides are never removed by this package.

## Compatibility and anti-cheat boundary

The public build requires the exact validated panel identity and EDID, exactly
one active Intel Arc Sync output and an Intel graphics adapter. It changes only
global display configuration. It does not patch, inject into, hook or monitor a
game process and installs no game DLL, overlay, service or driver.

## Build

```powershell
.\tools\Build-Release.ps1 -Version 2.0.2
```

The release contains readable scripts only and a SHA-256 manifest. It bundles
no Intel DLL, driver, executable, EDID dump or CRU binary.
