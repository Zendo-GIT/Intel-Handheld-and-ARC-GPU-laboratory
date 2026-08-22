# Safety and reversibility

## Scope and anti-cheat boundary

ClawLab changes only global Windows and Intel display configuration. It does not
open, enumerate, read, patch, hook, inject into or monitor a game process. It
installs no game DLL, overlay, service, kernel driver or network rule. The LFC
task runs once at sign-in and exits; only the optional desktop cursor helper is
resident and it has no Intel driver interface.

## Stable profiles

The public stable choices are 30–120 and official 48–120 Hz. The 30 Hz floor is
outside MSI's official range but does not overclock the 120 Hz maximum. It uses
a reversible Windows EDID override and never writes panel firmware. Official
48–120 leaves the physical EDID intact.

Both profiles use exact panel, EDID, Intel output, managed-state and driver
readback checks before LFC flags can change.

## Experimental overclock risk

Every 144, 165, 180 or 192 Hz maximum is a display overclock outside MSI
specifications. It can cause temporary flicker, scan lines, artifacts, an
unstable image or a black screen. Identical model names and EDIDs do not
guarantee identical headroom; the result depends on the individual panel
silicon lottery.

- 48–144 is **Stable Experimental** because it was tested on one MSI Claw 8 AI+
  Polar Tempest Edition. This does not make it official or universally safe.
- 48–165 and 48–180 remain **Unstable Experimental** despite successful Claw 8
  AI+ tests; individual panel silicon lottery still controls stability.
- 48–192, 30–144, 30–165, 30–180 and 30–192 are **Unstable Experimental** and
  have not been validated by ClawLab. The 192 Hz profiles are the highest risk
  and exist only as extreme silicon-lottery trials.

Each experimental BAT enforces a 10-second reading delay and exact typed risk
acknowledgement. No stable VRR, LFC or Cursor Refresh Helper persistence is
installed during the observation trial.

Disconnect every external display before the guarded trial. The validated
internal MSI Claw panel must be the only active display while Windows refresh
rate is changed; the runtime refuses the transition otherwise.

## Guarded 30-second trial

The first restart after an experimental request runs a one-time task with
normal-user (`RunLevel Limited`) rights. The initial elevated profile
transaction also registers this task; if registration fails, the pending EDID
and partial trial artifacts are rolled back together. Task Scheduler never
executes the trial script as administrator. The task and any later UAC action
use a SHA-256-manifested `%ProgramData%` runtime whose ACL gives standard users
read/execute access but no write access:

1. It verifies the exact panel, physical EDID, requested override, managed mode
   and trial record share one identity.
2. It waits for an explicit visible Start answer after sign-in; ignoring or
   declining this ready dialog never applies the overclock.
3. It explicitly selects the requested Windows maximum refresh and Intel
   `EXCELLENT` profile, then presents a dedicated animated 30-second window.
4. It independently verifies that the exact Windows maximum and Intel range
   remained active for the complete observation.
5. It attempts a return to the safe native 120 Hz mode in `finally` and verifies
   the result.
6. Only after verified safe restoration does it ask whether the target was
   reached and remained stable.

If the screen is black or corrupted, wait patiently. Do not power off or reboot
during the 30-second test. The bounded parent process still attempts safe 120 Hz
even if the visible observation process fails or cannot be seen.

Yes triggers a visible UAC request from that protected runtime. The terminal
transaction applies and verifies the requested VRR profile, applies and verifies
LFC, and only then validates the Cursor Refresh Helper and normal one-shot
persistence. No, a 30-second prompt timeout, a verification error or a failed
child action enters exact saved-state recovery. Windows restarts only after an
independent terminal proof confirms the original VRR/LFC state. If proof fails,
ClawLab does not restart automatically; it neutralizes the one-time task when
safe and preserves the recovery evidence for Diagnostics and Recovery.

## Restore-before-switch interlock

