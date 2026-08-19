THE ISLE: EVRIMA MSI CLAW PERFORMANCE FIX 1.0.0
================================================

SUPPORTED BUILD

  Game version: 0.21.784
  Steam build:  24664737
  Validated on: MSI Claw 8 AI+ Polar Tempest / Intel Arc 140V
  Intel driver: 32.0.101.8974 WHQL

WHAT IT DOES

  - Corrects the validated blocky/corrupted-looking rendering profile.
  - Corrects the 1920x1200 high-DPI and 16:10 UI presentation.
  - Keeps 1920x1200 output for VRR while rendering 3D at 40 percent
    (approximately 768x480).
  - Sets every scalability group to Low/disabled except Medium view distance.
  - Applies shader-precache, streaming, TSR and conservative VRS settings.

IMPORTANT LIMIT

  The profile improves playability but does not eliminate every stutter.
  Evrima still performs blocking shader/PSO work during some map and scene
  transitions. No unsafe injection or anti-cheat bypass is included.

INSTALL

  1. Launch the game once, select 1920x1200, then close it completely.
  2. Run INSTALL_FIX.bat.
  3. Confirm that State is FIX_INSTALLED.
  4. Launch normally through Steam with Easy Anti-Cheat enabled.

CONFIGURATION LOCK

  Engine.ini and GameUserSettings.ini are made read-only because the game
  otherwise overwrites hidden values. Graphics and input changes will not
  persist while installed. Run UNINSTALL_FIX.bat before changing them.

UNINSTALL

  Close the game and run UNINSTALL_FIX.bat. The exact pre-install files and their
  attributes are restored from the verified ClawLab backup.

SAFETY

  This package modifies only the current user's INI configuration. It does not
  modify the game directory, EXE, DLL, PAK, EAC files, running process, memory,
  network access, Windows power plan, VRR profile or external optimization app.
  Compatible by design is not an official anti-cheat guarantee.

Full documentation:
https://github.com/Zendo-GIT/Intel-Handheld-and-ARC-GPU-laboratory/tree/master/games/the-isle-evrima
