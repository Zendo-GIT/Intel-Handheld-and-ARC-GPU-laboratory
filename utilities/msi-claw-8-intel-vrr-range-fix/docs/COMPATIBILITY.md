# Compatibility

## Supported MSI Claw families

Version 2.3.0 supports these exact internal-panel families:

| Handheld family | Exact panel | Native mode | Physical EDID SHA-256 |
|---|---|---:|---|
| MSI Claw A1M / Claw 7 AI+ | `TMA2027 / TL070FVXS02-0` | 1920x1080 at 120 Hz | `3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1` |
| MSI Claw 8 AI+ / Claw 8 EX AI+ | `CSW0801 / PN8007QB1-2` | 1920x1200 at 120 Hz | `E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0` |

Compatibility is never inferred from a product name, screen size or advertised
refresh range. WMI monitor identity, canonical EDID length, full physical EDID
SHA-256, block checksums, Intel adapter count and active Intel Arc Sync output
must all match. An unknown revision is refused before modification.

## Profile availability

The package contains these profile choices:

- stable: 30–120 Hz and official 48–120 Hz;
- Stable Experimental: 48–144 Hz;
- Unstable Experimental: 48–165, 48–180, 48–192, 30–144, 30–165, 30–180
  and 30–192 Hz.

Availability in the package is not a validation claim. Every profile above
120 Hz is a display overclock outside MSI specifications and depends on the
individual panel silicon lottery.

On A1M / Claw 7 AI+ systems where the Intel driver exposes the exact verified
OEM `CUSTOM 30–120` baseline and rejects both standard profile setters, only
the stable 30–120 installer is permitted. The 48–120 and overclock installers
remain fail-closed on that path. They require a standard Intel baseline that
the collected driver state cannot establish safely.

### Real-hardware evidence

- Stable 30–120 and 48–120 behavior, Intel LFC correction and cursor helper:
  reference MSI Claw 8 AI+ Polar Tempest, Intel Core Ultra 7 258V, Arc 140V,
  Windows 11, Intel driver `32.0.101.8974` WHQL.
- Matching Claw 8 AI+ and 8 EX AI+ systems have community confirmations for the
  stable profiles.
- 48–144 Hz reached and remained stable on one MSI Claw 8 AI+ Polar Tempest
  Edition. It is therefore labelled **Stable Experimental**, not official.
- 48–165 Hz has successful Claw 8 AI+ reports, and 48–180 Hz reached the exact
  verified active state on one Claw 8 AI+ Polar Tempest Edition. Both remain
  **Unstable Experimental** because another nominally identical panel may fail.
  192 Hz and every 30 Hz-floor overclock remain unvalidated. All such outcomes
  are treated only as silicon-lottery possibilities.
- A1M Core Ultra 5 and Ultra 7 diagnostics and a Claw 7 AI+ report established
  the shared TMA2027 telemetry behavior. Their 2.3.0 policy is exact-EDID
  constrained; high-refresh experiments remain unvalidated on those models.

## A1M / Claw 7 AI+ Intel telemetry anomaly

The Tianma EDID declares a physical 48–120 Hz range. Collected systems can
nevertheless return `24–120 Hz` from Intel Control Library's monitor-capability
query. One field-tested 30–120 installation also returned `15–120 Hz` after the
managed profile loaded. In both cases, the active profile query independently
returns the real custom 30–120 or official 48–120 range. The direct Intel
D3DKMT interface continues to expose the physical 48–120 range.

Version 2.3.0 recognizes a halved telemetry floor only when all applicable
conditions are true:

- panel key is the exact A1M / Claw 7 AI+ Tianma definition;
- canonical EDID and selected ClawLab override have pinned hashes;
- the separately queried active Intel profile exactly matches the requested
  30/48 Hz minimum and 120/144/165/180/192 Hz maximum;
- the direct interface, expected EDID and managed record agree.
- the 15 Hz variant is bound to an already existing current-version ClawLab
  mode whose expected minimum is exactly 30 Hz; it is never accepted for a
  clean/unmanaged system or a 48 Hz profile.

The 15 and 24 Hz values are capability telemetry only. No 15/24 Hz EDID,
install action, profile or fallback exists in this package.

### Exact OEM CUSTOM baseline fallback

Collected A1M drivers can return this otherwise unusual combination:

- ControlLib monitor telemetry: `24–120 Hz` (`HALF_PHYSICAL_FLOOR`);
- active profile: ID 7 `CUSTOM 30–120`, 8333/8333 µs timings;
- direct Intel interface: physical 48–120 VRR with both original LFC solution
  flags enabled;
- `RECOMMENDED` reports success but reads back as CUSTOM;
- `EXCELLENT` is rejected by the kernel driver with `0x40000017`.

