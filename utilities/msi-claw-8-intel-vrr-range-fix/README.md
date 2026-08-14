# MSI Claw 8 AI+ / 8 EX AI+ Intel VRR Range Fix

A transparent and reversible utility for the `CSW0801 / PN8007QB1-2` internal
panel used by compatible MSI Claw 8 AI+ and Claw 8 EX AI+ configurations.

![Version](https://img.shields.io/badge/release-1.0.1-blue)
![Official mode](https://img.shields.io/badge/official-48--120_Hz-green)
![Experimental modes](https://img.shields.io/badge/experimental-30--120_%7C_48--144_Hz-orange)
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
monitor VRR range. MSI documents both Claw Intel models with an 8-inch
`48-120 Hz VRR` display.

- [Intel Graphics Control Library Arc Sync API](https://intel.github.io/drivers.gpu.control-library/Control/api.html)
- [MSI Claw 8 AI+ specifications](https://www.msi.com/Handheld/Claw-8-AI-Plus-A2VMX/Specification)
- [MSI Claw 8 EX AI+ specifications](https://www.msi.com/Handheld/Claw-8-EX-AI-Plus-CG3EMX/Specification)

## Three deliberately separate modes

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
style `0`. The script waits silently for the display driver, applies and
verifies `EXCELLENT`, and only then starts Intel Graphics Software with its
original `-s` argument. No console window is displayed.

This mode does not modify the EDID, graphics driver, monitor firmware or any
game. Its only registry change is the reversible startup-order entry described
above.

### Experimental mode: 30-120 Hz

`INSTALL_EXPERIMENTAL_30_120_VRR.bat` is an optional validated-panel-only EDID
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

### Experimental mode: 48-144 Hz

`INSTALL_EXPERIMENTAL_48_144_VRR.bat` preserves the documented 48 Hz minimum
and adds a 1920x1200 144 Hz DisplayID detailed timing plus a 48-144 Hz maximum.
It is a panel overclock outside MSI's 120 Hz specification.

On the reference Claw 8, Windows exposed 1920x1200 at 144 Hz and Intel Control
Library directly verified `EXCELLENT / 48-144 Hz`. The image remained stable
after a transient burst of stutter and line artifacts while the Intel display
device reloaded. This does not prove that every unit has identical electrical
headroom. Persistent flicker, lines or blanking means the profile is unsuitable
for that unit and must be restored immediately.

The combined 30-144 Hz profile is deliberately not distributed. It was
accepted by the driver as `EXCELLENT / 30-144 Hz` but produced visible panel
flicker during real-hardware testing.

## Installation

1. Extract the release ZIP completely.
2. Close games and display-control applications.
3. Choose exactly one installer:
   - run `INSTALL_48_120_VRR.bat` for the recommended official mode and accept
     its administrator prompt; or
   - run `INSTALL_EXPERIMENTAL_30_120_VRR.bat` for the optional experimental
     low-range mode and accept its administrator prompt; or
   - run `INSTALL_EXPERIMENTAL_48_144_VRR.bat` for the optional experimental
     144 Hz panel-overclock mode and accept its administrator prompt.
4. Accept the final restart prompt, or restart the PC manually later.
5. After signing in, wait for Intel Graphics Software to start automatically;
   the VRR task runs before it.
6. Run `CHECK_STATUS.bat`.

The experimental installer first establishes the verified official profile,
then installs the EDID override. If status reports
an `EXPERIMENTAL_*_PENDING_RESTART` state, restart before evaluating the result.
Always restore one mode before selecting another.

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
EXPERIMENTAL_30_120_ACTIVE
EXPERIMENTAL_48_144_ACTIVE
DRIVER_PROFILE_CONSTRAINED
UNKNOWN_EDID_OVERRIDE
```

`StartupReapply` must show `Ready` or `Running` after installation. If it shows
`NOT_INSTALLED`, the driver can return to 60-120 Hz on the next restart.
`IntelGraphicsStartup` must show `CLAWLAB_ORDERED`; any unknown startup entry is
refused rather than overwritten.

## Restore and emergency recovery

Run `RESTORE_ORIGINAL_VRR.bat` to restore the first saved Intel Arc Sync profile
and remove the experimental EDID override if this package installed it. Restore
also unregisters the sign-in task, deletes its installed scripts and restores
the exact signed Intel startup entry. Restart the PC when prompted.

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
selection and validation. The experimental mode must never be copied blindly to
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
hook. Its scheduled task runs once after sign-in and exits immediately after
profile verification. Official mode changes a global display profile through
Intel's public API; experimental mode installs a Windows monitor EDID override.

This design has no direct interaction with anti-cheat software, but no project
can guarantee third-party anti-cheat policy. Keep the package documentation
available when reporting compatibility.

## Building the release

```powershell
.\tools\Build-Release.ps1 -Version 1.0.1
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
