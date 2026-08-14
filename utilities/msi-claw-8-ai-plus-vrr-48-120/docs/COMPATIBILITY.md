# Compatibility

## Validated configuration

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

Disconnect external VRR displays while installing. The public build requires
exactly one active Intel Arc Sync output because the current Intel API does not
provide a stable user-facing monitor identifier in the profile call.

## Other Intel Arc systems

The official `EXCELLENT` profile is part of Intel Control Library and is not
specific to Arc 140V. The underlying technique may therefore work on other
Intel Arc Sync systems. This release remains Claw-panel-specific because only
that full hardware path has been validated.

The experimental EDID transformation is never generic. A different monitor can
store its range in different blocks and can have different electrical limits.

## Known limits

- Intel Graphics Software can show stale or profile-derived range information.
- Driver reinstallations can reset the Arc Sync profile; rerun official install
  and verify with `CHECK_STATUS.bat`.
- Experimental mode requires a restart before its EDID is active.
- Experimental 30 Hz operation is outside MSI's stated 48-120 Hz range and may
  flicker or fail on individual panels even with the same model identifier.
- The tool does not prove that every game presents frames through a VRR-capable
  swap chain.
