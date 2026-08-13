# Compatibility

## Game versions

| Game executable | Status |
| --- | --- |
| Steam JWE3 1.4.2.0, supported SHA-256 | Supported |
| Any updated or modified JWE3.exe | Refused safely |
| Microsoft Store or other storefront builds | Not tested |

## GPUs and drivers

| Configuration | Status |
| --- | --- |
| Intel Arc 140V, driver 32.0.101.8864 | Water fix validated |
| Other Intel Arc GPUs on affected drivers | Plausible, not yet validated |
| AMD or NVIDIA GPUs | Not required and not tested |

## Other tools

XeSS, OptiScaler, fakenvapi and water-quality settings are not requirements for
this fix. They were ruled out independently during diagnosis. Compatibility
with third-party overlays or injectors is not claimed.

## Updates

Steam may restore or replace `JWE3.exe` during a game update or file-integrity
check. The installer will then report an unsupported or original state. Never
force an old offset onto a new executable; wait for a newly analysed release.
