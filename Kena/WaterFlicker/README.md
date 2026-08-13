# Kena: Bridge of Spirits — Intel Arc Water Flicker Investigation

## Status

The issue is reproduced and a native DirectX 12 fix has been validated on the
reference Intel Arc system. Disabling the subtle animated foam contribution on
the affected Forest Path material eliminated the bright water flashes, while
the tester could not identify a visible loss of foam during normal play. The
release extends this same scalar correction to all 31 active-foam UIWS
surface-water instances in the tested build; true waterfalls/cascades remain
untouched.

The required end result is a local, reversible fix that works on Intel Arc with
native DirectX 12. OptiScaler, fakenvapi, GPU vendor spoofing, and a DirectX 11
fallback are not acceptable runtime dependencies.

## Reference system and build

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V / Intel Arc 140V
- 32 GB RAM
- Intel Graphics driver `32.0.101.8864`
- Unreal Engine `4.27.2-60700+DEV` (reported by the crash context)
- Steam App ID `1954200`, build `10345375`
- `Kena-Win64-Shipping.exe` SHA-256:
  `2AA94A7C678EAD73186D776B0D668BB993A90F2359AE76BC816887899D3E034B`

## Symptom

The water surface intermittently alternates between its normal dark-blue state
and a bright cyan or white state. The change affects broad regions of the water
surface while nearby terrain and foliage remain stable. This is different from
the missing or corrupted polygons repaired in Jurassic World Evolution 3.

Intel documents the same symptom as **Strong Light Flashes on Water Surface in
Kena: Bridge of Spirits** and lists it as a known Intel Arc graphics issue:

<https://www.intel.com/content/www/us/en/support/articles/000095373/graphics.html>

## Reproduction evidence

The supplied recording was analyzed frame by frame.

- Duration: approximately 9.43 seconds
- Resolution: 1920 × 1200
- Frame rate: 30 FPS
- Observed behavior: the water surface changes as a large coherent region; the
  rest of the scene does not exhibit a matching global exposure flash.

The analysis therefore excludes a whole-frame exposure or display-brightness
event.

## Confirmed asset and PAK loading

The affected Forest Path water references:

```text
/Game/Mochi/MaterialLibrary/Water/UIWS/MI_WaterClean_Shallow
```

`MI_WaterClean_Shallow` inherits from:

```text
/Game/Mochi/MaterialLibrary/Water/UIWS/M_Water_UIWS
```

A deliberately obvious load probe changed `FarColor`, `NearColor`, and
`ShallowColorTint` to magenta. The target water became magenta in game, proving
all of the following:

- the selected material instance is used by the observed water;
- the override path is correct;
- the PAK is mounted from `Kena/Content/Paks/~Mods`;
- the V11 format, `../../../` mount point, Zlib compression, and path-hash seed
  match the official PAK;
- earlier negative tests were genuine negative results, not packaging errors.

The water continued to flash while magenta. This is the most important result:
the static color parameters are not the source of the defect. The affected
material is being altered by a later rendering or lighting stage.

## Native rendering constraints

- DirectX 12 is mandatory (`bUseD3D12InGame=True`).
- XeSS and XeFG do not cause the defect.
- OptiScaler and fakenvapi are excluded as required dependencies.
- DirectX 11 is outside the project scope.
- No global driver rollback will be required for one game.
- The official 17.8 GB game PAK remains untouched.

Kena ships only the `PCD3D_SM5` shader path:

- `Engine/GlobalShaderCache-PCD3D_SM5.bin`
- `Kena/Content/ShaderArchive-Global-PCD3D_SM5.ushaderbytecode`
- `Kena/Content/ShaderArchive-Kena-PCD3D_SM5.ushaderbytecode`

No SM6/SM6.5 archive, mesh-shader path, or `DispatchMesh` use was found. The
JWE3 mesh-shader fallback therefore cannot apply to Kena.

## GPU vendor-spoofing observation

When OptiScaler reports the Intel GPU as an NVIDIA GPU through DXGI, the water
flash disappears even though the physical Intel GPU and Intel driver remain in
use. OptiScaler's current source shows that DXGI spoofing changes the adapter
description, Vendor ID, and Device ID returned to callers. This is strong
evidence that Unreal selects a different vendor-dependent path when it sees
Intel (`0x8086`) instead of NVIDIA (`0x10DE`).

This observation is diagnostic only. The final fix must work with the GPU
correctly identified as Intel and without OptiScaler.

OptiScaler reference:

<https://github.com/optiscaler/OptiScaler/blob/master/OptiScaler/spoofing/Dxgi_Spoofing.cpp>

## Rejected hypotheses

All tests below were limited to the confirmed water material or its UIWS parent
and were removed after testing.

| Test | Scope | Result |
| --- | --- | --- |
| Custom water highlight intensity set to zero | UIWS water instances | No change |
| Material screen-space reflections disabled | UIWS water masters | No change |
| `SpecularIntensity`: `0.2 → 0` | Confirmed shallow-water instance | No change |
| `Metallic`: `0.7 → 0` | Confirmed shallow-water instance | No change |
| `RefractionScale`: `1.5 → 0` | Confirmed shallow-water instance | No change |
| Static water colors replaced with magenta | Confirmed shallow-water instance | PAK loaded and material confirmed; flashing remained |
| Parent changed from translucent `M_Water_UIWS` to cooked opaque `M_Water_UIWS_Opaque` | Confirmed shallow-water instance | No change |
| `Wave_Intensity`, `Wave_Intensity_Secondary`, and `Ripples_Intensity` set to zero | Confirmed shallow-water instance | Water became visibly flatter; flashing remained unchanged |
| Parent changed to cooked `M_SimpleUnlitTranslucent` | Confirmed shallow-water instance | Water became nearly black but remained translucent/reflective; the flash became darker at the same frequency |
| `Foam_Opacity`: `0.2 → 0` | Confirmed shallow-water instance | **Flashing eliminated; no identifiable visual loss reported** |

