# ClawLab temporary compositor boost test

This is a reversible diagnostic test for the low-refresh mouse-pointer behavior observed with a managed 30-120 Hz VRR range.

It does **not** change the Intel LFC fix, VRR profile, EDID, registry, driver files, or scheduled tasks. It calls the documented Windows `DCompositionBoostCompositorClock` API for 20 seconds and then releases the request. Closing the process also releases it.

## Test

1. Keep the ClawLab 30-120 Hz profile and LFC fix exactly as installed.
2. Open a refresh-rate monitor that can show the panel's current refresh rate.
3. Run `TEST_COMPOSITOR_BOOST_20_SECONDS.bat`.
4. During the blue 20-second period, first leave the desktop idle, then move only the mouse pointer.
5. Record the refresh rate during the boost and after it is released.

Do not run a game during this diagnostic test.

## Result template

```text
Device:
Intel driver:
Windows desktop mode:
ClawLab profile:

Before test, desktop idle:
Before test, mouse movement only:
During boost, desktop idle:
During boost, mouse movement only:
After boost release, mouse movement only:

Did the pointer feel smoother during boost? Yes / No
Any flicker, black screen, or artifact? Yes / No
```

This test is not the public mouse helper. Its only purpose is to verify whether the Windows compositor-clock path can wake the panel without changing the Intel LFC configuration.
