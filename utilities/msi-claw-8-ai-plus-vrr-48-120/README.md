# MSI Claw 8 AI+ Intel Arc Sync VRR Range Fix

A transparent and reversible utility for the `CSW0801 / PN8007QB1-2` internal
panel used by the validated MSI Claw 8 AI+ configuration.

![Version](https://img.shields.io/badge/release-1.0.0-blue)
![Official mode](https://img.shields.io/badge/official-48--120_Hz-green)
![Experimental mode](https://img.shields.io/badge/experimental-30--120_Hz-orange)
![License](https://img.shields.io/badge/license-MIT-green)

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
monitor VRR range. MSI documents the Claw 8 AI+ display as `48-120 Hz VRR`.

- [Intel Graphics Control Library Arc Sync API](https://intel.github.io/drivers.gpu.control-library/Control/api.html)
- [MSI Claw 8 AI+ specifications](https://www.msi.com/Handheld/Claw-8-AI-Plus-A2VMX/Specification)

## Two deliberately separate modes

### Official mode: 48-120 Hz

`INSTALL_48_120_VRR.bat` selects Intel's official `EXCELLENT` Arc Sync profile
through `ControlLib.dll`, then reads the profile back from the driver and
requires an exact `48-120 Hz` result.

This mode does not modify the EDID, registry, graphics driver, monitor firmware
or any game.

### Experimental mode: 30-120 Hz

`INSTALL_EXPERIMENTAL_30_120_VRR.bat` is an optional Claw-panel-only EDID
override comparable in purpose to configuring the range with ToastyX Custom
Resolution Utility (CRU). It changes the minimum from 48 to 30 in copies of the
base EDID range descriptor and DisplayID Adaptive-Sync block, recalculates both
checksums, and writes only those two verified 128-byte override blocks using
Windows' documented `EDID_OVERRIDE` mechanism.

The physical panel EEPROM is never written. A restart is required for Windows
and the Intel driver to reload the override. This mode is outside MSI's
specified range and can cause flicker, blanking or other display instability.
It is explicitly experimental and must not be represented as MSI-certified.

- [Microsoft EDID override documentation](https://learn.microsoft.com/windows-hardware/drivers/display/overriding-monitor-edids)
- [Official CRU support thread](https://www.monitortests.com/forum/Thread-Custom-Resolution-Utility-CRU)

No CRU file is bundled or required.

## Installation

1. Extract the release ZIP completely.
2. Close games and display-control applications.
3. Choose exactly one installer:
   - run `INSTALL_48_120_VRR.bat` for the recommended official mode; or
   - run `INSTALL_EXPERIMENTAL_30_120_VRR.bat` for the optional experimental
     mode and accept its administrator prompt.
4. Accept the final restart prompt, or restart the PC manually later.
5. Run `CHECK_STATUS.bat` after Windows starts again.

The experimental installer first establishes the verified official profile,
then installs the EDID override. If status reports
`EXPERIMENTAL_OVERRIDE_PENDING_RESTART`, restart before evaluating the result.

## Status versus Intel Graphics Software

Intel Graphics Software can continue displaying a cached or profile-derived
`60-120 Hz` value. `CHECK_STATUS.bat` reads the monitor capability and active
profile directly from the Intel Control Library and separately verifies the
Windows EDID override. Its result is the package's authoritative status.

Expected states include:

```text
OFFICIAL_48_120_ACTIVE
EXPERIMENTAL_OVERRIDE_PENDING_RESTART
EXPERIMENTAL_30_120_ACTIVE
DRIVER_PROFILE_CONSTRAINED
UNKNOWN_EDID_OVERRIDE
```

## Restore and emergency recovery

Run `RESTORE_ORIGINAL_VRR.bat` to restore the first saved Intel Arc Sync profile
and remove the experimental EDID override if this package installed it. Restart
the PC when prompted.

The original profile is stored under:

```text
%LOCALAPPDATA%\ClawLab\Intel-Arc-Sync-Full-Range\original-profile.json
```

If experimental mode causes a display problem, boot Windows Safe Mode and run
`EMERGENCY_REMOVE_EXPERIMENTAL_EDID.bat`. This path does not initialize the
Intel graphics API. It removes only override blocks whose SHA-256 values match
this package, then asks for a restart. After normal Windows returns, run the
regular restore script to restore the saved Intel profile.

## Compatibility boundary

The official Intel API mechanism may be useful on other Intel Arc Sync systems,
but this release intentionally accepts only:

```text
Panel ID: CSW0801
Panel name: PN8007QB1-2
Physical EDID SHA-256:
E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0
```

This is a display-specific safeguard, not a claim that other Intel Arc GPUs are
incapable. A future generic edition needs separate monitor selection and
validation. The experimental mode must never be copied blindly to another EDID.

## Anti-cheat boundary

The utility does not open, inject into, patch, monitor or control game
processes. It modifies no game file and installs no runtime service, overlay or
hook. Official mode changes a global display profile through Intel's public API;
experimental mode installs a Windows monitor EDID override.

This design has no direct interaction with anti-cheat software, but no project
can guarantee third-party anti-cheat policy. Keep the package documentation
available when reporting compatibility.

## Building the release

```powershell
.\tools\Build-Release.ps1 -Version 1.0.0
```

The ZIP contains only readable scripts and documentation. It contains no Intel
DLL, CRU executable, graphics driver, EDID binary dump or compiled executable.

## Credits

ClawLab performed the diagnosis, direct Intel API verification, EDID analysis,
real-hardware testing and packaging. Development was assisted collaboratively
by OpenAI Codex.

This project is not affiliated with MSI, Intel, Microsoft, ToastyX or Nexus
Mods.

## License

Original scripts and documentation are available under the [MIT License](LICENSE.txt).
