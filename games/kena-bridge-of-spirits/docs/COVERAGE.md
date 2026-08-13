# Surface-water coverage

Release 1.0.0 patches every material instance in Steam build `10345375` that:

1. resolves to the `M_Water_UIWS` or `M_River_UIWS` surface-water family;
2. has the `Foam?` static switch enabled and overridden; and
3. exposes a nonzero `Foam_Opacity` scalar.

The release changes only that scalar to zero.

## `M_Water_UIWS` surfaces (15)

- `MI_Pond_UIWS`
- `MI_RusuGorge_UIWS`
- `MI_RusuGorge_UIWS_LightFoam`
- `MI_RusuGorge_UIWS_Single`
- `MI_W2_BarnWater`
- `MI_W2ThresholdWater`
- `MI_Water_HuntsmanArena`
- `MI_Water_Ocean`
- `MI_WaterClean_Cave`
- `MI_WaterClean_Shallow`
- `MI_WaterClean_UIWS_Rain`
- `MI_WaterClean_UIWS1`
- `MI_WaterClean_VH_Cave`
- `MI_WaterDirty_Shallow`
- `MI_WaterDZ_UIWS`

## `M_River_UIWS` surfaces (16)

- `MI_River_Forge`
- `MI_River_ForgeFoam`
- `MI_River_Hideout`
- `MI_River_Hideout_Meditation`
- `MI_River_HideoutFast`
- `MI_River_HideoutFast2`
- `MI_River_Logs`
- `MI_River_UIWS`
- `MI_River_UIWS_shallow`
- `MI_River_UIWS_shallow_Foam`
- `MI_River_UIWS_shallow_Foam2`
- `MI_River_VH_Ent`
- `MI_River_VillageDocks`
- `MI_River_W2`
- `MI_RiverBG_W2`
- `MI_WaterBG_W2`

`MI_River_ForgeFoam` inherits through `MI_River_Forge`; its chain still
resolves to `M_River_UIWS` and is explicitly checked by the build tooling.

## Intentionally not patched

- Eight UIWS instances where `Foam?` is already false. The affected branch is
  not active, so changing their unused scalar would add no protection.
- Two opaque UIWS instances without `Foam_Opacity`.
- True waterfalls and cascades. They use separate `M_Waterfall_*` materials
  under `/Game/Mochi/Effects/Waterfall`, not either UIWS surface family.

The packaged PAK contains exactly 31 `.uasset` and 31 `.uexp` entries and no
waterfall or cascade path.
