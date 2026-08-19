# Compatibility

## Validated

| Component | Validated value |
|---|---|
| Device | MSI Claw 8 AI+ Polar Tempest |
| CPU | Intel Core Ultra 7 258V |
| GPU | Intel Arc 140V |
| Memory | 32 GB |
| Intel driver | 32.0.101.8974 WHQL |
| Windows | Windows 11, 150% desktop scaling |
| Game branch | Evrima |
| Game version | 0.21.784 |
| Steam build ID | 24664737 |
| Display | Internal 1920x1200 16:10 panel |
| API | Native DX12 |

## Installer policy

Release 1.0.0 refuses installation unless Steam reports build `24664737`.
Because this is a configuration profile rather than an executable patch, a
future build may remain technically compatible, but that must be tested and
documented before the public gate is changed.

The installer also requires the existing game configuration to report
1920x1200. This prevents the 16:10-specific UI scale from being applied blindly
to a 1920x1080 or unrelated external display profile.

## Unverified

- MSI Claw A1M and Claw 7 AI+ with 1920x1080 panels;
- MSI Claw 8 EX AI+;
- external displays and display mirroring;
- non-Intel GPUs;
- Windows desktop scaling other than 150 percent;
- later Evrima builds or the game's Legacy branch.

The 0.9 application scale specifically compensates the validated 1920x1200
16:10 UI crop. Applying it blindly to a 16:9 display could make the interface
unnecessarily small, which is why this release does not claim universal device
support.
