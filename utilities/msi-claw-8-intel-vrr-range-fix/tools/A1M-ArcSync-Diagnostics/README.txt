CLAWLAB A1M ARC SYNC RAW DIAGNOSTICS 1.0.0
================================================

Purpose
-------
This temporary diagnostic package investigates the conflicting VRR values
reported on MSI Claw A1M systems. It accepts only the exact pinned
TMA2027 / TL070FVXS02-0 physical EDID.

Safety
------
- Read-only collection only.
- No Intel profile setter is included in the Arc Sync query component.
- No EDID, registry value, Intel VRR flag, task, service or display mode is
  changed.
- Administrator privileges are not required.
- It does not open, inspect or inject into any game process.

Instructions
------------
1. Extract the complete ZIP to a normal folder.
2. Double-click COLLECT_A1M_ARCSYNC_RAW.bat.
3. Wait for the PASS message.
4. Send back the ClawLab-A1M-ArcSync-Raw-*.json file created on the Desktop.

Do not run any VRR installer, Restore or Factory Reset for this diagnostic.