No direct profile switching is permitted. This applies to all models and to
every stable or experimental combination. A different requested mode is refused
until `RECOVERY\RESTORE_ORIGINAL_VRR.bat` completes successfully and Windows
restarts. Only an exact same **stable** profile can enter the 2.3.0 public
repair path. Its pre-existing original backups are never consumed by automatic
rollback. A confirmed experimental profile must be restored before any new
guarded trial, including a trial at the same range.

Same-stable repair additionally requires the exact panel, physical EDID,
managed mode and both original backups to remain one identity. It may repair a
narrowly recognized Intel driver reset or missing managed task/payload after an
update. Unknown `CUSTOM`, wrong-range or wrong-identity drift is refused. A
failed repair preserves the backups and requests Recovery.

A managed 2.2.1-or-older installation is also refused, even when it uses the
same range. Run the older release's `RECOVERY\RESTORE_ORIGINAL_VRR.bat`, finish
the restart, extract 2.3.0 to a new folder and install the desired profile.
Factory Reset is not required for this normal migration.

If the older ZIP no longer exists, current 2.3.0 Recovery may use the retained
legacy backup. An Intel Graphics Software Run entry changed by a later driver or
application update is preserved only after a fresh canonical-path, Intel
Authenticode and stable-file proof. Unknown or unsigned entries remain untouched
and block Recovery. System PowerShell policy changes are not a recovery step.

A clean first installation accepts Intel Arc Sync `RECOMMENDED` or `EXCELLENT`
directly. An unmanaged `CUSTOM` profile is never adopted as the original state:
it may belong to another VRR writer or a previous manually deleted installation.
Current Intel Graphics Software builds do not expose a control for selecting
the internal standard profiles. ClawLab first tries Intel `RECOMMENDED`, obtains
fresh readback, and tries `EXCELLENT` if the driver returned success but retained
`CUSTOM`. It saves only the first standard profile confirmed by exact profile-ID
verification. Failure stops before a backup or managed mode is created.

Before the first normalization setter can mutate an unmanaged `CUSTOM` profile,
ClawLab atomically writes `normalization-compensation.json` with the exact
profile, panel, GPU, driver and target identity. Failure or interruption restores
and verifies that snapshot. An unresolved compensation record blocks all new
installs until Recovery resumes it.

The only custom-baseline exception is the exact pinned TMA2027 OEM profile
observed on affected A1M / Claw 7 AI+ drivers: ID 7, 30–120 Hz, 8333/8333 µs,
known half-floor telemetry, clean direct 48–120 VRR state and both original LFC
flags enabled. It is accepted only by the 30–120 installer, with one display at
native 1920×1080 and 120 Hz. The exact state is saved and later preserved
without calling the rejected Intel setter. Any mismatch or drift is refused
before backup, EDID, task or display cleanup.

The core policy tests all ten managed modes (two stable plus eight experimental)
against all ten desired modes for both panel families. Its expected matrix
contains 20 same-mode recognitions and 180 cross-profile refusals, plus
clean-state and restore-required checks. The public coordinator narrows this
further: only the two stable same-profile cases can be repaired in place; every
overclock rerun requires a verified restore, completed restart and fresh guarded
trial.

## Intel LFC backup

Before disabling Intel's low/high-FPS solutions, the LFC component saves their
original values in a schema-4 backup bound to:

- exact physical panel identity and SHA-256;
- validated active EDID;
- managed VRR mode;
- Intel driver context and monitor-instance history.

The write is atomic and verified. Unknown panels, EDIDs, profiles or backup
identity changes fail closed. If original values are missing while a flag is
off, both normal installation and restoration refuse to guess or adopt that
modified state as the original. The separately labelled emergency factory
action turns both flags on only when no recoverable backup exists.

Normal complete restoration uses a write-ahead sequence. `PrepareRestore`
restores and verifies the original LFC flags while retaining the active backup;
VRR is then restored and verified; `CommitRestore` converts the backup into a
durable `restore-committed.json` record; an independent joint proof runs; and
`FinalizeRestore` converts it into verified `restore-finalized.json` provenance.
Only then may cleanup and automatic restart proceed. Every stage is resumable
after interruption.

