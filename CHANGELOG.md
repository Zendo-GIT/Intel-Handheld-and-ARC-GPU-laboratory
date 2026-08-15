# Changelog

## 2026-08-16

- Prepared MSI Claw VRR Range Fix 2.1.0 with the real-hardware-validated
  event-driven Cursor Refresh Helper. Raw mouse activity briefly animates a
  nearly transparent 2x2 WPF/DWM surface at the extreme lower-right corner,
  raising the idle desktop from 30 Hz to 120 Hz without changing the LFC fix.
  The timer stops at idle and the animation is suppressed for hidden cursors
  while remaining compatible with Xbox Full Screen Experience. Installation, sign-in launch, status,
  integrity verification, restore cleanup and rebuildable C# source are included.
  The final helper removes per-input native allocations and was confirmed free
  of the prototype cursor micro-stutter. Added strict Claw A1M support using its
  exact `TMA2027 / TL070FVXS02-0` 128-byte EDID and a deterministic one-block
  30-120 transformation; A1M real-device behavior remains validation pending.

- Prepared MSI Claw VRR Range Fix 2.0.3 after a Claw 8 AI+ diagnostic proved
  that Intel Graphics Software and its machine Run entry may both be absent on
  a valid driver 8974 installation. The ordered startup backup now represents
  that absence without requiring a nonexistent executable, and elevated errors
  are persisted for support instead of disappearing with the UAC window.

- Prepared MSI Claw VRR Range Fix 2.0.2, removing every public 144 Hz installer
  and persistence path while retaining exact recovery support for older 144 Hz
  installations. Only corrected 30-120 and official 48-120 remain. Also fixed
  first-install recovery when the legacy LFC folder or Intel Graphics Software
  machine startup entry is absent.

- Prepared INAZUMA ELEVEN: Victory Road Offline Stutter Fix 1.0.1, correcting a
  false strict-mode failure when the uninstaller encountered exactly one
  remaining ClawLab firewall rule after restoring the vanilla executable.

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
