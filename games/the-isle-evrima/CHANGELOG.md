# Changelog

## 1.0.0 — 2026-08-19

- Added a configuration-only MSI Claw profile for The Isle: Evrima 0.21.784,
  Steam build 24664737.
- Corrected the validated blocky/corrupted Intel Arc rendering behavior.
- Enabled high-DPI game mode and applied a 0.9 UI scale to correct the game's
  cropped 16:10 presentation at 1920x1200 and 150 percent Windows scaling.
- Kept 1920x1200 output for VRR while selecting a 40 percent internal 3D scale,
  approximately 768x480.
- Set all scalability groups to Low or disabled except Medium view distance.
- Added the validated shader-precache, streaming, TSR and conservative VRS
  configuration.
- Added transactional backup, atomic writes, post-install verification,
  read-only persistence, exact restoration and a read-only status command.
- Documented the remaining engine-level shader/PSO stalls without claiming a
  complete stutter fix.
- Confirmed that the attempted early D3D12 disk-cache override is ignored by
  this shipping build and excluded it from the public package.
