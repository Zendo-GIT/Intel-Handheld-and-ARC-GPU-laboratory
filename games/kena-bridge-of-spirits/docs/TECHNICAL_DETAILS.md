# Technical details

## Symptom

The affected water alternates between its normal dark-blue appearance and
bright cyan or white states. Frame-by-frame analysis showed that the water
changes as a broad coherent region while nearby terrain and foliage remain
stable, excluding a whole-frame exposure or display-brightness event.

## Asset identification

A deliberately magenta load probe established that the observed Forest Path
water uses:

```text
/Game/Mochi/MaterialLibrary/Water/UIWS/MI_WaterClean_Shallow
```

The instance inherits from `M_Water_UIWS`. Its parent material references the
procedural foam function `MF_RadialFoam` and the texture `T_Ocean_Foam`.

## Controlled result

Tests individually ruled out the material's static colors, custom highlight,
screen-space-reflection flag, specular intensity, metallic value, refraction
scale, animated wave normals, and several parent/pass substitutions as single
causes. The successful probe changed only:

```text
Foam_Opacity: 0.2 -> 0.0
```

The flashing disappeared on the reference Intel Arc system. The tester could
not distinguish a visible foam loss in ordinary gameplay.

The final release extends the same scalar correction to every cooked UIWS
surface instance in the tested build whose `Foam?` static switch is enabled.
The scope was derived from all 41 material instances in
`/Game/Mochi/MaterialLibrary/Water/UIWS`:

- 31 active-foam surface instances are patched;
- 8 instances already have `Foam? = false` and remain untouched;
- 2 opaque instances do not expose `Foam_Opacity` and remain untouched;
- waterfall/cascade materials use `M_Waterfall_*` outside the UIWS family and
  are not packaged.

All 31 reconstructed assets passed a JSON-to-binary-to-JSON semantic
round-trip. For each asset, the only material-data change is
`Foam_Opacity -> 0`; parent references, static switches, all other parameters,
imports, exports, and compiled permutation data are preserved.

The complete 31-asset PAK subsequently loaded the test save successfully. The
confirmed Forest Path water remained free of flashes and no obvious visual
regression was reported during that validation pass. This is not presented as
a complete location-by-location playthrough.

## Interpretation

The test establishes that evaluating or compositing the animated foam
contribution triggers the visible defect on the affected rendering path. It
does not prove whether the underlying Intel issue is a shader compiler bug, a
texture-sampling issue, a precision problem, or a later blend/composition bug.

Reporting the GPU as NVIDIA through a third-party DXGI wrapper also prevented
the symptom while the Intel GPU and driver remained active. That observation
supports a vendor-dependent path, but vendor spoofing is diagnostic evidence
only and is not part of this fix.

## PAK metadata

The validated release PAK uses the same container properties as the game:

```text
Mount point: ../../../
PAK version: V11
Compression: Zlib
Path-hash seed: 02E20257
Files: 62 (31 .uasset + 31 .uexp)
```

Release PAK SHA-256:

```text
6B8A19873CB65EA6CA33BA8A50CC90581A32F62A6A24C20E03A245A150CAD072
```
