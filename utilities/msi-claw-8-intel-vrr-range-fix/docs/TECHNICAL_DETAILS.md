# Technical details

## Architecture

Version 2.3.0 separates nine responsibilities:

1. `MSI-Claw-VRR-Fix.ps1` validates hardware, generates exact EDID variants,
   selects Intel Arc Sync profiles, manages Windows refresh and owns the
   restore-before-switch state machine.
2. `MSI-Claw-Intel-LFC-Fix.ps1` saves and changes Intel low/high-FPS solution
   flags through a direct D3DKMT Intel private escape.
3. `ArcSync-Range-Policy.ps1` isolates normal range matching and the exact
   TMA2027 telemetry exception.
4. `Experimental-Overclock-VRR-Trial.ps1` schedules and executes the protected,
   user-started, visibly animated 30-second display-overclock trial.
5. `ClawLab-Cursor-Refresh-Helper.exe` raises normal desktop composition from
   the VRR floor only in response to visible raw-mouse movement.
6. `Scheduled-Task-Persistence.ps1` owns exact Task Scheduler COM readback,
   semantic validation, bounded registration and verified removal.
7. `ClawLab-VRR-Transaction.ps1` coordinates public mutable actions across one
   verified UAC identity and prevents split VRR/LFC completion. An already
   elevated launch inherits its verified token in the bound child rather than
   crossing a redundant second UAC boundary.
8. `ClawLab-Localization.ps1` and `locales/messages.json` provide the validated
   34-language public interface while internal state identifiers remain fixed.
   Runtime PowerShell is restricted to code-page-independent ASCII and the
   external translation catalog is decoded explicitly as UTF-8.
9. Windowless VBS launchers run one-shot sign-in operations without visible
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
| CSW0801 | 48–192 | `DC60F9E3CC7B33C4F094181C57E4AF271C1BFB4449AFDE2614B4EAC27C032752` |
| CSW0801 | 30–144 | `0B8E8A25325B4D9CAC2B6A03CF9B574688B1A6D2DEDF10401605C4898E0CAC05` |
| CSW0801 | 30–165 | `8EDC82A04D9E1FAD037CA4D794D53BD0D374C9554059B137E75C40D9F9C416A7` |
| CSW0801 | 30–180 | `0D1969CF0C7CFBA3CF9F077667C1427E202DB895DFA0A750FAF1323F57A88E4B` |
| CSW0801 | 30–192 | `949A7143DB4549FC7D0D36F9F2521A528C1C796DE8F3F1FA948E4B3DBF5ECED6` |
| TMA2027 | 30–120 | `7B5EE7D96BC91E83EBD2419B3A4F12771035D76303F77EEB0E356C996BFA4647` |
| TMA2027 | 48–144 | `AF1F6DEB144767F089522C37B89C1171DE59D06107B5F5073877A5693EBC9ADB` |
| TMA2027 | 48–165 | `89B0BDD6ACEB5A2320F235864314CC33CD67E4F3E4107E21573D506594E902D2` |
| TMA2027 | 48–180 | `0AA3BFD4DA2D6EB8D36BBA9F87CD476D453AD86651348CC3D17E8314BD3C898D` |
| TMA2027 | 48–192 | `4FA15135645E89BF10DA6B007921BA6702E03951C8FB9D2E2576F2837AD02BDE` |
| TMA2027 | 30–144 | `DFD9CBDDB7C0B8A711F026C43E3EB73165958F2E129857B97EB7EB008CB71B5E` |
| TMA2027 | 30–165 | `C0147C505E16907C62E66B56A3436870B591E1CB7B2FBA6CA410EEE3BEBDDC51` |
| TMA2027 | 30–180 | `CE853C0CB689CC6247E72E59C7965FEDCAE49479BCFD04EE7959FA3113A9D679` |
| TMA2027 | 30–192 | `6553A5DA6651D29D447F0E0D14EC80CA631B1178544DA60E1CC2D54C4FAFB4C9` |

The official 48–120 mode has no EDID override and uses the physical hash.

## A1M / Claw 7 AI+ range policy

Three sources of truth are intentionally separate:

- physical EDID range: 48–120 Hz;
- Intel Control Library monitor capability: observed as 24–120 Hz for the
  physical floor and 15–120 Hz after one managed 30–120 load on TMA2027;
- Intel active profile: selected independently as the exact managed range.

