# Changelog

## 2026-08-15

- Finalized MSI Claw 8 AI+ / 8 EX AI+ VRR Range Fix 1.0.1 after full-restart
  validation showed Intel restoring `RECOMMENDED / 60-120 Hz` during startup.
  The windowless current-user task now applies and verifies
  `EXCELLENT / 48-120 Hz` before launching Intel Graphics Software, with exact
  backup and restoration of Intel's original startup entry.
- Added guarded 48-144 Hz support after direct Intel-driver and display-mode
  validation; rejected the combined 30-144 Hz range after visible panel flicker.
- Added a read-only display/EDID collector for future Claw A1M research.
- Fixed 48-144 Hz restart persistence by making the ordered task reselect the
  fixed 144 Hz Windows mode before final Intel Arc Sync verification.
- Added a mandatory VRR profile-switch interlock and a hash-restricted ClawLab
  factory recovery path for damaged or mixed VRR state.

## 2026-08-14

- Rebuilt the public project as one unified MSI Claw Game Optimization Lab repository.
- Moved all game-specific material under a single `games` hierarchy.
- Added shared scope, release, contribution, security, and anti-cheat policies.
- Added a shared release builder and repository validation workflow.
- Added INAZUMA ELEVEN: Victory Road Offline Stutter Fix 1.0.0.
- Added Detroit: Become Human Intel Arc Stability Fix 1.0.0 with verified
  unsupported-GPU dialog suppression, cache-aware launch safeguards and
  transition presentation recovery, plus optional reversible Steam Play
  integration.
- Added MSI Claw 8 AI+ / 8 EX AI+ VRR Range Fix 1.0.0 with a validated official
  48-120 Hz Intel Arc Sync profile, exact status reporting, reversible recovery,
  and a separately marked panel-specific experimental 30-120 Hz EDID override.

Game-specific changes remain documented in each game folder.
