# MSI Claw Intel VRR Range Fix 2.1.2

Version 2.1.2 is a compatibility and recovery hardening release for the public
30-120 and official 48-120 profiles.

## A1M and Claw 7 AI+ EDID compatibility

Diagnostics from both a Core Ultra 5 and a Core Ultra 7 MSI Claw A1M confirmed
that some current Intel/Windows configurations expose the exact 128-byte
`TMA2027 / TL070FVXS02-0` EDID followed by 128 zero bytes. Earlier releases
rejected that 256-byte registry buffer before checking its valid base block.

2.1.2 recognizes only this exact non-semantic padding shape when the base block
declares zero extensions. The canonical 128-byte block must still match the
pinned SHA-256 `3518AB...64CA1`; any non-zero tail, unknown hash, bad length or
different panel remains rejected. This shared entry covers Claw A1M and Claw 7
AI+ systems using that exact panel.

## Driver-update-safe LFC backup

Intel driver installation can recreate Windows' volatile monitor instance
name even though the physical panel and EDID are unchanged. LFC component
2.0.4 replaces that single volatile binding with schema 4 stable identity:

- exact manufacturer, product code and panel name;
- exact physical EDID SHA-256 and exact approved EDID-at-save;
- original managed profile and original Intel solution flags;
- last validated Windows instance plus an auditable migration count.

Existing schema 3 backups migrate atomically only after the exact panel and a
pinned EDID state verify. Older schema 1/2 backups without a pinned EDID remain
instance-bound and fail closed. A driver update therefore no longer creates a
restore/reinstall loop merely because Windows renamed the same monitor.

The final 2.1.2 package also corrects the Windows PowerShell atomic-replacement
call used by that migration. It supplies a real same-directory rollback file,
verifies the migrated backup, and removes the temporary rollback only after a
successful replacement. This fixes restoration of an existing schema 3 backup
without weakening its identity checks.

Only exact `30-120 Hz` and `48-120 Hz` states can receive the Intel LFC
correction. Any other driver range, including an erroneous `24-120 Hz`
readback, is refused before a backup, persistence task or Intel flag is changed.

## Clearer diagnosis

`CHECK_STATUS.bat` now reports game-facing VRR/LFC health separately from the
optional Windows desktop Cursor Refresh Helper. A healthy core correction is
no longer hidden behind a generic helper warning. `DIAGNOSTICS` also includes
`EXPORT_STATUS_REPORT.bat`, which writes one read-only JSON report to the
Desktop for support. Failed component queries are now recorded as failures in
that JSON instead of causing a misleading secondary property error.

Never manually delete `%LOCALAPPDATA%\ClawLab`. That directory contains the
original profile and Intel-flag backups required for a verified restore. Use
the normal `RECOVERY` tools first and the documented `EMERGENCY` tools only for
their named failure cases.

If the original LFC backup was already deleted while either Intel solution
flag remains off, 2.1.2 no longer reports a false successful restore. It emits
`ORIGINAL_LFC_BACKUP_MISSING_CANNOT_RESTORE`. The explicit emergency factory
fallback is available only when no backup remains and sets both Intel solution
flags on; it refuses to overwrite a valid saved original state.

The cursor helper behavior and direct Intel LFC flag combination are otherwise
unchanged. No game process, anti-cheat component, driver file or panel firmware
is accessed or modified.
