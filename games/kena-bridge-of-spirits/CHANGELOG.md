# Changelog

## 1.0.0 — 2026-08-13

- Disable only `Foam_Opacity` on all 31 active-foam UIWS surface-water
  instances in Steam build `10345375`.
- Eliminate the reproduced bright cyan/white water flashes on the reference
  Intel Arc 140V system.
- Leave true waterfall/cascade materials, opaque water, and already-disabled
  foam variants untouched.
- Preserve native DirectX 12 operation without wrappers or vendor spoofing.
