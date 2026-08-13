# Contributing

Compatibility reports and narrowly scoped improvements are welcome.

## Test reports

Include:

- GPU and device model;
- graphics-driver version;
- game storefront and build number;
- DirectX mode;
- exact location and water material when known;
- whether the flash is removed;
- any visible loss of foam or other regression;
- a short recording or before/after screenshots when possible.

## Scope rules

- Keep the public fix native to DirectX 12.
- Do not add DLL injection, proxy DLLs, runtime hooks, memory modification, GPU
  spoofing, or anti-cheat bypasses.
- Do not broaden the material list without reproducing and validating the same
  one-parameter fix on real hardware.
- Do not commit game executables, official full PAKs, extracted maps, saves, or
  unrelated proprietary assets.
- Keep public documentation in English.

## Pull requests

Explain the exact asset and value changed, the evidence supporting it, and the
hardware/build combination used for validation. Run the release builder before
submitting packaging changes.