Emergency LFC Factory Defaults writes `factory-default-intent.json` before the
first flag mutation and retains verified `factory-finalized.json` provenance at
the true/true target. A later clean install can safely adopt that exact terminal
state as its new original LFC backup. Ambiguous, missing or mismatched records
fail closed.

## A1M / Claw 7 telemetry rule

The `24–120 Hz` value observed in one Intel monitor-capability query on the
exact TMA2027 panel is accepted only as known half-physical telemetry. The
later observed `15–120 Hz` value is accepted only as half-managed telemetry
after an exact current-version ClawLab 30 Hz record already exists. In both
cases, the selected Intel profile, expected range and exact EDID are verified
independently. A clean or unmanaged 15 Hz reading remains rejected. No 15 or
24 Hz mode exists in the installers or EDID catalog.

## Third-party VRR ownership

Disable or remove all other software that writes or reapplies VRR/EDID state.
The only supported exception is
[ClawTweaks 3.0 or later](https://github.com/enterTheVoidCode/ClawTweaks), which
contains the ClawLab compatibility patch. ClawTweaks is not required: the VRR,
LFC, startup, recovery and cursor components all work standalone.

Earlier ClawTweaks releases and every other VRR-writing utility are considered
conflicts. A conflict can overwrite a verified profile after installation and
invalidate both status and restoration assumptions.

Any historical CRU use also requires `reset-all.exe` from the current official
CRU release followed by a restart. Unknown third-party EDID data is refused and
never deleted by ClawLab. If CRU has never been used on the Windows
installation, no CRU reset is needed.

Install and startup-apply paths inspect the actual `EDID_OVERRIDE` value names
as well as the EDID block hashes. Remaining `CRU_*` or other non-ClawLab
metadata causes a fail-closed refusal before a new profile is written. ClawLab
does not silently delete, adopt, or whitelist that state.

## Cursor helper boundary

The helper receives Windows Raw Input and presents through a non-activating 2×2
native Win32/D3D11/DXGI surface only during its bounded startup interval or
visible mouse activity. After 1.5 seconds of mouse inactivity it blocks on
kernel events with no polling loop, presentations or timer-resolution request.
Its dedicated task runs without elevation at `AboveNormal`; this only changes
scheduling latency while the event-driven helper is awake and grants no extra
privilege. Every active frame alternates two opaque black/near-black backbuffer
values so DWM sees real content changes.
It does not modify VRR, EDID or LFC and does not inspect, inject into or hook
games or controller-management applications.

Failure of native DXGI initialization falls back only to the previous WPF
desktop engine. It never triggers display-profile restoration. The dedicated
`UPDATE_CURSOR_REFRESH_ENGINE.bat` maintenance action first proves the existing
2.3.0 profile is consistent, then updates only helper files and its logon task;
it refuses profile drift without writing display state.

## Recovery rules

- Never manually delete `%LOCALAPPDATA%\ClawLab`.
- Use `RECOVERY\RESTORE_ORIGINAL_VRR.bat` for normal complete restoration.
- Use `RECOVERY\RESTORE_INTEL_LFC_DEFAULTS.bat` only for LFC flag restoration.
- Use `EMERGENCY` only for the exact labelled failure condition.
- If support is needed, export status JSON before changing anything else.
- Do not repeatedly alternate Restore and Factory Reset.
- Normal restore is idempotent: when the complete saved profile is already
  active, ClawLab skips the unnecessary ControlLib write, verifies the exact
  state and safely finishes cleanup.
- If an older installation has no original VRR backup, normal Restore can clean
  one orphaned legacy shell only when all independent evidence matches the
  pinned Intel factory state: exact panel/profile/range/timings, native 120 Hz,
  factory LFC flags, no EDID or normalization state, no other ClawLab task or
  recovery metadata, and one provably owned invalid VRR startup task. That path
  removes only the task and its payloads and performs no profile, mode or EDID
  write. Any missing or different fact is a hard refusal.
- If terminal recovery proof fails, do not reboot or delete state manually.
  ClawLab keeps the records, avoids automatic restart and requests a diagnostic
  export plus the appropriate Recovery action.
