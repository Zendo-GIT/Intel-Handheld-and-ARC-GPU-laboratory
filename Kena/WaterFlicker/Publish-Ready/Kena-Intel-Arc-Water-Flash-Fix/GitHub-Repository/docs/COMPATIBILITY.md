# Compatibility

## Validated

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V / Intel Arc 140V
- Intel Graphics driver `32.0.101.8864`
- *Kena: Bridge of Spirits* Steam build `10345375`
- Native DirectX 12
- Forest Path water using `MI_WaterClean_Shallow`

## Not required

- DirectX 11
- Driver rollback
- OptiScaler
- fakenvapi
- NVIDIA GPU spoofing
- XeSS or frame-generation changes

## Not yet validated

- Other Intel Arc driver versions
- Other Intel, AMD, or NVIDIA GPUs
- Epic Games Store builds
- Future game builds
- Water surfaces that use another material instance

The override is intentionally narrow. A future release should add another
material only after reproducing the same defect and validating the same
one-parameter correction on that material.

## Conflicts

Any mod that overrides either of these paths will conflict with this fix:

```text
Kena/Content/Mochi/MaterialLibrary/Water/UIWS/MI_WaterClean_Shallow.uasset
Kena/Content/Mochi/MaterialLibrary/Water/UIWS/MI_WaterClean_Shallow.uexp
```

Remove all older `ClawLabWater...Probe` PAK files. Load order cannot merge two
versions of the same Unreal asset.