`ArcSync-Range-Policy.ps1` classifies 24–120 as
`INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR` for panel key
`CLAW_A1M_CLAW_7_AI_PLUS`. It classifies the 15 Hz variant as
`INTEL_CONTROL_LIB_HALF_MANAGED_FLOOR` only when its caller supplies an exact
expected 30 Hz managed minimum and a known ceiling. The current-version managed
record, active Intel profile and expected EDID must then independently agree;
without that binding, 15 Hz remains `UNSUPPORTED`. Expected profile minimum is
still restricted to 30 or 48, and expected maximum to 120, 144, 165, 180 or
192. The direct D3DKMT interface may continue to report physical 48–120 on this
panel; it is accepted only when the loaded EDID hash is the exact expected
managed variant. Thus a pending, foreign or mismatched EDID cannot be mistaken
for a ready profile.

The exact affected-driver first-install signature additionally requires active
profile ID 7 `CUSTOM 30–120`, 8333/8333 µs timings, one active display, native
1920×1080 at 120 Hz, no EDID override and a direct Intel 48–120 state with VRR
and both original solution flags enabled. That complete state can be preserved
as the restoration baseline only for `Install30`; no Intel profile setter is
called. Any variation, `Install48` or overclock request remains refused.

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
- do not install stable VRR, LFC or Cursor Helper persistence yet;
- stage exact runtime files and register a limited-interactive one-time task in
  the same elevated transaction as the pending EDID;
- roll back the pending EDID, managed state, task and copied trial artifacts if
  registration or verification fails;
- place the trial/main elevation payload in a non-reparse `%ProgramData%`
  directory protected by explicit SYSTEM/Administrators full-control and Users
  read/execute-only ACLs;
- bind every protected payload file to a versioned SHA-256 manifest and verify
  that manifest before the trial or elevated main script proceeds;
- construct and persist a fresh protected DACL separately for the parent and
  versioned runtime directories; reusing one .NET `DirectorySecurity` instance
  is forbidden because its modified-section flags are cleared after the first
  persistence operation;
- run the task itself with limited user privileges.

### Phase 2: post-restart trial

- task waits 10 seconds after sign-in for display initialization;
- exact trial context is revalidated;
- a visible ready dialog must be explicitly accepted before any overclock is
  applied;
- the validated internal panel must be the only active Windows display;
- requested Windows maximum and Intel `EXCELLENT` profile are attempted;
- a separately bounded normal-user process presents an animated 30-second test
  window, so the display is judged only after the desktop is visible;
- the exact Windows maximum and Intel range are read back again at the end of
  the observation;
- 120 Hz restoration is attempted in `finally` and its result is verified;
- confirmation appears only after verified safe restoration;
- Yes is written to the trial record before a separate visible UAC request and
  protected-runtime verification/final persistence can pass;
- No, timeout or error enters the exact saved-state recovery path. Automatic
  restart is permitted only after independent terminal proof succeeds; failed
  proof retains evidence and does not restart Windows automatically.

`ConfirmExperimentalTrial` refuses to persist without `UserConfirmed = true` in
the exact matching trial record. A successful path reapplies the requested
Windows maximum and verifies the exact VRR identity, applies and verifies LFC,
then validates the Cursor Refresh Helper and normal one-shot persistence before
removing the trial task and restarting. This same terminal order applies to all
eight confirmed experimental profiles and both stable profiles.

## Restore-before-switch state machine

`managed-mode.json` is authoritative only when its expected override and all
required artifacts agree. `Test-ClawLabProfileTransitionAllowed` implements:

```text
CLEAN/NONE                       -> requested mode allowed
CONSISTENT + current 2.3.0 + same stable mode -> guarded in-place repair
CONSISTENT + any experimental mode             -> Restore before a new trial
older managed FixVersion -> OLDER_VERSION_RESTORE_REQUIRED
anything else                    -> RESTORE_ORIGINAL_VRR required
```

The core transition policy can recognize an exact same experimental mode, but
the public 2.3.0 coordinator deliberately does not reuse a previously confirmed
trial. It requires Restore so that each overclock installation receives a new
warning, timed test and explicit confirmation. A stable repair retains its
pre-existing original backups; if joint VRR/LFC verification fails, ClawLab
marks recovery required instead of consuming those backups as compensation.
The public repair path additionally requires the exact current panel, physical
EDID, managed mode and both backups. It can rebuild missing managed task/payload
state or recover a narrowly recognized Intel standard-profile reset after a
driver update. Unknown `CUSTOM`, range or identity drift remains refused.

