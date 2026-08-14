# System utilities

System utilities are independent of the game-specific fixes under `games/`.
They operate only on documented Windows or vendor interfaces and keep their own
recovery state.

| Utility | Purpose | Validated hardware |
|---|---|---|
| [MSI Claw 8 AI+ / 8 EX AI+ VRR Range Fix](msi-claw-8-intel-vrr-range-fix/README.md) | Activates the shared panel's official 48-120 Hz Intel Arc Sync range and offers a separately marked experimental 30-120 Hz EDID override | MSI Claw 8 AI+ and Claw 8 EX AI+, only with the exact CSW0801 / PN8007QB1-2 EDID |

Do not apply a display-specific EDID override to a different panel. The VRR
utility refuses unknown hardware and unknown existing overrides.
