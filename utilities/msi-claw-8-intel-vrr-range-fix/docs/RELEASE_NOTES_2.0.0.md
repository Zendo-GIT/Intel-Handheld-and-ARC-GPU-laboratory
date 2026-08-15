# MSI Claw Intel VRR Range Fix 2.0.0

Release 2.0.0 turns the original range selector into a complete, reversible
Intel VRR package for the exact `CSW0801 / PN8007QB1-2` panel used by validated
MSI Claw 8 AI+ and Claw 8 EX AI+ configurations.

## Recommended download choice

The release default is `INSTALL_30_120_VRR.bat`.

It combines:

- Intel `EXCELLENT` Arc Sync;
- the exact ClawLab 30-120 Hz EDID override;
- the community-validated Intel LFC x2 correction;
- hidden one-shot sign-in reapply;
- original-state backup and coordinated restore.

The correction removed the observed refresh multiplication where, for example,
60 FPS drove 120 Hz and 68 FPS drove 136 Hz. Both Intel low- and high-FPS VRR
solutions are disabled as one tested combination. LFC below 30 FPS is therefore
unavailable while this mode is active.

## Four profiles

| Installer | Role | Validation boundary |
|---|---|---|
| `INSTALL_30_120_VRR.bat` | Default 2.0.0 profile | Corrected combination validated on the reference Arc 140V system |
| `INSTALL_48_120_VRR.bat` | Official Intel/MSI profile | Native panel range through Intel's public `EXCELLENT` profile |
| `INSTALL_EXPERIMENTAL_48_144_VRR.bat` | Guarded panel-overclock trial | Fixed 144 Hz was stable on tested units; VRR at 144 Hz is not guaranteed |
| `INSTALL_EXPERIMENTAL_30_144_VRR.bat` | Guarded full-range trial | Visibly flickered on the reference panel; not recommended |

## 144 Hz failsafe

The two 144 Hz installers do not silently keep an unconfirmed range. At the next
sign-in, the tool waits until the driver verifies the requested profile, observes
it for 20 seconds, and displays a system-modal Yes/No confirmation.

- **Yes** keeps the profile and deletes the temporary confirmation task.
- **No**, closing the dialog, or no answer within 30 seconds selects 120 Hz,
  restores the previous profile and restarts Windows.
- Failure to verify the requested 144 Hz range also triggers rollback.

## Safety and reversibility

- Exact panel identity and pinned EDID hashes are mandatory.
- Cross-profile installation is refused until restore completes.
- Unknown third-party EDID overrides are never removed.
- Intel Graphics Software updates require a fresh valid Intel Authenticode
  signature before their changed executable identity is trusted.
- `RESTORE_ORIGINAL_VRR.bat` restores Intel solution flags, Arc Sync profile,
  EDID, tasks, installed scripts and the original Intel startup entry.
- `FACTORY_RESET_CLAWLAB_VRR.bat`, Safe Mode EDID recovery and SHA-256 manifests
  remain included.

## Game and anti-cheat boundary

The utility changes global display state only. It does not open, patch, inject
into, hook or monitor a game process. It installs no game DLL, overlay, driver,
service or continuous watchdog. No project can guarantee every third-party
anti-cheat policy, but this package has no direct game-process interaction.

## Validated reference

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V / Intel Arc 140V
- `CSW0801 / PN8007QB1-2`
- Windows 11
- Intel Graphics driver `32.0.101.8974` WHQL

Community reports also confirmed the official 48-120 profile on matching-panel
Claw 8 AI+ and Claw 8 EX AI+ units. Model name alone is never accepted.

Read `README.txt`, `docs/SAFETY.md` and `docs/COMPATIBILITY.md` before using an
experimental profile.