These results exclude the tested static highlight, SSR flag, specular,
metallic, refraction-scale, base-color parameters, and the translucent pass as
individual causes. The visibly flatter surface also proves that the animated
normal overrides were active, while excluding their motion as the source of
the flash.

## Validated fix

The successful probe changes exactly one existing scalar parameter on the
confirmed material instance:

```text
Asset: /Game/Mochi/MaterialLibrary/Water/UIWS/MI_WaterClean_Shallow
Parameter: Foam_Opacity
Original value: 0.2
Fixed value: 0.0
```

The parent water material references `MF_RadialFoam` and `T_Ocean_Foam`. This
foam contribution is a subtle procedural overlay rather than necessarily
recognizable white shoreline foam. Disabling its opacity eliminated the bright
cyan/white flashes on the reference Intel Arc system. This establishes the
foam branch as the trigger, but it does not by itself identify the exact Intel
driver instruction or compiler defect inside that branch.

The fix preserves the water's color, transparency, normals, waves, refraction,
specular settings, metallic setting, blend mode, parent, and compiled shader
permutation. It requires no executable patch, GPU spoofing, DLL, hook, overlay,
or configuration change.

## Investigation history

An attempted opaque-unlit probe changed the parent to the cooked
`M_Emissive_Color` material, disabled the old static permutation, removed its
static parameters, and changed the explicit blend-mode override to opaque. The
title screen loaded, but entering the affected save triggered an Unreal
assertion while loading the confirmed material instance:

```text
MaterialInstanceConstant /Game/Mochi/MaterialLibrary/Water/UIWS/MI_WaterClean_Shallow:
Serial size mismatch: Got 14203, Expected 50657
```

The probe was removed immediately and `~Mods` was returned to an empty state.
This was an asset-serialization failure, not a graphics-driver crash. Changing
`bHasStaticPermutationResource` altered conditional deserialization without
recooking the material's binary resource data, so that method must not be
reused.

A conservative follow-up preserved the original parent, static parameters,
compiled permutation, export serial size (`51642` bytes), and complete
conditional structure. Its only semantic change was the existing
material-instance override from `BLEND_Translucent` to `BLEND_Opaque`. The save
still crashed while the material was loading, this time with an access
violation on a task-graph worker rather than a serial-size assertion. The probe
was removed and `~Mods` was returned to an empty state.

This confirms that changing the blend mode also requires a compatible cooked
shader permutation. Parent, blend-mode, and static-permutation mutations are
therefore outside the safe scope of UAssetGUI-only probes. Further work must
either use safe parameters already compiled into the original material or
identify the Intel/DX12 runtime path selected before the shader executes.

Configuration probes are currently **inconclusive**, not negative results. A
late-mounted PAK first changed
`r.SeparateTranslucencyAfterDistortion=1` to `0`, then a second probe used both
`r.DisableDistortion=1` and the unmistakable witness
`r.ScreenPercentage=50`. The rendered scene did not become lower-resolution,
which proves that `WindowsEngine.ini` inside `~Mods` was not consumed.

The same two variables were then placed temporarily in the user's actual Saved
`Engine.ini`, followed by a direct launch using `-ExecCmds`. Neither route
produced the 50 percent resolution witness. The original local configuration
was restored byte-for-byte after testing. Because the witness itself never
appeared, these attempts do not establish whether disabling distortion affects
the water flash. No configuration-only probe is currently installed.

The successful material override changes only the confirmed Forest Path
instance's `Foam_Opacity` from `0.2` to `0`. In-game validation eliminated the
flashing; no identifiable visual loss was reported.

The release PAK applies `Foam_Opacity -> 0` to every instance in the tested
build that resolves to `M_Water_UIWS` or `M_River_UIWS` and has `Foam?`
enabled: 15 water surfaces and 16 river surfaces. It contains no
`M_Waterfall_*` asset. Eight UIWS instances with foam already disabled and two
opaque instances without the parameter are left untouched. All 31 packaged
assets passed a semantic JSON-to-binary-to-JSON round-trip; the only material
data change per asset is the scalar value.

The complete PAK then loaded the test save successfully, kept the confirmed
Forest Path water free of flashes, and produced no obvious visual regression
during the validation pass. A complete location-by-location playthrough has
not been claimed.

## Release artifacts

- Public repository source: `github/`
- Reproducible release builder: `github/tools/Build-Release.ps1`
- Nexus Mods ZIP: `github/dist/Kena-Intel-Arc-Water-Flash-Fix-1.0.0.zip`
- Complete handoff bundle:
  `Publish-Ready/Kena-Intel-Arc-Water-Flash-Fix/`

Release ZIP SHA-256:

```text
C9134327672EE28F4C6C9766B86E699B552D4FC715BA67A36027E6674B9B1C33
```

The final ZIP is required to contain no nested archive and no executable or
DLL. Its embedded PAK must match the verified 31-asset release PAK.

## PAK policy

The validated PAK and temporary experimental PAK files are installed only at:

```text
Kena/Content/Paks/~Mods/
```

Every PAK is reversible and contains only the minimum overridden assets. The
official PAK is never edited. Disabled probes are retained under the ignored
local analysis directory for audit and recovery.

## Anti-cheat and safety policy

Kena is being treated as a single-player diagnostic target. The preferred
solution is a data-only PAK override: no runtime injection, DLL proxy, overlay,
memory modification, or anti-cheat bypass. Any technique later considered for
another game must undergo a separate anti-cheat review; compatibility is never
assumed across titles.
