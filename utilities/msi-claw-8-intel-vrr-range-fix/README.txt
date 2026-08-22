MSI CLAW INTEL VRR RANGE FIX 2.3.0
=================================

SUPPORTED EXACT PANELS
----------------------
- MSI Claw A1M / Claw 7 AI+: TMA2027 / TL070FVXS02-0, 1920x1080.
- MSI Claw 8 AI+ / Claw 8 EX AI+: CSW0801 / PN8007QB1-2, 1920x1200.

STABLE INSTALLERS
-----------------
- INSTALL_30_120_VRR.bat: ClawLab default 30-120 Hz profile.
- INSTALL_48_120_VRR.bat: official Intel/MSI 48-120 Hz profile.
- UPDATE_CURSOR_REFRESH_ENGINE.bat: update/repair only the desktop cursor
  engine while preserving an already verified 2.3.0 VRR/LFC profile.

Both include the Intel LFC x2 correction and event-driven desktop cursor helper.
On the exact A1M / Claw 7 AI+ driver state with an immutable OEM CUSTOM 30-120
baseline, only INSTALL_30_120_VRR is available. The driver cannot establish the
standard baseline required by 48-120 or overclock profiles on that path.

EXPERIMENTAL FOLDER
-------------------
- 48-144 Hz: Stable Experimental. Tested on one MSI Claw 8 AI+ Polar Tempest.
- 48-165 Hz: Unstable Experimental, successfully tested on Claw 8 AI+
  hardware but still subject to individual panel silicon lottery.
- 48-180 Hz: Unstable Experimental, tested on one MSI Claw 8 AI+ Polar
  Tempest but still subject to individual panel silicon lottery.
- 48-192, 30-144, 30-165, 30-180 and 30-192 Hz: Unstable Experimental and
  untested.

Every value above 120 Hz is a display overclock outside MSI specifications.
Results depend on each panel's silicon lottery. The experimental installers
show risks throughout a 10-second countdown and ask for the exact typed phrase
once. After restart, the overclock is not applied until the user starts it from
a visible ready dialog. The exact final Windows/Intel state then runs inside an
animated 30-second test and is read back again at the end. No stable VRR, LFC
or Cursor Helper persistence is installed during that window. ClawLab then
attempts and verifies safe 120 Hz before asking for confirmation.
The one-time test runs with normal-user rights. The initial installer UAC also
registers that limited task as one transaction; scheduling failure rolls back
the pending profile. Its scripts are copied to a SHA-256-verified, administrator-
protected ProgramData directory. The final persistent change can show another
normal UAC prompt after Yes. Accept it only when you started this process.
If the screen flickers, shows artifacts or goes black, WAIT PATIENTLY. DO NOT
POWER OFF OR REBOOT. After Yes, the protected transaction verifies VRR first,
then LFC, then the Cursor Helper and persistence. No, no response within 30
seconds, any error, or failed verification enters exact saved-state recovery.
Windows restarts only after terminal recovery proof succeeds. If proof fails,
ClawLab does not restart automatically and preserves the evidence for
Diagnostics and Recovery.

The 192 Hz profiles can align with a 48 FPS x4 frame-generation output target.
They do not install, enable or guarantee XeSS/XeFG and are extreme overclocks.

MANDATORY BEFORE INSTALLATION
-----------------------------
1. Extract the complete ZIP.
2. If version 2.2.1 or any older ClawLab VRR release is installed, run
   RECOVERY\RESTORE_ORIGINAL_VRR.bat and complete the restart first. Prefer the
   matching older package when available. If its ZIP was deleted, current 2.3.0
   Recovery can use the retained legacy backup and preserve a newer Intel-signed
   Graphics Software startup entry after fresh verification. Version 2.3.0
   refuses to install over an unrestored older state. Do not use Factory Reset
   for a normal upgrade and never manually delete the ClawLab state directory.
3. If CRU was ever used, run reset-all.exe from the current official CRU
   release and restart Windows.
   If CRU was NEVER used on this Windows installation, no CRU reset is needed.
   ClawLab checks the real EDID_OVERRIDE registry values too. Any remaining
   CRU_* or other third-party metadata stops installation before a profile or
   EDID change is made.
4. Disable or remove every other tool that changes or reapplies VRR/EDID.
5. The only supported exception is ClawTweaks 3.0 or later:
   https://github.com/enterTheVoidCode/ClawTweaks
   ClawTweaks is OPTIONAL and is NOT required for ClawLab VRR to work.
6. Earlier ClawTweaks versions and all other VRR-writing tools must be disabled.
7. Disconnect every external display during installation and guarded trials.
   Only the validated internal panel may be active while refresh rate changes.
8. A clean first installation accepts Intel Arc Sync RECOMMENDED or EXCELLENT.
   If it finds an unmanaged CUSTOM profile, ClawLab does not save those unknown
   values. Intel Graphics Software cannot select the internal standard profiles
   manually. The installer tries RECOMMENDED, verifies fresh readback, and falls
   back to EXCELLENT if the driver silently retains CUSTOM. It saves only the
   first standard profile actually confirmed by the driver. Before the first
   setter, an atomic normalization-compensation journal captures the exact
   profile and device identity. A failed or interrupted normalization restores
   that snapshot; unresolved compensation blocks installation until Recovery
   resumes it. The only exception is the exact pinned TMA2027 OEM CUSTOM 30-120
   state. It is accepted only for
   INSTALL_30_120_VRR from 1920x1080 at 120 Hz after strict panel, timing,
   telemetry and direct-driver verification.

