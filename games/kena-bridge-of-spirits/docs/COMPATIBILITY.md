# Compatibility

## Validated

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V / Intel Arc 140V
- Intel Graphics driver `32.0.101.8864`
- *Kena: Bridge of Spirits* Steam build `10345375`
- Native DirectX 12
- Flash elimination on Forest Path water using `MI_WaterClean_Shallow`
- Structural and semantic verification of all 31 packaged UIWS instances
- Successful save loading and confirmed-scene retest with the complete PAK

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
- Location-by-location visual results for the additional 30 packaged instances

The release covers every active-foam UIWS surface instance found in the tested
Steam build. This includes still water and horizontally animated river/ocean
surfaces. It intentionally excludes true waterfalls and cascades, which use a
different material family and did not exhibit the reported flash.

## Conflicts

Any mod overriding one of the 31 assets listed in [Coverage](COVERAGE.md) will
conflict with that part of the fix. All affected paths share this prefix:

```text
Kena/Content/Mochi/MaterialLibrary/Water/UIWS/
```

Remove all older `ClawLabWater...Probe` PAK files. Load order cannot merge two
versions of the same Unreal asset.