`Test-ClawLabFirstInstallProfileSafe` adds a separate baseline rule: a genuine
`CLEAN/NONE` first installation accepts Intel `RECOMMENDED` or `EXCELLENT`
directly. A clean unmanaged `CUSTOM` result enters a normalization transaction:
the main script tries Intel `RECOMMENDED`, obtains fresh ControlLib readback and,
if the driver silently retains `CUSTOM`, tries `EXCELLENT` and reads back again.
Only verified profile ID 1 or 2 can become the restoration baseline. Unknown
CUSTOM values are never adopted. Before the first setter, the exact snapshot and
panel/GPU/driver/target identity are atomically stored in
`normalization-compensation.json`. Success retires that journal only after the
standard baseline backup is verified. Failure or power loss restores the exact
snapshot; unresolved compensation blocks new installs until Recovery resumes it.

`Get-ClawLabFirstInstallBaselineDecision` contains one narrow exception to that
last rule for the complete TMA2027 OEM signature above. The saved backup records
the baseline policy. Factory reset and restore use pure policy decisions: an
exact matching TMA2027 baseline is preserved without a setter, while any drift
is rejected before display or managed-state mutation. Standard Intel baselines
retain the existing verified skip/write behavior.

No exception exists for stable-to-stable, stable-to-experimental, or one
experimental range to another. The pure test covers every pair for both panel
families.

## Intel LFC component 2.0.7

The direct Intel driver interface queries VRR support, range, enable state and
both solution flags. Before change, schema-4 backup records original values,
physical panel identity, active EDID, managed mode, driver and monitor-instance
history. Atomic file replacement uses a real same-directory backup path for
Windows PowerShell/.NET compatibility.

Both low- and high-FPS solutions are disabled and read back. Any error enters
verified saved-state recovery. The LFC task is the canonical sign-in
orchestrator: it holds the global display-transaction lock, invokes and waits for
the bounded VRR child, then takes the shared startup lock and applies LFC only
after exact mode/EDID/range verification. The direct VRR task delegates driver
writes whenever that exact orchestrator and payload verify, and remains a
fail-closed fallback if they do not. No resident watcher is installed.

All stable and experimental profiles receive the same LFC patch. TMA2027 uses
the exact-panel direct-range exception described above; CSW0801 still requires
the direct interface to report the selected range exactly.

## Startup ordering and external tools

ClawLab stores and verifies Intel Graphics Software's signed startup identity,
removes the original Run entry while managed, runs its own one-shot task, then
starts the trusted Intel application. Signed application updates are accepted
only after fresh Authenticode and SHA-256 verification.

If an Intel update rewrites the Run command while an older ClawLab backup still
exists, the differing entry is classified separately from an unknown entry. It
may be adopted for managed ordering or preserved during Recovery only after its
canonical executable path, Intel Authenticode signer and stable file identity
are freshly proven. Recovery therefore does not require a deleted legacy ZIP,
but it still refuses an unsigned, noncanonical or unrecognized command.

Task specifications retain the caller SID as their immutable ownership key.
Registration uses the NT account name translated from that SID because affected
Windows installations reject a raw SID in Task Scheduler XML `Principal/UserId`
with `ERROR_INVALID_PARAMETER`. Trigger and principal readback are translated
back to SID and must match before a task can be reused, started or removed.

A dedicated limited-user logon task executes the installed Cursor Refresh
Engine directly with no PowerShell, WMI or Intel Control Library dependency.
The trigger has zero delay and Task Scheduler priority 2 (`AboveNormal`), rather
than the priority-7 `BelowNormal` default. The executable reasserts the same
priority on itself but remains non-elevated. The process waits internally for
the interactive shell and DWM composition,
creates its native swap chain and begins a bounded 30-second warm-up. This early
desktop action does not satisfy the terminal transaction. The coordinated path
applies and verifies VRR, applies and verifies LFC, then sets a named auto-reset
resynchronization event. The existing process recreates its DXGI swap chain in
place and starts one final bounded warm-up. No process stop/start gap and no
additional profile write occurs.

