# Technical details

## Diagnosed problems

The investigation separated four behaviors that initially appeared related:

1. severe blocky or smeared scene rendering;
2. very low GPU-side scalability efficiency on the reference handheld;
3. a high-DPI/16:10 UI presentation failure;
4. recurring shader/PSO stalls during map and scene transitions.

The first three could be improved through user configuration. The fourth could
not be eliminated safely in the shipping build.

## High-DPI and 16:10 correction

With Windows at 150 percent scaling, the uncorrected game initialized Slate at
1280x800 while presenting a 1920x1200 D3D12 surface. Enabling Unreal's high-DPI
game mode restored a true 1920x1200 logical viewport:

```ini
[/Script/Engine.UserInterfaceSettings]
bAllowHighDPIInGameMode=True
```

The game's interface was then vertically fitted as a 16:9 canvas and cropped
horizontally on the 16:10 panel. A UI-only scale of `1080 / 1200 = 0.9`
compensated for the excess zoom without changing the 3D render scale:

```ini
ApplicationScale=0.900000
```

The corrected log reported a 1920x1200 window and work area.

## Rendering profile

The output remains 1920x1200 so the internal display and VRR path stay in their
native mode. `ScreenPercentage=40` renders the 3D scene at approximately
768x480 before temporal reconstruction.

Every scalability group is set to level 0 except view distance at level 1.
Physics foliage, physics grass, Lumen, motion blur and dynamic resolution are
disabled. Texture quality is Low; the earlier High-texture experiment was not
used in the final public profile.

The Engine.ini profile enables Unreal's existing PSO precache, shader-map
preload, low-level PSO retention, conservative variable-rate shading, reduced
TSR history bandwidth and amortized texture streaming paths. No renderer or
shader code is supplied by ClawLab.

## Remaining stalls

Game logs from the validated build recorded blocking shader preloads during the
Gateway transition. Individual waits included approximately 412, 470, 688,
745 and 747 milliseconds.

The same log reported:

```text
Not using pipeline state disk cache per r.D3D12.PSO.DiskCache=0
Not using driver-optimized pipeline state disk cache per r.D3D12.PSO.DriverOptimizedDiskCache=0
```

Those switches are evaluated before the per-user Saved Engine.ini is loaded.
An early `Engine/Config/ConsoleVariables.ini` experiment was performed locally,
but the shipping game ignored it and continued to report both values as zero.
The ineffective file was removed and is not part of this project.

Reducing resolution further cannot prevent a CPU-side blocking shader preload.
Removing the final transition stalls would likely require changes to the game
build, shader pipeline or protected launch path, which are outside the public
configuration-only and EAC-safe design boundary.

## Power observations

The game benefited from active CPU boost and performance cores. Increasing
package power beyond the useful operating point did not remove PSO stalls. The
public installer therefore does not create or edit a Windows power profile and
does not depend on a third-party tuning application.
