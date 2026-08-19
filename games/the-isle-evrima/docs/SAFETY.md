# Safety and Easy Anti-Cheat boundary

## Classification

ClawLab classifies this release as **compatible by design** under the
laboratory's public anti-cheat policy. The classification describes the method;
it is not approval or a guarantee from the game developer or anti-cheat vendor.

## Files changed

Only these current-user files are edited:

```text
%LOCALAPPDATA%\TheIsle\Saved\Config\WindowsClient\Engine.ini
%LOCALAPPDATA%\TheIsle\Saved\Config\WindowsClient\GameUserSettings.ini
```

Exact pre-install copies and installation metadata are stored under:

```text
%LOCALAPPDATA%\ClawLab\The-Isle-Evrima-Claw-Fix
```

## Explicitly not changed

- `TheIsle.exe` and every other executable;
- DLLs, PAKs, shaders and proprietary game assets;
- Easy Anti-Cheat services, files or launch flow;
- process memory, API calls, overlays or render injection;
- firewall rules or game network access;
- Steam launch options and game-directory configuration;
- Windows display modes, VRR, registry or power plans;
- ClawTweaks, Clawptimize, MSI Center or other external applications.

## Persistence model

The two managed INI files are made read-only after successful verification.
This prevents the game from restoring hidden values such as Epic foliage on
exit. The original file attributes are recorded and restored exactly.

The installer uses a per-operation snapshot and atomic replacement. If a write
or post-install verification fails, the files are returned to their state at
the beginning of that operation.

## User responsibility

Run the game normally through Steam with Easy Anti-Cheat enabled. Do not combine
this package with injectors, modified binaries, bypasses or unrelated hidden
configuration mods and then attribute the resulting state to ClawLab.

If a game update, EAC message or official policy objects to the profile, close
the game, run the uninstaller and report the exact build and message.
