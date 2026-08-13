# MSI Claw Game Optimization Lab

This repository collects **game-specific** diagnostics and fixes for MSI Claw
handhelds. It is independent from Clawptimize and ClawTweaks.

## Laboratory principles

- Never require a global driver rollback to repair one game.
- Prefer local, reversible, and verifiable fixes.
- Do not inject code into game processes or bypass anti-cheat systems.
- Keep a bit-identical backup and verify restoration whenever a local fix must
  modify an official file.
- Separate genuine frame-time stutter from stutter caused by Alt+Tab.
- Treat third-party wrappers and GPU spoofing as diagnostic instruments, not as
  mandatory dependencies for public fixes.
- Publish only fixes that have been reproduced and validated on the reference
  hardware and exact game build.

## Cases

- [Jurassic World Evolution 3 — Intel Arc water corruption](JWE3/ArcWaterFix/README.md):
  fix validated; release 1.0.0 prepared for Nexus Mods and GitHub.
- [Kena: Bridge of Spirits — Intel Arc water flicker](Kena/WaterFlicker/README.md):
  minimal native DirectX 12 material fix validated on Intel Arc; release 1.0.0
  prepared for Nexus Mods and GitHub.

## Anti-cheat policy

The laboratory does not assume that a technique proven safe for one
single-player title is safe for another game. DLL injection, runtime hooks,
anti-cheat bypasses, and generic executable patches are not acceptable default
solutions. Every public fix must document its exact scope, installation method,
reversibility, and compatibility limitations.
