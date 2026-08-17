# Technical details

## Architecture

Version 2.2.0 separates six responsibilities:

1. `MSI-Claw-VRR-Fix.ps1` validates hardware, generates exact EDID variants,
   selects Intel Arc Sync profiles, manages Windows refresh and owns the
   restore-before-switch state machine.
2. `MSI-Claw-Intel-LFC-Fix.ps1` saves and changes Intel low/high-FPS solution
   flags through a direct D3DKMT Intel private escape.
3. `ArcSync-Range-Policy.ps1` isolates normal range matching and the exact
   TMA2027 telemetry exception.
4. `Experimental-Overclock-VRR-Trial.ps1` schedules and executes the protected
   one-time 15-second display-overclock trial.
5. `ClawLab-Cursor-Refresh-Helper.exe` raises normal desktop composition from
   the VRR floor only in response to visible raw-mouse movement.
6. Windowless VBS launchers run one-shot sign-in operations without visible
   PowerShell windows.

No component contains game-specific logic or accesses a game process.

## Exact hardware definitions

### CSW0801 / PN8007QB1-2

- Models: MSI Claw 8 AI+ / 8 EX AI+
- Mode: 1920×1200 at 120 Hz
- EDID length: 256 bytes
- Physical SHA-256:
  `E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0`
- Range fields: base descriptor bytes 95/96 and DisplayID bytes 142/143
- Experimental maximum timing: DisplayID 2.0 Type VII detailed timing in the
  validated empty slot at bytes 156–178

The experimental timing inherits the native 2080×1264 totals. Pixel clock is
`floor(2080 × 1264 × Hz / 1000) - 1 kHz`; the conservative one-kHz bias
preserves the previously field-tested 144 Hz timing byte for byte.

### TMA2027 / TL070FVXS02-0

- Models: MSI Claw A1M / Claw 7 AI+
- Mode: 1920×1080 at 120 Hz
- EDID length: 128 bytes
- Physical SHA-256:
  `3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1`
- Range descriptor bytes: 95/96
- Experimental maximum timing: native 1920×1080 timing cloned into the
  secondary DTD slot at bytes 72–89 with a recalculated pixel clock

The native 120 Hz preferred DTD remains intact as a recovery mode. The
horizontal maximum and pixel-clock maximum fields are updated consistently and
the base checksum is regenerated.

## Managed profiles and hashes

Every generated EDID and block hash is pinned in source and independently
reproduced by `tools/Test-Experimental-Overclock-Edids.ps1`.

| Panel | Range | Full EDID SHA-256 |
|---|---:|---|
| CSW0801 | 30–120 | `14CDDC390CF69367C4B6821A46728518200446A33F708A1A87CA673B68B66918` |
| CSW0801 | 48–144 | `4CFB165CE96119BA37A07176F9D346691D447E0A40E8697777E499E1556A744E` |
| CSW0801 | 48–165 | `FBB2CEFA8A0CC36CD5231D1070D4271165CAB9EA43A22271E3B2FD49D6914677` |
| CSW0801 | 48–180 | `279EA02FF5AEB3FA474235ECFCD3119AE7845A969C2F6BB7A63866CC3151EF62` |
| CSW0801 | 30–144 | `0B8E8A25325B4D9CAC2B6A03CF9B574688B1A6D2DEDF10401605C4898E0CAC05` |
| CSW0801 | 30–165 | `8EDC82A04D9E1FAD037CA4D794D53BD0D374C9554059B137E75C40D9F9C416A7` |
| CSW0801 | 30–180 | `0D1969CF0C7CFBA3CF9F077667C1427E202DB895DFA0A750FAF1323F57A88E4B` |
| TMA2027 | 30–120 | `7B5EE7D96BC91E83EBD2419B3A4F12771035D76303F77EEB0E356C996BFA4647` |
| TMA2027 | 48–144 | `AF1F6DEB144767F089522C37B89C1171DE59D06107B5F5073877A5693EBC9ADB` |
| TMA2027 | 48–165 | `89B0BDD6ACEB5A2320F235864314CC33CD67E4F3E4107E21573D506594E902D2` |
| TMA2027 | 48–180 | `0AA3BFD4DA2D6EB8D36BBA9F87CD476D453AD86651348CC3D17E8314BD3C898D` |
| TMA2027 | 30–144 | `DFD9CBDDB7C0B8A711F026C43E3EB73165958F2E129857B97EB7EB008CB71B5E` |
| TMA2027 | 30–165 | `C0147C505E16907C62E66B56A3436870B591E1CB7B2FBA6CA410EEE3BEBDDC51` |
| TMA2027 | 30–180 | `CE853C0CB689CC6247E72E59C7965FEDCAE49479BCFD04EE7959FA3113A9D679` |

