# Compatibility

## Targeted Intel model family

- MSI Claw 8 AI+ A2VM / A2VMX
- MSI Claw 8 EX AI+ CG3EM / CG3EMX

Both model families are accepted only when the internal display returns the
exact `CSW0801 / PN8007QB1-2` identity and validated physical EDID below. The
installer does not infer compatibility from a model name or public display
specification alone.

## Real-hardware validation configuration

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V
- Intel Arc 140V
- internal panel `CSW0801 / PN8007QB1-2`
- physical EDID SHA-256
  `E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0`
- Intel Graphics driver `32.0.101.8864`
- Intel Graphics Software `26.18.2353.2`
- Windows 11

## Strict hardware check

The release checks the WMI monitor identity, physical EDID length, full physical
EDID SHA-256, both EDID checksums, Intel Arc Sync support and connected-output
count. Any mismatch is rejected without modification.

This permits another Claw configuration using the exact validated display to
pass while still rejecting a future panel revision whose EDID differs.

Disconnect external VRR displays while installing. The public build requires
exactly one active Intel Arc Sync output because the current Intel API does not
provide a stable user-facing monitor identifier in the profile call.

## Other Intel Arc systems

The official `EXCELLENT` profile is part of Intel Control Library and is not
specific to Arc 140V. The underlying technique may therefore work on other
Intel Arc Sync systems. This release remains exact-panel-specific because only
that full hardware path has been validated.

The experimental EDID transformation is never generic. A different monitor can
store its range in different blocks and can have different electrical limits.

## Similar displays that are not supported

The Intel-powered MSI Claw A1M has a different 7-inch `1920x1080 / 120 Hz`
display. A model name and maximum refresh rate do not establish its panel
identity, EDID layout, VRR floor or safe overclock limit. This release therefore
refuses the A1M. Owners can run `COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat` to create
a read-only JSON/EDID diagnostic bundle for future research. The collector does
not apply a profile or prove compatibility.

MSI specifies the AMD-powered Claw A8 BZ2EM with an 8-inch `1920x1200 /
48-120 Hz VRR` display, but the official mode in this package depends on Intel
Control Library and cannot run on its Radeon 890M. A dedicated A8 edition would
need a physical EDID capture and AMD-driver validation first.

The Lenovo Legion Go S also has similar published display characteristics. No
reliable source currently establishes that it uses the exact same panel and
EDID, so it is deliberately excluded.

## Known limits

- Intel Graphics Software can show stale or profile-derived range information.
- Driver reinstallations can reset the Arc Sync profile; rerun official install
  and verify with `CHECK_STATUS.bat`.
- Experimental mode requires a restart before its EDID is active.
- Experimental 30 Hz operation is outside MSI's stated 48-120 Hz range and may
  flicker or fail on individual panels even with the same model identifier.
- Experimental 48-144 Hz is a panel overclock. It was stable on the reference
  unit after transient reload artifacts but is not guaranteed on every unit.
- Combined 30-144 Hz is intentionally unavailable because the reference panel
  visibly flickered while that range was active.
- The tool does not prove that every game presents frames through a VRR-capable
  swap chain.
