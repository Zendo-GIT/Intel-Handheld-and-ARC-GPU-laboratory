# Compatibility

## Validated configuration

- MSI Claw 8 AI+ Polar Tempest
- Intel Core Ultra 7 258V
- Intel Arc 140V
- 32 GB RAM
- Intel Graphics driver 32.0.101.8864
- Windows 11
- Detroit: Become Human Steam build 12158144
- Native Vulkan renderer

## Executable compatibility

Only the exact vanilla and warning-fixed SHA-256 values listed in the project
README are supported. Game updates and other storefront executables are rejected.

## Other Intel GPUs

The launcher accepts only the documented executable build, but the graphics and
transition results have not yet been validated on other Arc devices. Reports
should include GPU, driver version, Steam build and executable SHA-256.

## Known limits

- Internal resolution scaling below 100% is intentionally overridden.
- In-game HDR is intentionally disabled by the optimized launcher.
- RTSS and overlays are left in their existing state.
- Brief asset-loading hitches can still occur. Transition Guard resets
  automatically only after a top-level completed chapter-progress file changes.
  It excludes checkpoints and never reacts automatically to an in-game hang.
- Steam file verification removes the executable patch and requires reinstalling
  the fix. When Steam integration is active, verification also overwrites the
  local wrapper; the status command detects this condition without replacing the
  Steam-provided executable.
- Steam integration restores the real game to its original executable name and
  full path during gameplay so Windows Game Bar and ClawTweaks can retain their
  existing game identity. Steam child-process tracking and profile recognition
  should still be confirmed on each supported storefront configuration; the
  classic launcher remains the fallback.