The official 48–120 mode has no EDID override and uses the physical hash.

## A1M / Claw 7 AI+ range policy

Three sources of truth are intentionally separate:

- physical EDID range: 48–120 Hz;
- Intel Control Library monitor capability: observed as 24–120 Hz on TMA2027;
- Intel active profile: selected independently as the exact managed range.

`ArcSync-Range-Policy.ps1` accepts 24–120 only as
`INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR` for panel key
`CLAW_A1M_CLAW_7_AI_PLUS`. Expected profile minimum remains restricted to 30 or
48, and expected maximum to 120, 144, 165 or 180. The direct D3DKMT interface
may continue to report physical 48–120 on this panel; it is accepted only when
the loaded EDID hash is the exact expected managed variant. Thus a pending,
foreign or mismatched EDID cannot be mistaken for a ready profile.

## Intel Control Library path

The main script loads the signed system `ControlLib.dll` and calls:

- `ctlGetIntelArcSyncInfoForMonitor`;
- `ctlGetIntelArcSyncProfile`;
- `ctlSetIntelArcSyncProfile`.

Every setter is followed by a fresh query. The final profile must be
`EXCELLENT` and active minimum/maximum must equal the requested managed range.
Capability telemetry alone never proves installation.

## Windows display-mode path

The script enumerates exact resolution/refresh combinations through Win32
display APIs. Experimental confirmation is impossible unless the requested
1920×1080 or 1920×1200 maximum refresh appears as a Windows mode after the EDID
reload. `ChangeDisplaySettingsEx` writes the confirmed selection to the user
profile and a second query verifies the result.

Safe rollback explicitly selects 120 Hz before any experimental EDID is
removed.

## Guarded overclock transaction

An experimental install is a two-phase transaction.

### Phase 1: pending state

- verify clean state or exact same pending mode;
- save the original Intel profile;
- write only the exact generated EDID blocks;
- record panel key, physical/experimental hashes, range and classification;
- do not install normal persistence or LFC yet;
- stage exact runtime files and register a limited-interactive one-time task in
  the same elevated transaction as the pending EDID;
- roll back the pending EDID, managed state, task and copied trial artifacts if
  registration or verification fails;
- place the trial/main elevation payload in a non-reparse `%ProgramData%`
  directory protected by explicit SYSTEM/Administrators full-control and Users
  read/execute-only ACLs;
- bind every protected payload file to a versioned SHA-256 manifest and verify
  that manifest before the trial or elevated main script proceeds;
- run the task itself with limited user privileges.

### Phase 2: post-restart trial

- task waits 10 seconds after sign-in for display initialization;
- exact trial context is revalidated;
- the validated internal panel must be the only active Windows display;
- requested Windows maximum and Intel `EXCELLENT` profile are attempted;
- child execution is bounded to 15 seconds;
- 120 Hz restoration runs unconditionally in `finally`;
- confirmation appears only after safe restoration;
- Yes is written to the trial record before a separate visible UAC request and
  protected-runtime verification/final persistence can pass;
- No, timeout or error restores original state and restarts Windows.

`ConfirmExperimentalTrial` refuses to persist without `UserConfirmed = true` in
the exact matching trial record. A successful path reapplies the requested
Windows maximum, re-verifies Intel range, installs normal startup/cursor files,
applies LFC, removes the trial task and restarts.

## Restore-before-switch state machine

`managed-mode.json` is authoritative only when its expected override and all
required artifacts agree. `Test-ClawLabProfileTransitionAllowed` implements:

```text
CLEAN/NONE                       -> requested mode allowed
CONSISTENT + current 2.2.0 + same requested mode -> allowed as idempotent repair
older managed FixVersion -> OLDER_VERSION_RESTORE_REQUIRED
anything else                    -> RESTORE_ORIGINAL_VRR required
```

`Test-ClawLabFirstInstallProfileSafe` adds a separate baseline rule: a genuine
`CLEAN/NONE` first installation accepts only Intel `RECOMMENDED` or `EXCELLENT`.
It refuses an unmanaged `CUSTOM` profile before saving any original-state file.