PROFILE SWITCHING
-----------------
Before applying any different stable or experimental profile, successfully run
RECOVERY\RESTORE_ORIGINAL_VRR.bat and complete the restart. The installer
refuses every cross-profile change. Only an exact same stable-profile repair is
allowed within version 2.3.0, and only when panel, EDID, mode and both original
backups still form one identity. It may rebuild missing managed tasks/payloads
or a narrowly recognized driver reset. A failure preserves the backups and
directs the user to Recovery.
An experimental profile must be restored before any new guarded trial, even at
the same range. Any managed 2.2.1-or-older state requires the upgrade
restoration described above.

A1M / CLAW 7 AI+ NOTE
---------------------
Intel Control Library can expose halved monitor-capability floors on the exact
TMA2027 panel: physical 48 Hz can read as 24 Hz, and an already managed 30 Hz
profile can read as 15 Hz. ClawLab treats both as telemetry only and validates
the selected active profile separately. The 15 Hz case also requires an exact
existing ClawLab 30 Hz managed record. It never creates or installs a 15 or
24 Hz mode.
The affected driver can also expose an exact OEM CUSTOM 30-120 profile while
rejecting RECOMMENDED and EXCELLENT writes. Version 2.3.0 preserves that exact
baseline without rewriting it. Select 1920x1080 at 120 Hz before installing;
1080p at 60 Hz is not sufficient.

LANGUAGES
---------
The public interface automatically follows the Windows display language for
the same 34 languages as Clawptimize. English is the fallback. Run
SELECT_LANGUAGE.bat to save a manual language or return to automatic detection.
Yes/No confirmations display the localized one-letter shortcuts, for example
[Y/N] in English and [O/N] in French. Press one letter once; Enter is not
required. A text fallback remains only for hosts without direct key input.
Technical status names and JSON property names remain English for support.
Runtime PowerShell code is code-page-independent ASCII and loads the external
translation catalog explicitly as UTF-8. Korean and other non-Western Windows
PowerShell 5.1 code pages therefore cannot corrupt script parsing.
Normal launch requests one UAC approval. If the launcher is already running as
administrator, ClawLab reuses that verified token instead of requesting a
second elevation.
Interactive tasks are registered with the account name resolved from the caller
SID and are verified by SID on readback. This fixes Windows accounts that reject
a raw SID in Task Scheduler UserId XML. Changing the system PowerShell policy
from RemoteSigned to Unrestricted is not required and does not fix this error.

STATUS
------
After installation and after every Intel driver update, run CHECK_STATUS.bat.
Expected core results include ProfileSwitchGuard CONSISTENT,
CLAWLAB_LFC_FIX_ACTIVE, both Intel solution flags False and LfcFixActive True.
Before the final requested restart, *_PENDING_RESTART,
READY_AT_NEXT_SIGN_IN and LfcFixActive False can be normal transitional values.
Complete that restart before judging final health.
After complete removal, CLEAN_NOT_INSTALLED, ManagedMode NONE and
ProfileSwitchGuard CLEAN are expected. Do not run Restore again in that state.
TransactionJournalPresent True takes precedence over those individual fields:
overall health is ATTENTION_REQUIRED and its action and phase are displayed.
Version 2.3.0 removes a false experimental scheduling journal only after a new
complete proof of original VRR/LFC state, task/runtime absence and verified
terminal LFC provenance.
One bounded legacy recovery also handles an absent VRR backup when fresh
readback proves the exact unmanaged Intel factory VRR/LFC state and the sole
remaining object is one provably owned invalid ClawLab startup task. CHECK_STATUS
reports ORPHANED_DEFAULT_VRR_SHELL_RECOVERABLE. Normal Restore then removes only
that stale task and its payloads; it never writes an Intel profile, display mode
or EDID. Every near match remains blocked.
The Cursor Refresh Engine starts from its own limited-user logon task. It uses
a native Win32/D3D11/DXGI flip-model surface, background Raw Input and a bounded
30-second startup warm-up. After VRR and LFC verify, the running process is
resynchronized in place; it is not restarted and no display profile is written.
The task has no delay and uses AboveNormal priority instead of Windows' default
BelowNormal background-task priority. Each native frame changes the 2x2
backbuffer between black and near-black so DWM cannot discard unchanged frames.
At mouse idle it blocks on kernel events with no polling or timer-resolution
request. WPF is retained only as an isolated compatibility fallback.

If only the desktop helper needs repair, run UPDATE_CURSOR_REFRESH_ENGINE.bat.
It preserves an already verified 2.3.0 VRR/LFC profile and does not require a
profile restore, reinstall, overclock retest or Windows restart.

RECOVERY
--------
- RECOVERY\RESTORE_ORIGINAL_VRR.bat: complete verified original-state restore.
  If that exact saved profile is already active, its redundant Intel driver
  write is skipped and cleanup completes only after exact readback. It also
  contains the bounded no-display-write cleanup for the exact legacy orphaned
  factory-state shell described above.
- RECOVERY\RESTORE_INTEL_LFC_DEFAULTS.bat: Intel LFC flags only.
- DIAGNOSTICS\EXPORT_STATUS_REPORT.bat: support report.
- EMERGENCY: use only for the explicitly named failure case.

Normal restore uses a durable write-ahead sequence: prepare LFC recovery while
retaining its backup, restore VRR, commit LFC only after exact readback, then
finalize terminal provenance after independent joint proof. Interrupted work is
resumable. A failed terminal proof keeps the evidence and does not trigger an
automatic restart. LFC Factory Defaults similarly retains verified durable
provenance for a future clean install.

Never delete %%LOCALAPPDATA%%\ClawLab manually. Unknown third-party EDID data is
refused and never removed by ClawLab.

SAFETY
------
This utility changes global Windows/Intel display state only. It does not patch,
inject into, hook, open or monitor a game process. It bundles no Intel driver,
CRU binary or proprietary EDID dump.
