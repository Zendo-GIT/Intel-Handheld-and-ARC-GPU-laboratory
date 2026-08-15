# ClawLab temporary software-composed cursor test

This reversible diagnostic checks whether the Intel VRR panel remains at its minimum refresh rate because Windows normally updates the mouse pointer through a separate hardware cursor path.

The test temporarily enables the shortest Windows pointer trail. This makes Windows redraw cursor movement through a composed path on many display stacks. The original setting is restored when the test ends or when `Ctrl+C` closes it.

It does not modify the Intel LFC fix, ClawLab VRR profile, EDID, registry, driver files, or scheduled tasks. The setting is session-only and is not saved to the Windows user profile.

The package also includes `TEST_REAL_DWM_ANIMATION_20_SECONDS.bat`. This second diagnostic creates a real animated 4x4 pixel DWM surface. Use it only if the software-composed cursor test does not raise the panel refresh rate. A tiny flashing square in the lower-right corner is expected and disappears automatically.

## Procedure

1. Keep the working ClawLab 30-120 Hz profile and LFC fix unchanged.
2. Open a refresh-rate monitor.
3. Run `TEST_SOFTWARE_COMPOSED_CURSOR_20_SECONDS.bat`.
4. During the blue 20-second period, move only the mouse pointer.
5. Report whether the panel reaches its maximum refresh rate and whether the pointer feels smoother.
6. Confirm that the short visible trail disappears after the test.

## Result template

```text
Before test, mouse movement only:
During test, mouse movement only:
After test, mouse movement only:

Did the pointer feel smoother? Yes / No
Did the temporary trail disappear after the test? Yes / No
Any flicker, black screen, or artifact? Yes / No
```