No exception exists for stable-to-stable, stable-to-experimental, or one
experimental range to another. The pure test covers every pair for both panel
families.

## Intel LFC component 2.0.5

The direct Intel driver interface queries VRR support, range, enable state and
both solution flags. Before change, schema-4 backup records original values,
physical panel identity, active EDID, managed mode, driver and monitor-instance
history. Atomic file replacement uses a real same-directory backup path for
Windows PowerShell/.NET compatibility.

Both low- and high-FPS solutions are disabled and read back. Any error restores
saved values. The one-shot sign-in task first waits for the managed VRR reapply,
then verifies the exact mode/EDID/range policy before touching flags.

The standalone VRR task and the LFC parent can be triggered at nearly the same
time. A per-user named mutex serializes only their `ApplyStartup` phase, avoiding
duplicate profile/helper operations. The mutex is released when startup work
ends and is not a resident watcher.

All stable and experimental profiles receive the same LFC patch. TMA2027 uses
the exact-panel direct-range exception described above; CSW0801 still requires
the direct interface to report the selected range exactly.

## Startup ordering and external tools

ClawLab stores and verifies Intel Graphics Software's signed startup identity,
removes the original Run entry while managed, runs its own one-shot task, then
starts the trusted Intel application. Signed application updates are accepted
only after fresh Authenticode and SHA-256 verification.

The windowless task launcher starts the already installed non-elevated cursor
helper as its first best-effort action. It does not wait for PowerShell, WMI or
Intel Control Library initialization. The main verified startup path later
checks the helper hash/state and idempotently starts it again if necessary. This
separates desktop responsiveness from the slower driver-stabilization phase
without creating a resident VRR watcher.

Every other VRR/EDID writer must be disabled. The only supported exception is
[ClawTweaks 3.0 or later](https://github.com/enterTheVoidCode/ClawTweaks), whose
compatibility patch prevents it from overwriting ClawLab state. ClawTweaks is
not a dependency; absent installations skip the optional startup wait.

## Cursor helper implementation

The C#/.NET Framework WPF helper registers Raw Input with `RIDEV_INPUTSINK` and
uses no per-packet native allocation. While a visible mouse moves it animates a
nearly transparent 2×2 surface at the extreme lower-right corner. Its 8 ms
animation timer stays active for 1.5 seconds after the latest input to avoid
rapid floor/ceiling oscillation. Deep idle stops the timer, calls
`timeEndPeriod(1)`, trims only its process working set and waits in the Windows
message loop.

Hidden cursors suppress activation. Controller use therefore consumes no
continuous animation resources. The helper is non-elevated and does not inject
into or inspect elevated windows or games.

## Recovery boundaries

Normal restore order is:

1. select safe 120 Hz for an overclock state;
2. restore saved Intel LFC flags;
3. restore saved Intel Arc Sync profile;
4. remove only exact known ClawLab EDID blocks;
5. remove tasks/helpers/scripts;
6. restore the original Intel Graphics Software startup state;
7. require a restart to reload the physical EDID.

Step 3 is idempotent. The current snapshot is compared with every saved CUSTOM
field (profile ID, range and both transition timings), or with the saved
standard profile ID. If it already matches, the setter is skipped; fresh
readback must still match before cleanup. Transient Intel device/KMD/retry
results receive up to three fresh ControlLib attempts. Internal adapter,
display, support and telemetry-drift failures use distinct ClawLab errors and
are no longer reported as Intel `CTL_RESULT_ERROR_KMD_CALL`.

The health policy distinguishes an exact clean uninstall (no managed record,
backup, EDID, task, helper or LFC modification) from a broken installation and
reports `CLEAN_NOT_INSTALLED`. A clean unmanaged CUSTOM Arc Sync profile remains
visible but receives a standard-baseline instruction, not another Restore.

Unknown third-party EDID blocks are never removed. Emergency EDID removal also
requires an exact known hash and exact validated registry path.

## Release verification

`tools/Build-Release.ps1`:

- parses every PowerShell source file;
- rebuilds and versions the cursor helper;
- verifies physical and custom EDID hashes for both panels;
- reproduces all 12 overclock variants;
- runs the complete profile-switch matrix;
- validates mandatory 10/15/30-second trial markers and rollback actions;
- rejects any 24 Hz install marker;
- validates ZIP layout and emits per-file and archive SHA-256 manifests.