Every other VRR/EDID writer must be disabled. The only supported exception is
[ClawTweaks 3.0 or later](https://github.com/enterTheVoidCode/ClawTweaks), whose
compatibility patch prevents it from overwriting ClawLab state. ClawTweaks is
not a dependency; absent installations skip the optional startup wait.

## Cursor helper implementation

The primary C#/.NET Framework engine creates a non-activating 2×2 native Win32
window at the extreme lower-right corner and a D3D11/DXGI flip-sequential swap
chain. Before every `Present(1, 0)`, it clears the current backbuffer to one of
two opaque black/near-black values through `ID3D11DeviceContext`, ensuring the
2×2 content really changes without becoming visibly distracting. It registers
generic-desktop mouse Raw Input with `RIDEV_INPUTSINK` and does not allocate a
native packet buffer per event. Presentations continue for
1.5 seconds after the latest visible mouse packet. Hidden cursors suppress the
tail, so controller/game use naturally reaches idle without inspecting a
profile manager or game process.

After the bounded sign-in warm-up or mouse tail expires, the engine performs no
presentation and calls `MsgWaitForMultipleObjectsEx` with an infinite timeout
over native messages plus named Shutdown/Resync events. This is deep idle: no
polling loop, timer-resolution request, periodic profile write or continuous
animation. Resync recreates only the swap chain and never changes VRR/EDID/LFC.

If native window, D3D11 or DXGI initialization throws, the same executable
records the reason and falls back to the earlier WPF/DWM implementation. This
fallback is confined to the optional desktop helper. It cannot restore or
change the managed display profile. Status distinguishes native flip,
compatibility presentation and WPF fallback states.

`UPDATE_CURSOR_REFRESH_ENGINE.bat` is a separate maintenance transaction. It
requires exact 2.3.0 managed-mode and Intel range consistency before elevation,
then updates only the executable/state record and dedicated task. Its result
explicitly reports that profile, LFC and EDID were unchanged.

## Recovery boundaries

Normal restore order is:

1. select safe 120 Hz for an overclock state;
2. run LFC `PrepareRestore`, which restores and verifies the saved flags while
   retaining their exact active backup;
3. restore and verify the saved Intel Arc Sync profile, exact known ClawLab EDID
   blocks, tasks, helper payloads and original Intel Graphics Software startup
   state;
4. run LFC `CommitRestore`, atomically converting the retained backup into
   `restore-committed.json`;
5. prove the complete VRR/LFC state independently;
6. run LFC `FinalizeRestore`, atomically retaining terminal
   `restore-finalized.json` provenance, then prove the terminal state again;
7. request a restart only after that proof succeeds so Windows reloads the
   physical EDID.

An interruption at any stage is resumable. Failed terminal proof does not
request an automatic restart, does not delete the transaction journal and does
not discard recovery evidence. The one-time trial task is neutralized when safe.
The separately labelled LFC Factory Defaults action follows an analogous
`factory-default-intent.json` to `factory-finalized.json` transaction, so a
crash can resume without guessing whether one or both flags were changed.

Arc Sync restoration is idempotent. The current snapshot is compared with every saved CUSTOM
field (profile ID, range and both transition timings), or with the saved
standard profile ID. If it already matches, the setter is skipped; fresh
readback must still match before cleanup. Transient Intel device/KMD/retry
results receive up to three fresh ControlLib attempts. Internal adapter,
display, support and telemetry-drift failures use distinct ClawLab errors and
are no longer reported as Intel `CTL_RESULT_ERROR_KMD_CALL`.

A separate missing-backup resolver is limited to an orphaned legacy startup
shell. It first attempts the normal fully-clean proof. Only if that fails does
the private `RecoverOrphanedDefaultState` action permit cleanup, and only after
fresh readback matches an exact pinned unmanaged factory signature: Claw 8
`RECOMMENDED 60-120` with 8333/8333 us timings, or the exact TMA2027 OEM
`CUSTOM 30-120` signature. It additionally proves native 120 Hz, Intel factory
LFC flags, no EDID/normalization/managed record/protected runtime, no other
tasks, and exact ownership of the one invalid VRR task. The action contains no
Arc Sync setter, display-mode setter or EDID registry write. It deletes the
owned task/payloads, rereads the factory profile, and then runs the ordinary
clean-state proof before the transaction may continue.

The health policy distinguishes an exact clean uninstall (no managed record,
backup, EDID, task, helper or LFC modification) from a broken installation and
reports `CLEAN_NOT_INSTALLED`. A clean unmanaged CUSTOM Arc Sync profile remains
visible but receives the automatic standard-profile normalization instruction,
not another Restore.

Before the final requested restart, status may legitimately expose a managed
`*_PENDING_RESTART` state, `READY_AT_NEXT_SIGN_IN` persistence and
`LfcFixActive: False`. Health policy treats these as transitional rather than
terminal success or failure. After restart, exact active-profile and LFC
readback, including `LfcFixActive: True`, is required.

Unknown third-party EDID blocks are never removed. Emergency EDID removal also
requires an exact known hash and exact validated registry path.

## Release verification

`tools/Build-Release.ps1`:

- parses every PowerShell source file;
- rebuilds and versions the cursor helper;
- verifies physical and custom EDID hashes for both panels;
- reproduces all 16 overclock variants;
- runs the complete two-panel profile-switch matrix: 20 same-mode recognitions
  and 180 cross-profile refusals across ten modes per panel;
- validates mandatory 10/15/30-second trial markers and rollback actions;
- rejects any 24 Hz install marker;
- validates ZIP layout and emits per-file and archive SHA-256 manifests.
