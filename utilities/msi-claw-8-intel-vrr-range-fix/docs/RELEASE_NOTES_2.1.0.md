# MSI Claw Intel VRR Range Fix 2.1.0

Release 2.1.0 is the stable public release of the event-driven Cursor Refresh
Helper together with the hardened 2.0.3 installation path.

## Desktop refresh correction

On the validated Claw 30-120 Hz configuration, Windows can leave the complete
desktop at 30 Hz while only the hardware mouse cursor moves. Scrolling or a real
window animation raises the panel to 120 Hz. Real-hardware investigation showed
that compositor-clock requests and pointer trails did not change this behavior,
while a genuine WPF/DWM animation did.

The new helper:

- receives standard Windows Raw Input without a global code hook;
- animates a nearly transparent 2x2 WPF/DWM surface at the extreme lower-right
  corner only during visible mouse movement;
- stops its 8 ms animation timer 500 ms after the last mouse event;
- has no active high-frequency timer at idle;
- suppresses animation when the system cursor is hidden while remaining active
  inside Windows Xbox Full Screen Experience;
- never injects into, hooks, patches, opens, enumerates or reads a game process;
- does not change the Intel LFC flags, Arc Sync profile or EDID.

Testing on the reference MSI Claw confirmed repeatable transitions from 30 Hz
idle to 120 Hz during mouse movement and back to 30 Hz after movement, with the
2x2 surface visually imperceptible. The final helper removes per-packet native
buffer allocations and keeps the wake animation alive for 500 ms, eliminating
the cursor micro-stutter observed during the first prototype.

## A1M exact-panel integration

Release 2.1.0 adds a second strict panel definition for the Intel-powered MSI
Claw A1M:

- identity: `TMA2027 / TL070FVXS02-0`;
- native mode: 1920x1080 at 120 Hz;
- physical EDID: one 128-byte block, SHA-256
  `3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1`;
- generated 30-120 EDID: SHA-256
  `7B5EE7D96BC91E83EBD2419B3A4F12771035D76303F77EEB0E356C996BFA4647`.

The script now selects the panel definition automatically, validates its exact
EDID length and checksum layout, and writes only the EDID blocks that exist.
Claw 8/8 EX legacy 144 Hz hashes remain recovery-only and are never associated
with the A1M. A1M installation still requires exact Intel API and active-range
readback. Its EDID path is reproducibly verified, but real A1M driver/LFC and
panel testing remains pending.

## Installation and recovery

Both `INSTALL_30_120_VRR.bat` and `INSTALL_48_120_VRR.bat` install the helper.
The existing limited current-user sign-in task launches it only after the Arc
Sync profile has been reapplied and verified. The package records the installed
binary SHA-256 and refuses startup after a mismatch.

`CHECK_STATUS.bat` reports the helper as `RUNNING_EVENT_DRIVEN` after sign-in.
`RESTORE_ORIGINAL_VRR.bat` stops only the exact installed helper path and removes
its binary and integrity state along with the other managed components.

The LFC startup parent uses `WaitForExit()` on the direct VRR child. It does not
use PowerShell's process-tree `-Wait` behavior, which would incorrectly keep the
one-shot task alive for as long as the resident helper remains active.

The 13 KB .NET Framework executable, complete C# source and rebuild script are
included in the archive. No Intel DLL, driver, CRU binary or EDID dump is bundled.

## Existing corrections retained

- Corrected ClawLab 30-120 Hz and official Intel/MSI 48-120 Hz remain the only
  public profiles.
- The Intel LFC x2 correction remains unchanged at version 2.0.3.
- Intel Graphics Software may be present or absent; its original startup state
  remains preserved through schema 4.
- Exact legacy 144 Hz hashes remain recovery-only. No 144 Hz installer or
  persistence path is present.
- Unknown CRU or third-party EDID overrides remain refused and untouched.
- If CRU was ever used on the same Windows installation, `reset-all.exe` from
  the current official CRU release must be run followed by a restart before
  ClawLab installation, even when CRU now appears inactive.
