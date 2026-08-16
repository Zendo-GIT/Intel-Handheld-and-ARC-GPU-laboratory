# System utilities

System utilities are independent of the game-specific fixes under `games/`.
They operate only on documented Windows or vendor interfaces and keep their own
recovery state.

| Utility | Purpose | Hardware scope |
|---|---|---|
| [MSI Claw Intel VRR Range Fix](msi-claw-8-intel-vrr-range-fix/README.md) | Default corrected 30-120 Hz range and official Intel/MSI 48-120 Hz | Claw 8 AI+ / 8 EX AI+ with the exact CSW0801 / PN8007QB1-2 EDID; Claw A1M / Claw 7 AI+ with the exact TMA2027 / TL070FVXS02-0 EDID |

Do not apply a display-specific EDID override to a different panel. The VRR
utility refuses unknown hardware and unknown existing overrides.
