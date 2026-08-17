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

Every 144, 165 or 180 Hz maximum is a display overclock outside MSI
specifications. It can cause temporary flicker, scan lines, artifacts, an
unstable image or a black screen. Identical model names and EDIDs do not
guarantee identical headroom; the result depends on the individual panel
silicon lottery.

- 48–144 is **Stable Experimental** because it was tested on one MSI Claw 8 AI+
  Polar Tempest Edition. This does not make it official or universally safe.
- 48–165, 48–180, 30–144, 30–165 and 30–180 are **Unstable Experimental** and
  have not been validated by ClawLab.

Each experimental BAT enforces a 10-second reading delay and exact typed risk
acknowledgement. The profile is never persisted immediately.

Disconnect every external display before the guarded trial. The validated
internal MSI Claw panel must be the only active display while Windows refresh
rate is changed; the runtime refuses the transition otherwise.

## Guarded 15-second trial

The first restart after an experimental request runs a one-time task with
normal-user (`RunLevel Limited`) rights. The initial elevated profile
transaction also registers this task; if registration fails, the pending EDID
and partial trial artifacts are rolled back together. Task Scheduler never
executes the trial script as administrator. The task and any later UAC action
use a SHA-256-manifested `%ProgramData%` runtime whose ACL gives standard users
read/execute access but no write access:

1. It verifies the exact panel, physical EDID, requested override, managed mode
   and trial record share one identity.
2. It explicitly selects the requested Windows maximum refresh and Intel
   `EXCELLENT` profile.
3. It limits the attempted high-refresh window to 15 seconds.
4. It unconditionally returns Windows to the safe native 120 Hz mode.
5. Only after safe restoration does it ask whether the target was reached and
   remained stable.

If the screen is black or corrupted, wait patiently. Do not power off or reboot
during the 15-second test. The task continues without relying on visible output.

Yes triggers a visible UAC request from that protected runtime, then a second
exact verification, selects
the requested Windows maximum, applies LFC and installs normal one-shot
persistence. No, a 30-second prompt timeout, a verification error or a failed
child action restores the
original profile and LFC state and restarts Windows.

## Restore-before-switch interlock

No direct profile switching is permitted. This applies to all models and to
every stable or experimental combination. A different requested mode is refused
until `RECOVERY\RESTORE_ORIGINAL_VRR.bat` completes successfully and Windows
restarts. Only exact same-profile repair within version 2.2.0 is idempotent.

A managed 2.1.2-or-older installation is also refused, even when it uses the
same range. Run the older release's `RECOVERY\RESTORE_ORIGINAL_VRR.bat`, finish
the restart, extract 2.2.0 to a new folder and install the desired profile.
Factory Reset is not required for this normal migration.

A clean first installation accepts Intel Arc Sync `RECOMMENDED` or `EXCELLENT`
directly. An unmanaged `CUSTOM` profile is never adopted as the original state:
it may belong to another VRR writer or a previous manually deleted installation.
Current Intel Graphics Software builds do not expose a control for selecting
the internal standard profiles. ClawLab first tries Intel `RECOMMENDED`, obtains
fresh readback, and tries `EXCELLENT` if the driver returned success but retained
`CUSTOM`. It saves only the first standard profile confirmed by exact profile-ID
verification. Failure stops before a backup or managed mode is created.

The release includes an offline test of all eight managed modes against all
eight desired modes for both panel families. Its expected matrix contains 16
same-profile approvals and 112 cross-profile refusals, plus clean-state and
restore-required checks.

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

## A1M / Claw 7 telemetry rule

The `24–120 Hz` value observed in one Intel monitor-capability query on the
exact TMA2027 panel is not treated as a profile. It is accepted only as known
half-physical telemetry while the selected Intel profile and exact EDID are
verified independently. No 24 Hz mode exists in the installers or EDID catalog.

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

The helper receives Windows Raw Input and presents a nearly transparent 2×2 WPF
surface only while a visible mouse moves. After 1.5 seconds it stops animation,
releases its timer-resolution request, trims only its own working set and waits
in the Windows message loop. It does not modify VRR, EDID or LFC state and does
not interact with games or controller-management applications.

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
