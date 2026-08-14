# Safety

## Official mode

Official mode calls only these Intel Control Library functions:

- `ctlInit`
- `ctlEnumerateDevices`
- `ctlEnumerateDisplayOutputs`
- `ctlGetIntelArcSyncInfoForMonitor`
- `ctlGetIntelArcSyncProfile`
- `ctlSetIntelArcSyncProfile`
- `ctlClose`

The requested profile is `CTL_INTEL_ARC_SYNC_PROFILE_EXCELLENT`. The result is
accepted only when the driver reads back `EXCELLENT / 48-120 Hz`.

## Experimental mode

Experimental mode writes two binary registry values named `0` and `1` under the
validated monitor instance's `Device Parameters\EDID_OVERRIDE` key. This is the
per-block Windows mechanism documented by Microsoft. It does not write the
panel EEPROM.

Before writing, the tool requires the complete physical EDID SHA-256 and both
block checksums. After writing, it requires exact SHA-256 values for both
generated blocks. An existing unknown override is never replaced or deleted.

Administrative elevation is requested only for experimental EDID installation
or removal. Official profile installation does not require elevation.

## Recovery

The first original Intel profile is saved under the current user's local
ClawLab state directory and is not overwritten by repeated installation.

Normal restore verifies and removes only this package's EDID blocks, restores
the saved Intel profile, and asks for a restart. Emergency restore uses the
recorded exact registry path and hard-coded block SHA-256 values. It does not
load Intel Control Library and can be used from Safe Mode.

## What it never does

- no monitor EEPROM or firmware write;
- no graphics-driver file replacement;
- no generic or heuristic EDID patch;
- no unknown EDID-override removal;
- no game executable, asset, process or memory modification;
- no DLL injection, overlay, hook or background service;
- no power-plan, BIOS, network or anti-cheat modification;
- no bundled Intel, MSI, Microsoft or CRU binary.
