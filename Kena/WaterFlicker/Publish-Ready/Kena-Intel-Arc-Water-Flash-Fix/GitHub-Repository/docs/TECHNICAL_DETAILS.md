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
not distinguish a visible foam loss in ordinary gameplay. The serialized
material retained the same export size and import/export counts, and the PAK
contains only the `.uasset` and `.uexp` for the confirmed instance.

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
Files: 2
```

Release PAK SHA-256:

```text
2273313BA261F3CCC7F9D80806C0D5A1991C6AF062700F26F28E1C389FE53398
```