Version 2.3.0 can preserve that exact OEM state as the original baseline
without calling either rejected setter, but only for the 30–120 installer and
only when Windows is already at native **1920×1080, 120 Hz**. The exact panel
hash, zero-padding shape, timing values, telemetry class, direct interface,
single-display topology, LFC flags and absence of an EDID override are all
required. A nearby or partially matching custom state is refused.

Restoration and factory cleanup use the same exact decision. A matching OEM
state is preserved without a driver write; any drift is refused before display,
backup, EDID or task cleanup. This avoids repeating the setter that the A1M
driver is known to reject.

Windows sometimes exposes the 128-byte Tianma EDID with a second 128-byte block
of zeros. ClawLab accepts only that exact non-semantic padding shape when the
base block declares zero extensions, strips it, and then requires the canonical
physical SHA-256. Any non-zero tail is refused.

## Mandatory software ownership rule

Only one component may own VRR/EDID state. Disable or uninstall every other
tool that writes, restores, synchronizes or reapplies those settings.

The sole supported exception is
[ClawTweaks 3.0 or later](https://github.com/enterTheVoidCode/ClawTweaks), which
includes the ClawLab compatibility patch. ClawTweaks is optional and is not
required for the standalone VRR fix. Earlier ClawTweaks versions are not
compatible with this ownership rule.

If a conflicting tool reapplies a profile at startup, per game, during helper
restart or after a driver event, ClawLab can no longer guarantee the managed
range, backup identity or status result.

## Upgrade from an older ClawLab VRR release

Version 2.3.0 deliberately refuses any managed state recorded by 2.2.1 or an
older release, including the same nominal range. Use that older release's
`RECOVERY\RESTORE_ORIGINAL_VRR.bat`, restart Windows, then install 2.3.0 from a
newly extracted folder. Do not use Factory Reset for a normal upgrade.

## Mandatory CRU cleanup

If CRU was ever used on the current Windows installation, run `reset-all.exe`
from the current official
[CRU release](https://www.monitortests.com/forum/Thread-Custom-Resolution-Utility-CRU)
and restart Windows before ClawLab installation. This is mandatory even when
CRU was removed or no active override is visible. ClawLab does not bundle or
execute CRU and cannot prove historical CRU state.

If CRU has never been used on that Windows installation, no CRU reset is
needed; simply confirm that fact in the installer.

## External displays

Disconnect every external display during installation and guarded trials. The
validated internal panel must be the only active display whenever ClawLab
changes Windows refresh rate. The
current Intel profile API does not expose a stable user-facing output identity;
ClawLab therefore requires exactly one active Intel Arc Sync output.

## Unsupported similar devices

- AMD-powered MSI Claw models are excluded because this release uses Intel
  Control Library and an Intel D3DKMT private escape.
- Lenovo and other handhelds with similar published panel specifications are
  excluded without the exact pinned EDID and real diagnostics.
- Other Intel Arc desktops and laptops are not generically supported; an exact
  display definition and separate validation are required.

## Driver updates and known limits

- Run `CHECK_STATUS.bat` after every Intel driver update.
- A driver update can reset Intel profiles or recreate Intel Graphics Software
  startup. For a stable profile, reinstall only that exact same profile when
  status requests repair. The panel, physical EDID, managed mode and both
  original backups must still match; only a narrowly recognized standard-profile
  reset or missing managed task/payload is repairable, and failure preserves the
  backups. For an experimental profile, restore first, complete the restart and
  run a new guarded trial.
- If the managed VRR range and Intel LFC correction remain healthy and only
  `CursorRefreshHelper` or `DesktopHelperHealth` requires attention, run
  `UPDATE_CURSOR_REFRESH_ENGINE.bat`. This maintenance path preserves the
  current verified 2.3.0 profile—including 30–120—and does not require Restore,
  profile reinstallation, an overclock retest or a Windows restart.
- Before the final requested restart, `*_PENDING_RESTART`,
  `READY_AT_NEXT_SIGN_IN` and `LfcFixActive: False` can be normal transitional
  values. Final active-profile and LFC health is evaluated after that restart.
- Intel Graphics Software can cache or simplify range text. ClawLab status
  separates physical range, ControlLib telemetry and selected active profile.
- A custom EDID needs a restart before the driver loads it.
- 30 Hz is below MSI's official floor and may flicker on an individual panel.
- 144/165/180/192 Hz are display overclocks and can fail despite an identical EDID.
- Disabling Intel's low/high-FPS solutions removes traditional refresh
  multiplication below the selected profile floor.
- The tool cannot force a game to present through a VRR-capable swap chain.
- The native cursor engine affects normal non-elevated desktop composition
  only; an elevated always-on-top window can cover its 2×2 surface without
  affecting game VRR/LFC. WPF is used only if native DXGI initialization fails.
