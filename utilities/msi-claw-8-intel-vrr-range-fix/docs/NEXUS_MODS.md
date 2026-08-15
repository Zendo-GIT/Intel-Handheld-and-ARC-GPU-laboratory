# Optional Nexus Mods publication draft

- Title: **MSI Claw 8 AI+ / 8 EX AI+ Intel VRR Range Fix**
- Version: **2.0.2**
- Category: **Utilities** or **Bug Fixes**
- Installation: **Manual only**

## Short description

Corrected 30-120 Hz and official Intel/MSI 48-120 Hz profiles with a shared
Intel LFC x2 correction, exact panel/EDID checks, backup, windowless sign-in
reapply and complete recovery.

## Required disclosure

The 30-120 profile is outside MSI's official 48 Hz floor and may flicker on an
individual panel. The package is restricted to the exact validated
`CSW0801 / PN8007QB1-2` identity and EDID. Unknown CRU overrides are refused.

The former 48-144 and 30-144 installers were removed in 2.0.2. Their signatures
remain only to restore an older ClawLab installation safely to 120 Hz. Do not
advertise 144 Hz as an available feature.

The LFC correction uses a readable Windows D3DKMT request to Intel's
driver-private display interface. It saves and disables both Intel low/high-FPS
solutions, verifies the result and installs no continuous watcher. It never
opens, patches or injects into a game process.

The archive contains no driver, Intel DLL, executable, CRU binary, EDID dump,
game file, injector or anti-cheat component.
