# MSI Claw 8 AI+ / 8 EX AI+ Intel VRR Range Fix

A transparent and reversible utility for the `CSW0801 / PN8007QB1-2` internal
panel used by compatible MSI Claw 8 AI+ and Claw 8 EX AI+ configurations.

![Version](https://img.shields.io/badge/release-2.0.1-blue)
![Official mode](https://img.shields.io/badge/official-48--120_Hz-green)
![Default mode](https://img.shields.io/badge/default-30--120_Hz-orange)
![Guarded trials](https://img.shields.io/badge/guarded_trials-48--144_%2F_30--144_Hz-red)
![License](https://img.shields.io/badge/license-MIT-green)

See the [2.0.1 release notes](docs/RELEASE_NOTES_2.0.1.md) for the publication
summary and upgrade boundary.

## Why this exists

The panel EDID and MSI specification both report a native VRR range of
`48-120 Hz`, but the Intel `RECOMMENDED` Arc Sync profile can expose only
`60-120 Hz` as the active driver range. On the reference system, the official
Intel Control Library reported:

```text
Monitor range: 48-120 Hz
RECOMMENDED profile: 60-120 Hz
EXCELLENT profile: 48-120 Hz
```

Intel defines `EXCELLENT` as the unconstrained profile that can use the full
monitor VRR range. MSI documents both Claw Intel models with an 8-inch
`48-120 Hz VRR` display.

- [Intel Graphics Control Library Arc Sync API](https://intel.github.io/drivers.gpu.control-library/Control/api.html)
- [MSI Claw 8 AI+ specifications](https://www.msi.com/Handheld/Claw-8-AI-Plus-A2VMX/Specification)
- [MSI Claw 8 EX AI+ specifications](https://www.msi.com/Handheld/Claw-8-EX-AI-Plus-CG3EMX/Specification)

## Four deliberately separate profiles

The default profile in release 2.0.1 is **30-120 Hz with the validated Intel
LFC x2 correction**. The native **48-120 Hz** profile remains available as the
official Intel/MSI-specification choice. Both 144 Hz profiles are opt-in guarded
hardware trials.

### Official mode: 48-120 Hz

`INSTALL_48_120_VRR.bat` selects Intel's official `EXCELLENT` Arc Sync profile
through `ControlLib.dll`, then reads the profile back from the driver and
requires an exact `48-120 Hz` result.

A full Windows restart was observed restoring Intel's constrained
`RECOMMENDED / 60-120 Hz` profile. The installer therefore stores a verified
copy of its readable PowerShell script and creates a current-user scheduled
task named `ClawLab MSI Claw 8 VRR Range`.

To guarantee startup order, installation verifies and backs up Intel's signed
`Intel® Graphics Software` Run entry, then removes only that entry. At sign-in,
a small readable Windows Script Host launcher starts PowerShell with window
style `0`. The script waits silently for the display driver, starts the verified
Intel Graphics Software command, allows display initialization to settle, then
applies and verifies `EXCELLENT`. No console window is displayed.

Graphics-driver packages can replace `IntelGraphicsSoftware.exe`. Version
2.0.1 detects that replacement and renews the saved file identity only after a
fresh Windows Authenticode validation confirms the canonical executable is
still validly signed by Intel. A changed hash alone is never trusted. Invalid,
relocated or unstable files are refused without launching them.

This mode does not modify the EDID, graphics driver, monitor firmware or any
game. It also applies the shared Intel LFC correction described below.

### Default ClawLab mode: 30-120 Hz

`INSTALL_30_120_VRR.bat` is a validated-panel-only EDID
override comparable in purpose to configuring the range with ToastyX Custom
Resolution Utility (CRU). It changes the minimum from 48 to 30 in copies of the
base EDID range descriptor and DisplayID Adaptive-Sync block, recalculates both
checksums, and writes only those two verified 128-byte override blocks using
Windows' documented `EDID_OVERRIDE` mechanism.

The physical panel EEPROM is never written. A restart is required for Windows
and the Intel driver to reload the override. This range is outside MSI's stated
48 Hz floor and can cause flicker, blanking or other display instability. It is
the release's default because the complete 30-120 + Intel LFC correction was
validated on the reference system; it must not be represented as MSI-certified.

- [Microsoft EDID override documentation](https://learn.microsoft.com/windows-hardware/drivers/display/overriding-monitor-edids)
- [Official CRU support thread](https://www.monitortests.com/forum/Thread-Custom-Resolution-Utility-CRU)

No CRU file is bundled or required.

Version 2.0.1 integrates the correction for Intel's
aggressive LFC/Adaptive Sync Plus behavior. On affected systems, the driver can
multiply refresh rate by two inside the intended VRR range, for example
`60 FPS -> 120 Hz` or `68 FPS -> 136 Hz`. Every installer:

- selects Intel `EXCELLENT`;
- verifies the exact range and pinned EDID for its selected profile;
- disables both Intel low- and high-FPS VRR solutions through a direct Windows
  D3DKMT display-driver request;
- verifies both flags and the active range, then reapplies them once at sign-in.

The two Intel flags are treated as one combination. The project does not claim
which flag is individually responsible. Disabling the low-FPS solution also
means LFC is unavailable below the selected profile floor; frame rates below
30 FPS or 48 FPS, depending on the profile, can still tear or stutter. The x2
correction was directly validated at 30-120 Hz and is installed with exact
verification on all four profiles. The two 144 Hz profiles remain experimental.

### Experimental overclock: 48-144 Hz — VRR not guaranteed

`INSTALL_EXPERIMENTAL_48_144_VRR.bat` adds a validated 1920x1200 at 144 Hz
timing and advertises a 48-144 Hz range on the exact supported panel. Fixed
144 Hz remained stable on the tested Claw 8 AI+ and community-tested Claw 8
EX AI+ units, and Intel's API reported `EXCELLENT / 48-144 Hz`.

Those results prove that the fixed 144 Hz display mode works on the tested
panels; they do **not** prove that variable refresh operates correctly in every
game or throughout the advertised 48-144 Hz range. Follow-up game telemetry did
not reliably validate VRR at 144 Hz. Treat this option as an experimental panel
refresh overclock with **VRR not guaranteed**, not as a verified VRR upgrade.
It is outside MSI's 120 Hz specification and can cause artifacts, instability
or reduced panel lifetime.

### Experimental full-range trial: 30-144 Hz

`INSTALL_EXPERIMENTAL_30_144_VRR.bat` exposes the complete custom range. This
exact profile produced visible flicker on the reference panel, so it is offered
only as an informed, reversible trial—not as the recommended profile.

Both 144 Hz installers schedule the same failsafe for the next sign-in. Once
the driver has verified the requested range and both shared LFC flags, the
profile runs for 20 seconds and a system-modal Yes/No dialog opens. **Yes**
keeps it. **No**, closing the dialog, or no answer within 30 seconds restores
the original LFC flags and previous VRR profile, selects a safe 120 Hz display
mode, and restarts Windows to reload the physical EDID. The confirmation task
deletes itself after either outcome.

## Installation

1. Extract the release ZIP completely.
2. Close games and display-control applications.
3. If any ClawLab VRR profile is already installed, keep the same profile or run
   `RESTORE_ORIGINAL_VRR.bat` and restart before switching.
4. Choose exactly one installer:
   - run `INSTALL_30_120_VRR.bat` for the release's default,
     community-validated 30-120 Hz + Intel LFC x2 correction; or
   - run `INSTALL_48_120_VRR.bat` for the official Intel/MSI-specification
     48-120 Hz profile; or
   - run `INSTALL_EXPERIMENTAL_48_144_VRR.bat` for the guarded 48-144 trial; or
   - run `INSTALL_EXPERIMENTAL_30_144_VRR.bat` only after reading the visible-
     flicker warning and accepting the guarded 30-144 trial.
5. Accept the final restart prompt, or restart the PC manually later.
6. After signing in, wait for Intel Graphics Software to start automatically;
   the VRR task runs before it.
7. Run `CHECK_STATUS.bat`.

Every installer establishes its verified Intel profile, saves the original
Intel low/high-FPS solution flags, disables both, and installs a separate
windowless one-shot sign-in reapply. Custom profiles also install their pinned
EDID override. If status reports a pending-restart state, restart before
evaluating the result.

### Mandatory profile-switch procedure

Never run a different installer over an installed mode. Run
`RESTORE_ORIGINAL_VRR.bat`, require a successful result, restart when requested,
and only then install the new mode. Version 1.0.2 and later enforce this rule: every
successful installation records its exact managed mode, and every installer
refuses a different mode. Reinstalling the same mode remains allowed for repair
or package updates.

Legacy managed files without a trustworthy mode record are also refused until
normal restore completes. This conservative behavior prevents the utility from
guessing whether an incomplete state came from official mode or EDID recovery.

## Status versus Intel Graphics Software

Intel Graphics Software can continue displaying a cached or profile-derived
`60-120 Hz` value. `CHECK_STATUS.bat` reads the monitor capability and active
profile directly from the Intel Control Library and separately verifies the
Windows EDID override. Its result is the package's authoritative status.

Real-hardware testing confirmed that completely exiting the Intel Graphics
Software tray process and starting it again refreshes the application to the
correct `48-120 Hz` value. The application does not control the selected range;
its still-running tray process can retain stale display text.

Expected states include:

```text
OFFICIAL_48_120_ACTIVE
EXPERIMENTAL_OVERRIDE_PENDING_RESTART
CLAWLAB_30_120_ACTIVE
EXPERIMENTAL_48_144_ACTIVE
EXPERIMENTAL_30_144_ACTIVE
DRIVER_PROFILE_CONSTRAINED
UNKNOWN_EDID_OVERRIDE
```

`EXPERIMENTAL_48_144_ACTIVE` or `EXPERIMENTAL_30_144_ACTIVE` means that the
EDID, fixed Windows mode and Intel API readback match the declared range. It is
not proof of correct VRR behavior inside every game. For either 144 Hz mode,
`WindowsDisplayMode` must also report `1920x1200 @ 144 Hz`.

The trial-status block reports `AWAITING_CONFIRMATION` until the 20-second
observation and Yes/No decision are complete. A confirmed profile reports
`NOT_SCHEDULED` because the one-time failsafe removes itself.

`StartupReapply` must show `Ready` or `Running` after installation. If it shows
`NOT_INSTALLED`, the driver can return to 60-120 Hz on the next restart.
`IntelGraphicsStartup` must show `CLAWLAB_ORDERED`; any unknown startup entry is
refused rather than overwritten.

An Intel driver installer may recreate Intel Graphics Software's original Run
entry. The VRR profile can still be verified, but if status shows
`ORIGINAL_STILL_PRESENT`, rerun the installer for the same managed mode once;
it safely removes the newly recreated exact Intel entry and restores ordered
startup without requiring a profile switch.

The second status block reports the LFC correction for the selected profile. Its
active state is:

```text
CLAWLAB_LFC_FIX_ACTIVE
ExpectedRange              = selected profile range
LowFpsSolutionEnabled  = False
HighFpsSolutionEnabled = False
StartupPersistence     = INSTALLED_ONE_SHOT_AT_LOGON
LfcFixActive           = True
```

Display-profile tools that force Intel `RECOMMENDED` at sign-in or when a game
starts can overwrite the managed state. Disable that conflicting profile write
or use a build/configuration that leaves VRR untouched. This release deliberately
installs no continuous watchdog: it performs one ordered sign-in reapply and
then exits, avoiding in-game display switches and polling overhead.

`ManagedMode` identifies the installed mode and `ProfileSwitchGuard` must show
`CONSISTENT`. Any `RESTORE_REQUIRED`, `INCONSISTENT` or `UNSUPPORTED` state means
that no installer should be run; use restore or factory recovery.

## Restore and emergency recovery

Run `RESTORE_ORIGINAL_VRR.bat` to restore the saved Intel low/high-FPS solution
flags first, restore the first saved Intel Arc Sync profile, and remove the
ClawLab custom EDID override if this package installed it. Restore also
unregisters both sign-in tasks, deletes their installed scripts and restores the
exact signed Intel startup entry. Restart the PC when prompted.

`RESTORE_INTEL_LFC_DEFAULTS.bat` restores only the saved Intel low/high-FPS
solution flags and removes their one-shot task. It leaves the selected ClawLab
VRR range unchanged.

The original profile is stored under:

```text
%LOCALAPPDATA%\ClawLab\Intel-Arc-Sync-Full-Range\original-profile.json
```

If a custom range causes a display problem, boot Windows Safe Mode and run
`EMERGENCY_REMOVE_CLAWLAB_EDID.bat`. This path does not initialize the
Intel graphics API. It removes only override blocks whose SHA-256 values match
this package, then asks for a restart. After normal Windows returns, run the
regular restore script to restore the saved Intel profile.

If normal restore cannot complete because ClawLab state files were mixed,
deleted or damaged, run `FACTORY_RESET_CLAWLAB_VRR.bat`. This recovery does not
need the saved original Arc Sync profile. On the exact validated panel it:

- selects the enumerated 1920x1200 at 120 Hz Windows mode;
- selects Intel's factory `RECOMMENDED` Arc Sync profile;
- removes exact, partial or cross-profile combinations only when every present
  EDID block has a pinned ClawLab hash;
- removes the ClawLab task and installed helper scripts;
- restores Intel Graphics Software startup from a verified backup or its
  Authenticode-validated factory path;
- deletes all ClawLab VRR state and requires a restart.

An unknown third-party EDID override or unexpected Intel startup entry is
refused, not overwritten. “Factory reset” means factory recovery for the
validated ClawLab VRR utility, not a generic monitor or Windows reset.

## Compatibility boundary

The official Intel API mechanism may be useful on other Intel Arc Sync systems,
but model names alone are never trusted. This release intentionally accepts
only:

```text
Panel ID: CSW0801
Panel name: PN8007QB1-2
Physical EDID SHA-256:
E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0
```

This is a display-specific safeguard, not a claim that other Intel Arc GPUs are
incapable. A Claw 8 EX AI+ is accepted only when Windows reports the exact panel
and physical EDID above. A future generic edition needs separate monitor
selection and validation. A custom EDID must never be copied blindly to
another EDID.

The Intel-powered Claw A1M uses a different 7-inch 1920x1080 display and is not
accepted by this release. `COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat` performs a
read-only hardware/EDID collection for an A1M or another unsupported Claw so a
separate profile can be researched without guessing. Collection is not an A1M
fix and changes no display setting.

The AMD-powered Claw A8 has the same published `1920x1200 / 48-120 Hz VRR`
display specification, but it cannot use Intel Control Library. It is therefore
not compatible with this Intel package. It requires separate AMD-driver and
physical-EDID validation before a dedicated edition can be published. The same
restriction applies to the Lenovo Legion Go S, whose public display
specification is similar but whose exact panel identity has not been verified.

## Anti-cheat boundary

The utility does not open, inject into, patch, monitor or control game
processes. It modifies no game file and installs no runtime service, overlay or
hook. Its scheduled tasks run once after sign-in and exit immediately after
profile verification. Official mode changes a global display profile through
Intel's public API; custom modes install a Windows monitor EDID override.
The shared LFC correction changes only global Intel display-driver flags through
Windows D3DKMT; it performs no per-game operation.

This design has no direct interaction with anti-cheat software, but no project
can guarantee third-party anti-cheat policy. Keep the package documentation
available when reporting compatibility.

## Building the release

```powershell
.\tools\Build-Release.ps1 -Version 2.0.1
```

The ZIP contains only readable scripts and documentation. It contains no Intel
DLL, CRU executable, graphics driver, prepackaged EDID dump or compiled
executable. The optional read-only collector can export the user's own EDID to
a local diagnostics folder when explicitly run.

## Credits

ClawLab performed the diagnosis, direct Intel API verification, EDID analysis,
real-hardware testing and packaging. Development was assisted collaboratively
by OpenAI Codex.

This project is not affiliated with MSI, Intel, Microsoft, ToastyX or Nexus
Mods.

## License

Original scripts and documentation are available under the [MIT License](LICENSE.txt).
