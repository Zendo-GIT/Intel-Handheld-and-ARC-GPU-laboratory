# Changelog

## 2026-08-15

- Prepared MSI Claw VRR Range Fix 2.0.1 by extending the guarded Intel LFC x2
  correction to all four managed profiles. Added exact per-profile range/EDID
  verification, mode-bound backup, complete 144 Hz LFC/VRR rollback and build
  checks that reject an installer without the shared correction. Direct behavior
  remains validated at 30-120 Hz.

- Prepared MSI Claw VRR Range Fix 2.0.0 with the community-validated 30-120 Hz
  Intel LFC x2 correction, reversible driver-flag backup, windowless one-shot
  startup reapply, guarded 48-144/30-144 confirmation trials, and coordinated
  restoration. The correction is deliberately limited to the tested 30-120 Hz
  mode and installs no continuous watcher.

- Prepared MSI Claw VRR Range Fix 1.0.3 with signed Intel Graphics Software
  update detection and automatic trusted-identity renewal after driver updates.
- Retained the 48-144 Hz installer as an explicitly experimental fixed-refresh
  overclock after stable 144 Hz testing, while documenting that working VRR at
  144 Hz is not guaranteed. The flickering 30-144 profile remains recovery-only.

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
