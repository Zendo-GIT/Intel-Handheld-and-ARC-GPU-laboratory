# MSI Claw Intel VRR Range Fix 2.0.2

Release 2.0.2 deliberately removes every public 144 Hz installation path.
Only two profiles remain:

- `INSTALL_30_120_VRR.bat`: default ClawLab profile with the shared Intel LFC
  x2 correction;
- `INSTALL_48_120_VRR.bat`: official Intel/MSI range with the same correction.

The retired 48-144 and 30-144 hashes remain internal recovery identifiers only.
Status, normal restore, factory reset and Safe Mode recovery can still recognize
and remove an exact profile installed by an older release. Version 2.0.2 cannot
install or persist either 144 Hz profile.

This release also fixes both first-install recovery failures reported by the
community:

- LFC cleanup is idempotent when an older `Intel-LFC-Fix` directory or one of
  its installed files never existed;
- a missing Intel Graphics Software machine startup entry is now treated as a
  valid original state, recorded explicitly, and restored as absent. It no
  longer leaves a first-time install in `MISSING_WITHOUT_BACKUP`.

The 30-120 LFC result remains real-hardware validated on the reference Arc 140V
system. Both installers save the original Intel low/high-FPS solution flags,
disable them as one combination, verify the selected range and reapply once at
sign-in without a continuous watcher.

Cross-profile installation remains refused until `RESTORE_ORIGINAL_VRR.bat`
completes. Unknown CRU or third-party EDID overrides are never removed.

Validated reference:

- MSI Claw 8 AI+ Polar Tempest;
- Intel Core Ultra 7 258V / Intel Arc 140V;
- `CSW0801 / PN8007QB1-2`;
- Windows 11;
- Intel graphics driver `32.0.101.8974` WHQL.
