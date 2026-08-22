# Nexus Mods listing copy

## Name

MSI Claw Intel VRR Range and LFC Fix

## Version

2.3.0

## Short description

Reversible Intel Arc VRR/LFC correction for exact MSI Claw A1M, 7 AI+, 8 AI+
and 8 EX AI+ internal panels, with stable 30–120/48–120 profiles and guarded
experimental display-overclock trials.

## Description

ClawLab 2.3.0 corrects the Intel refresh-multiplication/LFC behavior that can
turn values such as 60 FPS into 120 Hz while preserving exact restoration of
the original driver state. It supports only pinned internal-panel definitions
used by MSI Claw A1M, Claw 7 AI+, Claw 8 AI+ and Claw 8 EX AI+.

Stable installers provide ClawLab 30–120 Hz and official Intel/MSI 48–120 Hz.
Both include the Intel LFC patch, one-shot sign-in persistence and the
native event-driven desktop Cursor Refresh Engine. Its dedicated limited-user
logon task starts a Win32/D3D11/DXGI flip-model surface directly, before the
slower Intel startup pass. The running engine is resynchronized in place after
final VRR/LFC verification and blocks on kernel events at idle. WPF remains an
automatic helper-only compatibility fallback.

`UPDATE_CURSOR_REFRESH_ENGINE.bat` repairs or upgrades only this desktop
engine on an already verified 2.3.0 installation. It preserves the current
30–120, 48–120 or confirmed experimental profile and the Intel LFC state; no
profile restore, reinstallation, overclock retest or Windows restart is needed.

Version 2.3.0 adds a single public operation coordinator: VRR, Intel LFC,
backups and startup persistence are verified together across one initial UAC
boundary, and an incomplete installation is rolled back instead of being
reported as successful. Task Scheduler registration now uses exact COM
readback and semantic validation, fixing the collected “startup reapply task
could not be verified” failure.

The optional `EXPERIMENTAL` folder adds 48–144 Hz as Stable Experimental,
validated on one Claw 8 AI+ Polar Tempest Edition. 48–165 and 48–180 have
successful Claw 8 AI+ results but remain Unstable Experimental. The untested
48–192, 30–144, 30–165, 30–180 and 30–192 profiles are also Unstable
Experimental. Every value
above 120 Hz is an overclock outside MSI specifications and depends on the
individual panel silicon lottery.

Experimental installation shows the risks throughout a mandatory ten-second
countdown and asks for the exact typed phrase once. After restart, a visible
ready dialog starts a dedicated animated 30-second trial with exact end readback
and no stable VRR, LFC or Cursor Helper persistence. ClawLab attempts and
verifies safe 120 Hz before showing confirmation. After Yes, the terminal
transaction verifies VRR,
then LFC, then the helper and one-shot persistence. No, timeout or any failed
verification enters exact saved-state recovery. Windows restarts only after
terminal recovery proof succeeds; otherwise ClawLab keeps the evidence, does
not restart automatically and requests Diagnostics/Recovery.

Before installation, run `reset-all.exe` and restart if CRU was ever used. If
CRU was never used on that Windows installation, no CRU reset is needed.
Disable every other VRR/EDID-writing tool. The only supported exception is
[ClawTweaks 3.0 or later](https://github.com/enterTheVoidCode/ClawTweaks), which
includes the compatibility patch. ClawTweaks is optional and is not required
for ClawLab VRR to work.

A clean first installation accepts Intel Arc Sync `RECOMMENDED` or `EXCELLENT`
directly. If it finds an unmanaged `CUSTOM` profile, ClawLab does not save those
unknown values. Current Intel Graphics Software cannot select the internal
standard profiles manually, so the installer tries Intel `RECOMMENDED`, verifies
fresh readback, and falls back to `EXCELLENT` if the driver silently retains
`CUSTOM`. Only a standard profile confirmed by the driver is saved. The only
exception is the exact pinned TMA2027 OEM `CUSTOM 30–120` state observed on
Claw A1M and Claw 7 AI+. Version 2.3.0 may preserve it without a rejected Intel
setter only for the stable 30–120 installer, from 1920×1080 at 120 Hz, after
strict panel, timing, telemetry and direct-driver verification. It never
creates a 15 or 24 Hz profile. On TMA2027, the reported `24–120` value is Intel
telemetry derived from the physical 48 Hz floor; an observed `15–120` value is
recognized only after an exact managed 30 Hz profile is independently verified.

Changing to any different ClawLab profile always requires a successful
`RESTORE_ORIGINAL_VRR.bat` and restart first. The package refuses mixed states.
Only an exact same stable 2.3.0 profile can be repaired in place after a narrowly
recognized driver reset or missing managed task/payload. Panel, EDID, mode and
both original backups must still match; a failed repair preserves them.

When upgrading from 2.2.1 or any older managed release, first run
`RECOVERY\RESTORE_ORIGINAL_VRR.bat` from that older extracted package and
restart Windows. Then extract 2.3.0 into a new folder and install the desired
profile. Do not use Factory Reset for a normal upgrade. Version 2.3.0 detects
an older managed state and refuses installation until this restore is complete.

The public interface automatically follows the Windows display language in 34
languages, with English as a safe fallback. `SELECT_LANGUAGE.bat` can save a
manual preference or return to automatic detection. Technical status names and
diagnostic JSON fields remain English for worldwide support.

The utility changes global Windows/Intel display settings only. It does not
inject into, patch, hook or monitor any game process.

## Requirements

- Windows 11;
- Intel graphics driver with Intel Arc Sync support;
- exactly one active Intel Arc Sync display during installation;
- exact catalogued internal panel;
- complete ZIP extraction;
- no conflicting VRR/EDID tool.

## Installation

1. Read `README.txt`.
2. Optionally run `SELECT_LANGUAGE.bat` to override automatic language
   detection.
3. Complete the CRU and software-ownership preflights.
4. For normal use, run one root stable installer.
5. For a display overclock, open `EXPERIMENTAL`, read the warning and run only
   one guarded installer.
6. Restart when requested, explicitly start the guarded trial when ready, and
   do not interrupt its visible 30-second test.
7. Run `CHECK_STATUS.bat` after the final restart.

Before that final restart, `*_PENDING_RESTART`, `READY_AT_NEXT_SIGN_IN` and
`LfcFixActive: False` can be normal transitional values. Judge final health only
after completing the requested restart.

## Uninstallation

Run `RECOVERY\RESTORE_ORIGINAL_VRR.bat`, accept the restart, then confirm clean
status. Never delete `%LOCALAPPDATA%\ClawLab` manually.

Restore safely skips a redundant Intel write when exact readback proves that
the complete saved original profile is already active.

## Permissions and credits

MIT-licensed source is included. ClawLab is not affiliated with or endorsed by
MSI, Intel, Microsoft, CRU or ClawTweaks.
