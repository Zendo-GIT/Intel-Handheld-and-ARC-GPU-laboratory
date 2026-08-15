# MSI Claw Intel VRR Range Fix 2.0.3

Release 2.0.3 fixes first installation on valid MSI Claw systems where the
Intel 8974 driver is installed but Intel Graphics Software itself and its
machine Run entry are both absent.

The previous fallback incorrectly constructed and authenticated a canonical
`IntelGraphicsSoftware.exe` command even when that optional application did not
exist. Installation then rolled back and left the user in a restore-required
loop. Schema 4 now saves genuine application absence without a command. The
windowless task applies and verifies VRR directly and skips the optional launch.
Normal restore preserves the original absence; if an external Intel startup
entry appears after installation, it is left untouched.

Elevated failures are now written to `last-error.txt` and echoed in the parent
console, preventing the useful error from disappearing with the UAC process.
LFC cleanup remains idempotent when legacy folders or files never existed.

Only these public profiles remain:

- `INSTALL_30_120_VRR.bat`: default ClawLab profile with the shared Intel LFC
  x2 correction;
- `INSTALL_48_120_VRR.bat`: official Intel/MSI range with the same correction.

No 144 Hz installation path is included. Exact legacy 48-144 and 30-144 hashes
remain internal recovery identifiers only.

Validated reference:

- MSI Claw 8 AI+ Polar Tempest;
- Intel Core Ultra 7 258V / Intel Arc 140V;
- `CSW0801 / PN8007QB1-2`;
- Windows 11;
- Intel graphics driver `32.0.101.8974` WHQL.
