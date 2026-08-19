# The Isle: Evrima MSI Claw Performance Fix 1.0.0

This initial release packages the configuration profile validated on the MSI
Claw 8 AI+ Polar Tempest with Intel Arc 140V, Intel driver 32.0.101.8974 WHQL,
Evrima 0.21.784 and Steam build 24664737.

It corrects the reproduced blocky rendering behavior, repairs the 1920x1200
high-DPI/16:10 presentation, keeps native output for VRR and applies the most
playable validated Low/Medium profile at a 40 percent internal render scale.

The installer is configuration-only, requires no administrator access, creates
an exact original backup, locks the managed INI files against game rewrites and
restores them transactionally.

Small shader/PSO stalls remain during some map and scene transitions. This
release deliberately does not claim to eliminate them and does not include the
ineffective early D3D12 disk-cache experiment.

Run the game normally through Steam with Easy Anti-Cheat enabled. No EXE, DLL,
PAK, EAC file, process memory, network rule, Windows display profile or external
optimization application is modified.
