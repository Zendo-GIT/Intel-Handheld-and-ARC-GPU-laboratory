# Compatibility

## Targeted Intel model family

- MSI Claw 8 AI+ A2VM / A2VMX
- MSI Claw 8 EX AI+ CG3EM / CG3EMX
- MSI Claw A1M
- MSI Claw 7 AI+

Each family is accepted only when the internal display returns one exact
catalogued identity and physical EDID. The installer does not infer
compatibility from a model name or public display specification alone.

| Family | Exact panel | Native mode | Physical EDID SHA-256 |
|---|---|---:|---|
| Claw 8 AI+ / 8 EX AI+ | `CSW0801 / PN8007QB1-2` | 1920x1200 at 120 Hz | `E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0` |
| Claw A1M / Claw 7 AI+ | `TMA2027 / TL070FVXS02-0` | 1920x1080 at 120 Hz | `3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1` |

## Real-hardware validation configuration

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V
- Intel Arc 140V
- internal panel `CSW0801 / PN8007QB1-2`
- physical EDID SHA-256
  `E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0`
- Intel Graphics driver `32.0.101.8974` WHQL
- Intel Graphics Software `26.18.2353.2`
- Windows 11

## Strict hardware check

The release checks the WMI monitor identity, canonical physical EDID length, full physical
EDID SHA-256, every declared EDID-block checksum, Intel Arc Sync support and connected-output
count. Any mismatch is rejected without modification.

This permits another Claw configuration using the exact validated display to
pass while still rejecting a future panel revision whose EDID differs.

The Claw A1M and Claw 7 AI+ share the exact 128-byte Tianma EDID definition,
including its valid base-block checksum and native 48-120 Hz range descriptor.
The generated 30-120 block is also pinned by full SHA-256. Diagnostics from
Core Ultra 5 and Core Ultra 7 A1M units showed Windows returning this exact
base block followed by 128 zero bytes. Release 2.1.2 accepts only that exact
zero-padding shape when the base EDID declares no extension, then still requires
the canonical pinned SHA-256. A non-zero tail remains refused. Release 2.1.2
performs the same fail-closed Intel API and active-range readback used on the
Claw 8 family. Because no physical A1M or Claw 7 AI+ was available during
development, their driver/LFC and panel behavior remain community-validation
pending; this is not presented as completed real-hardware validation.

Disconnect external VRR displays while installing. The public build requires
exactly one active Intel Arc Sync output because the current Intel API does not
provide a stable user-facing monitor identifier in the profile call.

## Mandatory CRU cleanup

If Custom Resolution Utility (CRU) has ever been used on the current Windows
installation, regardless of how long ago, whether CRU was deleted, or whether
its overrides now appear inactive, download the current official
[CRU release](https://www.monitortests.com/forum/Thread-Custom-Resolution-Utility-CRU),
run the included `reset-all.exe`, and restart Windows before installing
ClawLab. ToastyX documents `reset-all.exe` as the full-display reset path and
requires a reboot afterward.

This step is mandatory even when `CHECK_STATUS.bat` does not expose an active
CRU override. ClawLab cannot reliably determine whether CRU altered historical
display state, does not bundle CRU, and will not invoke an externally downloaded
executable automatically.

ClawTweaks is not a dependency. Its existing helper task is coordinated only
when detected; systems without ClawTweaks skip that optional wait and are fully
supported by the standalone ClawLab installer.

## Other Intel Arc systems

The official `EXCELLENT` profile is part of Intel Control Library and is not
specific to Arc 140V. The underlying technique may therefore work on other
Intel Arc Sync systems. This release remains exact-panel-specific: the Claw 8
path has real-hardware validation, while the shared A1M / Claw 7 AI+ entry has
exact EDID validation and deliberately awaits a first real-device result for
each model.

The custom EDID transformation is never generic. A different monitor can
store its range in different blocks and can have different electrical limits.

## Similar displays that are not supported

MSI specifies the AMD-powered Claw A8 BZ2EM with an 8-inch `1920x1200 /
48-120 Hz VRR` display, but the official mode in this package depends on Intel
Control Library and cannot run on its Radeon 890M. A dedicated A8 edition would
need a physical EDID capture and AMD-driver validation first.

The Lenovo Legion Go S also has similar published display characteristics. No
reliable source currently establishes that it uses the exact same panel and
EDID, so it is deliberately excluded.

## Known limits

- Intel Graphics Software can show stale or profile-derived range information.
- Driver reinstallations can reset the Arc Sync profile. Version 2.1.2 retains
  a replaced Intel Graphics Software executable, accepts it only after fresh
  Intel Authenticode validation, and then reapplies the managed profile. Verify
  the result with `CHECK_STATUS.bat` after every driver update. The overall
  report states whether the changed driver is already verified or needs repair.
- If the driver package recreates Intel Graphics Software's machine Run entry,
  status reports `ORIGINAL_STILL_PRESENT` or `MANAGED_COMMAND_REAPPEARED`;
  rerun the same-mode installer once to restore deterministic startup ordering.
- Some valid driver installations contain neither Intel Graphics Software nor
  its machine Run entry. Version 2.1.2 records that as an intentional original
  state and applies VRR without requiring or launching the optional app.
- A custom range requires a restart before its EDID is active.
- ClawLab 30 Hz operation is outside MSI's stated 48-120 Hz range and may
  flicker or fail on individual panels even with the same model identifier.
- Both 2.1.2 installers include Intel LFC component 2.0.4. Its stable schema-4
  backup tolerates only a verified Windows monitor-instance rename for the same
  exact physical panel after a driver update. It runs
  only after exact managed-mode, EDID and requested-range verification, and it
  reads both modified flags back from the driver.
- The observed removal of x2 refresh multiplication is validated on real
  hardware only with the exact ClawLab 30-120 mode on the reference Arc 140V /
  driver 32.0.101.8974 configuration. Official 48-120 uses the same guarded
  operation but is not yet a separate real-hardware LFC validation claim.
- Disabling both Intel low/high-FPS solutions removes Intel refresh
  multiplication below the selected floor. LFC below 30 FPS in a 30 Hz profile,
  or below 48 FPS in a 48 Hz profile, is consequently unavailable.
- A utility that forces Intel `RECOMMENDED` at sign-in or per game can overwrite
  the managed state. Use a configuration that leaves VRR settings untouched.
- Version 2.1.2 does not expose a 144 Hz profile. Older exact ClawLab 144 Hz
  states remain recognizable only so normal, factory or emergency recovery can
  return the display to 120 Hz. Unknown third-party data remains untouched.
- The tool does not prove that every game presents frames through a VRR-capable
  swap chain.
- The Cursor Refresh Helper is validated for the Windows desktop on the
  reference Claw. It is intentionally suppressed for hidden cursors, remains
  compatible with Xbox Full Screen Experience, and is not a game frame-pacing
  tool. After 1.5 seconds without usable visible-mouse input it enters deep idle,
  releases its timer-resolution request and waits for the next mouse packet.
  This covers controller/game profiles without detecting or depending on the
  utility that selected them.
- The factory reset is universal only across ClawLab VRR modes on an exact
  catalogued panel. It is not a generic CRU, monitor-driver or Windows reset.
