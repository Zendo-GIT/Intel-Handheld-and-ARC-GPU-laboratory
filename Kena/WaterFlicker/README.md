# Kena: Bridge of Spirits — Intel Arc Water Flicker Investigation

## Status

The issue is reproduced and the affected water material is confirmed, but a
native DirectX 12 fix has **not** been validated yet. No experimental PAK in
this directory should be published as a fix.

The required end result is a local, reversible fix that works on Intel Arc with
native DirectX 12. OptiScaler, fakenvapi, GPU vendor spoofing, and a DirectX 11
fallback are not acceptable runtime dependencies.

## Reference system and build

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V / Intel Arc 140V
- 32 GB RAM
- Intel Graphics driver `32.0.101.8864`
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

These results exclude the tested static highlight, SSR flag, specular,
metallic, refraction-scale, and base-color parameters as individual causes.

## Current diagnostic

The active temporary probe switches only the confirmed material instance from
the translucent parent `M_Water_UIWS` to Kena's already cooked opaque parent
`M_Water_UIWS_Opaque`. Its purpose is to distinguish the translucent DirectX 12
pass from lighting and reflection behavior shared with opaque water.

Expected interpretation:

- flash removed: investigate Kena's translucent surface-lighting or composition
  pass;
- flash remains: investigate the common lighting/reflection stage or Intel
  driver execution beyond translucency.

The water is expected to look different during this diagnostic. The probe is
not a release candidate.

## PAK policy

Experimental PAK files are installed only at:

```text
Kena/Content/Paks/~Mods/
```

Every probe is reversible and contains only the minimum overridden assets. The
official PAK is never edited. Disabled probes are retained under the ignored
local analysis directory for audit and recovery.

## Anti-cheat and safety policy

Kena is being treated as a single-player diagnostic target. The preferred
solution is a data-only PAK override: no runtime injection, DLL proxy, overlay,
memory modification, or anti-cheat bypass. Any technique later considered for
another game must undergo a separate anti-cheat review; compatibility is never
assumed across titles.
