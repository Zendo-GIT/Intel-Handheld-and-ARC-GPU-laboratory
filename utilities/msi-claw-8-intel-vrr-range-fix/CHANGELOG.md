# Changelog

## 2.2.0 — 2026-08-17

- Adds exact MSI Claw A1M and Claw 7 AI+ handling for Intel ControlLib's
  observed `24-120` monitor telemetry while continuing to expose only the
  supported `30-120` and `48-120` profiles. No 24 Hz profile exists.
- Keeps the exact `CSW0801 / PN8007QB1-2` path for MSI Claw 8 AI+ and Claw 8
  EX AI+, and the exact `TMA2027 / TL070FVXS02-0` path for Claw A1M and Claw 7
  AI+.
- Adds guarded display-overclock profiles for every supported exact panel:
  stable-experimental `48-144`, and unstable-experimental `48-165`, `48-180`,
  `30-144`, `30-165` and `30-180`.
- Labels overclock results as individual panel silicon lottery. Only `48-144`
  has been tested successfully on one Claw 8 AI+ Polar Tempest Edition; every
  other overclock profile remains untested and explicitly unstable.
- Enforces a 10-second warning delay and typed risk acceptance before any
  overclock is staged.
- Runs the requested refresh for no more than 15 seconds after restart, always
  returns to safe 120 Hz before asking for confirmation, and restores the
  original VRR/LFC state on No, timeout or failure.
- Runs the one-time trial task at limited user privilege from a protected,
  non-reparse `%ProgramData%` runtime with read/execute-only standard-user ACLs
  and a verified SHA-256 payload manifest; separately confirmed persistence
  requests its own elevation from that protected runtime.
- Selects and verifies the requested maximum refresh in Windows before a
  confirmed overclock is persisted.
- Refuses guarded Windows refresh-rate changes unless the validated internal
  panel is the only active display.
- Serializes duplicate sign-in reapply requests so the VRR and LFC tasks cannot
  race or launch duplicate cursor helpers.
- Starts the cursor helper before slow WMI/Intel initialization, waits internally
  for the interactive shell/DWM, then recreates its surface once after verified
  Intel startup so it is both prompt and effective.
- Builds a fresh protected DACL for the parent and versioned experimental runtime
  directories, fixing false missing-standard-user-read failures caused by reuse
  of a persisted .NET `DirectorySecurity` object.
- Extends the Intel LFC correction to all stable and experimental profiles.
- Refuses to adopt already-disabled Intel solution flags as original values
  when the original LFC backup is missing.
- Never adopts an unmanaged Intel Arc Sync `CUSTOM` profile as a clean
  first-install baseline. Because Intel Graphics Software cannot select the
  internal standard profiles manually, the installer tries `RECOMMENDED`,
  verifies fresh readback and falls back to `EXCELLENT` when the driver silently
  retains `CUSTOM`. Only a confirmed standard profile is saved.
- Makes original-profile restoration fully idempotent. Exact already-active
  CUSTOM ID/range/timing or standard-profile ID is verified without a redundant
  Intel setter call, fixing the collected A1M `0x40000017` recovery failure.
- Retries transient Intel device/KMD operations in fresh ControlLib sessions
  and separates internal target-drift errors from official Intel result codes.
- Reports a fully restored configuration as `CLEAN_NOT_INSTALLED` rather than
  the misleading `ATTENTION_REQUIRED`/Restore recommendation.
- Refuses to overwrite a managed 2.1.2-or-older installation; users must run
  that release's original-VRR restore and restart before installing 2.2.0.
- Tests every same-profile and cross-profile transition: reapplying an exact
  consistent 2.2.0 profile is idempotent, while every older or different
  profile requires a successful original-VRR restore and restart first.
