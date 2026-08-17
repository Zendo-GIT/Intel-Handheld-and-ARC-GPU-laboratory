# Nexus Mods listing copy

## Name

MSI Claw Intel VRR Range and LFC Fix

## Version

2.2.0

## Short description

Reversible Intel Arc VRR/LFC correction for exact MSI Claw A1M, 7 AI+, 8 AI+
and 8 EX AI+ internal panels, with stable 30–120/48–120 profiles and guarded
experimental display-overclock trials.

## Description

ClawLab 2.2.0 corrects the Intel refresh-multiplication/LFC behavior that can
turn values such as 60 FPS into 120 Hz while preserving exact restoration of
the original driver state. It supports only pinned internal-panel definitions
used by MSI Claw A1M, Claw 7 AI+, Claw 8 AI+ and Claw 8 EX AI+.

Stable installers provide ClawLab 30–120 Hz and official Intel/MSI 48–120 Hz.
Both include the Intel LFC patch, one-shot sign-in persistence and the
event-driven desktop cursor helper.

The optional `EXPERIMENTAL` folder adds 48–144 Hz as Stable Experimental,
validated on one Claw 8 AI+ Polar Tempest Edition, plus untested Unstable
Experimental 48–165, 48–180, 30–144, 30–165 and 30–180 profiles. Every value
above 120 Hz is an overclock outside MSI specifications and depends on the
individual panel silicon lottery.

Experimental installation is protected by a mandatory warning and reading
delay, typed risk acceptance, automatic 15-second trial, unconditional return
to safe 120 Hz, and a confirmation shown only after safe restoration. A No
answer, a timeout or any failed verification restores the original state
automatically.

Before installation, run `reset-all.exe` and restart if CRU was ever used. If
CRU was never used on that Windows installation, no CRU reset is needed.
Disable every other VRR/EDID-writing tool. The only supported exception is
[ClawTweaks 3.0 or later](https://github.com/enterTheVoidCode/ClawTweaks), which
includes the compatibility patch. ClawTweaks is optional and is not required
for ClawLab VRR to work.

A clean first installation accepts Intel Arc Sync `RECOMMENDED` or `EXCELLENT`
directly. If it finds an unmanaged `CUSTOM` profile, ClawLab does not save those
unknown values. Current Intel Graphics Software cannot select the internal
standard profiles manually, so the installer automatically forces Intel
`RECOMMENDED`, verifies fresh driver readback and only then saves that official
restoration baseline.

Changing to any different ClawLab profile always requires a successful
`RESTORE_ORIGINAL_VRR.bat` and restart first. The package refuses mixed states.

When upgrading from 2.1.2 or any older managed release, first run
`RECOVERY\RESTORE_ORIGINAL_VRR.bat` from that older extracted package and
restart Windows. Then extract 2.2.0 into a new folder and install the desired
profile. Do not use Factory Reset for a normal upgrade. Version 2.2.0 detects
an older managed state and refuses installation until this restore is complete.

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
2. Complete the CRU and software-ownership preflights.
3. For normal use, run one root stable installer.
4. For a display overclock, open `EXPERIMENTAL`, read the warning and run only
   one guarded installer.
5. Restart when requested and do not interrupt an experimental 15-second test.
6. Run `CHECK_STATUS.bat` after the final restart.

## Uninstallation

Run `RECOVERY\RESTORE_ORIGINAL_VRR.bat`, accept the restart, then confirm clean
status. Never delete `%LOCALAPPDATA%\ClawLab` manually.

Restore safely skips a redundant Intel write when exact readback proves that
the complete saved original profile is already active.

## Permissions and credits

MIT-licensed source is included. ClawLab is not affiliated with or endorsed by
MSI, Intel, Microsoft, CRU or ClawTweaks.
