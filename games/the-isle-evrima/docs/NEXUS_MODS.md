# Nexus Mods publication draft

## Suggested title

The Isle Evrima MSI Claw Performance and 16-10 Fix

## Suggested summary

Reversible configuration-only profile for The Isle: Evrima 0.21.784 on MSI
Claw 8 AI+ / Intel Arc 140V. Corrects the validated rendering corruption and
1920x1200 high-DPI UI crop while applying a performance-oriented Low/Medium
profile. Small engine-level shader stutters remain.

## Category and installation

Use a manual-download/configuration category. This is not a Vortex package.
Users extract the ZIP, close the game and run `INSTALL_FIX.bat`.

## Required warning

The release is validated only on Steam build 24664737 and refuses other builds.
Both INI files are made read-only, so users must run `UNINSTALL_FIX.bat` before
changing graphics or input bindings. The profile improves playability but does
not eliminate every shader/PSO transition stall.

## Anti-cheat disclosure

The package changes only per-user Unreal Engine INI files and launches the game
normally through Steam/EAC. It does not modify or include executables, DLLs,
PAKs, EAC files, injectors or bypasses. Compatible by design is not an official
endorsement or guarantee from the game or anti-cheat vendor.