- Requires exclusive ownership of VRR/EDID state. The only supported companion
  is [ClawTweaks 3.0 or later](https://github.com/enterTheVoidCode/ClawTweaks),
  which includes the compatibility patch; ClawTweaks remains optional and is
  not required for the standalone ClawLab fix.
- Retains mandatory `reset-all.exe` cleanup and restart whenever CRU was ever
  used on the Windows installation.
- Updates the Cursor Refresh Helper and release package to version 2.2.0.

## 2.1.2 — 2026-08-16

- Accepts the real A1M/Claw 7 AI+ Windows representation consisting of the
  exact pinned 128-byte EDID followed by 128 zero bytes; any non-zero tail or
  unknown canonical hash is still rejected.
- Records the same zero-padded representation on independently collected Core
  Ultra 5 and Core Ultra 7 Claw A1M diagnostics.
- Updates the Intel LFC component to 2.0.4 with atomic schema-4 stable panel
  identity, allowing a verified Windows monitor-instance rename after an Intel
  driver update without a restore/reinstall loop.
- Fixes schema-3 restoration on Windows PowerShell by using a real
  same-directory rollback path for atomic file replacement instead of an
  invalid null path.
- Restricts LFC application and startup reapply to exact 30-120 or 48-120
  driver readback; all other ranges fail before backup, persistence or flag
  changes.
- Keeps unverifiable schema-1/2 backups fail-closed and rejects every physical
  panel or EDID mismatch.
- Separates game-facing VRR/LFC health from optional desktop-helper health.
- Adds one-click read-only JSON status export under `DIAGNOSTICS`.
- Makes health and JSON diagnostics report failed status queries explicitly.
- Warns users never to delete `%LOCALAPPDATA%\ClawLab`, which contains the
  original state required for safe restoration.
- Detects a missing original backup with disabled Intel flags instead of
  claiming they are already restored, and adds a separate fail-closed emergency
  factory-default action that refuses to overwrite an existing backup.

## 2.1.1 — 2026-08-16

- Starts the Cursor Refresh Helper near the beginning of sign-in reapply instead
  of after the slower Intel driver stabilization path.
- Extends the cursor activity tail from 500 ms to 1.5 seconds to reduce rapid
  floor/ceiling transitions during short pauses.
- Adds source-agnostic controller/game deep idle: no usable visible-mouse input
  stops animation, releases the 1 ms timer-resolution request and trims the
  helper's own working set. The first visible raw-mouse packet resumes it.
- Keeps controller detection independent of ClawTweaks, MSI Center M or any
  other profile manager and adds no polling loop or game-process inspection.
- Adds an overall health report with explicit `HEALTHY`, `INITIALIZING` and
  `ATTENTION_REQUIRED` states plus Intel driver-change verification.
- Treats an installed helper from an older package as `VERSION_MISMATCH` rather
  than accepting its internally consistent old hash as current.
- Adds an interactive CRU preflight to both installers.
- Reorganizes the public ZIP: installers and status at root, normal restore in
  `RECOVERY`, destructive fallbacks in `EMERGENCY`, diagnostics in
  `DIAGNOSTICS`, and internal runtime components in `scripts`.
- Retains the unchanged 2.0.3 Intel LFC driver correction and both supported
  30-120 and official 48-120 profiles.

## 2.1.0 — 2026-08-16

- Added the real-hardware-validated Cursor Refresh Helper for the Windows
  desktop. Raw mouse activity animates a nearly transparent 2x2 WPF/DWM surface
  at the extreme lower-right corner so the panel rises from its idle VRR floor
  to 120 Hz.
- Stops the animation 500 milliseconds after mouse input; the high-frequency
  timer is not running at idle.
- Suppresses animation when the system cursor is hidden while remaining active
  in Windows Xbox Full Screen Experience.
- Uses standard Raw Input and desktop composition only, with no game injection,
  process hook, game-file access or modification of the existing LFC fix.
- Added helper binary integrity state, automatic sign-in launch, status,
  complete restore cleanup and publicly rebuildable C# source.
- Removed per-Raw-Input native allocations and extended the activity tail to
  500 ms, eliminating the cursor micro-stutter reproduced on the reference Claw.
- Added strict Claw A1M `TMA2027 / TL070FVXS02-0` support with its exact
  128-byte physical EDID and deterministic one-block 30-120 transformation.
- Generalized install, restore, factory and emergency recovery for one- or
  two-block catalogued panels without weakening unknown-override refusal.
- Added an offline A1M EDID generator/integrity test. A1M real-hardware
  driver/LFC and panel behavior remains community-validation pending.
- Fixed 2.1.0 sign-in orchestration so the LFC parent waits only for the direct
  VRR child, not for the resident Cursor Refresh Helper descendant. This keeps
  the one-shot task from reaching its four-minute execution limit.
- Made historical CRU cleanup explicit and mandatory: run `reset-all.exe` from
  the current official CRU release and restart before ClawLab installation,
  regardless of when CRU was used or whether it now appears inactive.

## 2.0.3 — 2026-08-15

- Fixed first installation when Intel Graphics Software and its machine Run
  entry are both absent, as confirmed by a Claw 8 AI+ / driver 8974 diagnostic.
- Added schema-4 startup state that preserves true application absence without
  constructing, validating or launching a nonexistent executable.
- Leaves a newly installed third-party Intel startup entry untouched during
  restore instead of deleting an external change.
- Persists elevated failure details in `last-error.txt` and echoes them back to
  the original console after a failed UAC child process.

## 2.0.2 — 2026-08-15

- Removed the 48-144 and 30-144 installers, confirmation task and every public
  144 Hz installation action.
- Retained exact legacy 144 Hz hashes only for status, normal restore, factory
  reset and Safe Mode recovery.
- Refuses startup or LFC persistence for a retired 144 Hz managed profile and
  directs the user to `RESTORE_ORIGINAL_VRR.bat`.
- Reduced the supported public choices to corrected 30-120 and official
  Intel/MSI 48-120.
- Made LFC and startup-file cleanup idempotent when a previous installation
  never created its local state directory.
- Added an explicit schema-3 startup backup for systems where Intel Graphics
  Software has no machine Run entry; normal restore now preserves that entry
  as absent instead of blocking first installation.

## 2.0.1 — 2026-08-15

- Integrated the community-validated Intel LFC x2 correction into all four
  installers. Its directly tested combination uses the `EXCELLENT` Arc Sync
  profile, the exact 30-120 Hz EDID override, and disables both Intel low- and
  high-FPS VRR solutions; every other profile receives the same operation only
  after its own exact mode, EDID and active-range verification.
- Replaced the 30-120-specific LFC companion with one profile-aware module whose
  backup is bound to the selected managed mode.
- Made both guarded 144 Hz confirmations require the requested range and both
  shared LFC flags before the 20-second observation can begin. Automatic
  rejection restores the original LFC and VRR state together.
- Added repository and release-build checks that reject any installer missing
  the shared LFC correction.
- Direct behavior remains real-hardware validated at 30-120 Hz; both 144 Hz
  profiles retain experimental status.
- Documented that disabling Intel's low-FPS solution removes LFC below the
  selected 30 or 48 Hz floor. Frames below that floor can still tear or stutter.

## 2.0.0 — 2026-08-15

- Integrated the community-validated Intel LFC x2 correction into the guarded
  30-120 Hz installer. The tested combination uses the `EXCELLENT` Arc Sync
  profile, the exact 30-120 Hz EDID override, and disables both Intel low- and
  high-FPS VRR solutions.
- Added a direct, readable D3DKMT Intel display-driver interface. It changes a
  global display setting only and never opens, patches, injects into or monitors
  a game process.
- Added an independent backup of both original Intel VRR solution flags, exact
  readback verification, a windowless one-shot logon reapply, and coordinated
  restore/factory-reset handling.
- Restricted the LFC x2 correction to the validated 30-120 Hz mode. Official
  48-120 Hz and optional 48-144 Hz remain separate and receive no unverified
  LFC claim.
- Documented that disabling Intel's low-FPS solution removes LFC below the new
  30 Hz floor. Frames below 30 FPS can still tear or stutter.
- Documented conflicts with display-profile tools that force Intel
  `RECOMMENDED` after sign-in or when a game starts. No resource-consuming
  background watchdog is installed.
- Reorganized the public choices around four profiles: default corrected
  30-120 Hz, official Intel/MSI 48-120 Hz, guarded 48-144 Hz, and guarded
  30-144 Hz.
- Added a one-time 144 Hz confirmation failsafe. After driver verification and
  20 seconds of observation, Yes keeps the profile; No, closing the dialog, a
  30-second timeout or verification failure restores 120 Hz and restarts
  Windows. The temporary task removes itself.
- Exposed 30-144 only through that guarded flow and retained the prominent
  disclosure that it visibly flickered on the reference panel.

## 1.0.3 — 2026-08-15

- Added safe Intel Graphics Software update detection: a replaced executable is
  trusted only after fresh Authenticode validation confirms Intel Corporation,
  the canonical path and original `-s` command, followed by stable SHA-256
  verification and an atomic identity-record update.
- Added automatic schema-2 migration for identities saved by earlier releases,
  including signer thumbprint, file version and SHA-256.
- Retained the 48-144 Hz installer as a clearly disclosed experimental panel
  overclock: fixed 144 Hz was stable on tested hardware, but VRR at 144 Hz or
  throughout the advertised range is not guaranteed.
- Kept the visibly flickering 30-144 profile unavailable and recovery-only,
  with an explicit rejected-profile status directing affected historical users
  to `RESTORE_ORIGINAL_VRR.bat`.

## 1.0.2 — 2026-08-15

- Added an optional 48-144 Hz DisplayID profile after guarded hardware testing
  confirmed 1920x1200 at 144 Hz and Intel `EXCELLENT / 48-144 Hz` readback.
- Recorded and withheld 30-144 Hz after visible flicker on the reference panel.
- Added a read-only display/EDID collector for unsupported Claw models such as
  the A1M; this is diagnostics only, not an A1M compatibility claim.
- Added verified fixed-refresh persistence for the 48-144 profile after
  community testing found Windows returning to 120 Hz after restart.
- Added startup-safe SHA-256 verification of the previously Authenticode-
  validated Intel Graphics Software executable.
- Added a mandatory managed-mode interlock that refuses every profile change
  until `RESTORE_ORIGINAL_VRR.bat` completes; same-mode repair remains allowed.
- Added `FACTORY_RESET_CLAWLAB_VRR.bat` to recover mixed or damaged ClawLab VRR
  state without requiring the saved original Arc Sync profile.

## 1.0.1 — 2026-08-15

- Added persistent `EXCELLENT / 48-120 Hz` reapply after restart validation
  showed Intel restoring `RECOMMENDED / 60-120 Hz` during driver startup.
- Added a windowless current-user task that retries until the Intel display API
  is ready, applies and verifies the profile, then starts Intel Graphics
  Software.
- Added exact backup and restoration of Intel Graphics Software's verified,
  Intel-signed machine-wide startup entry to guarantee launch order.
- Added task, startup-order and last-run status reporting.

## 1.0.0 — 2026-08-14

- Targeted compatible MSI Claw 8 AI+ and Claw 8 EX AI+ configurations through
  exact panel and EDID validation rather than model-name assumptions.
- Added direct Intel Arc Sync monitor and profile diagnostics through the
  official Intel Control Library.
- Added verified official `EXCELLENT / 48-120 Hz` installation.
- Added a separately marked experimental `30-120 Hz` Windows EDID override for
  the exact validated Claw panel and EDID only.
- Added original-profile backup, exact override verification, normal restore and
  API-independent emergency EDID removal.
- Added an explicit restart choice after installation and restoration.
- Added reproducible GitHub/Nexus packaging with no bundled executable or
  third-party binary.
