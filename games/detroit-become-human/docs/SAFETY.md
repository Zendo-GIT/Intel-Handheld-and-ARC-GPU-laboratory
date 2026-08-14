# Safety

## Local changes

Installation changes six bytes in the supported game executable after creating a
verified vanilla backup under:

```text
%LOCALAPPDATA%\ClawLab\Detroit-IntelArc-Stability-Fix
```

The optimized launcher may update only two documented graphics values in the
game's `GraphicOptions.JSON`: internal scale and HDR. Their original values are
saved and restored by the uninstaller.

Optional Steam integration renames the verified patched payload to
`DetroitBecomeHuman.ClawLab.real.exe` and places a locally compiled ClawLab
wrapper at Steam's original executable path. Both hashes are recorded. Removal
first verifies both files, restores the payload under its original name, and
keeps a recoverable copy of the retired wrapper under the state directory.

At launch, after the Steam-facing wrapper exits, the controller keeps a verified
recovery copy and temporarily places the real game at the exact original path.
It restores the wrapper after the game exits. An explicit handoff-state file
makes an interrupted exchange detectable and recoverable; no filename is
trusted without its expected SHA-256.

If Steam overwrites the wrapper, removal preserves Steam's current executable
and retires the older managed payload instead of overwriting a possible update.

## Temporary session state

During an optimized session the launcher:

- creates `steam_appid.txt` containing `1222140` so the controlled process is not
  replaced by a Steam-launched process;
- removes that file after exit or restores exact pre-existing contents.

Transition Guard reads file name, size and last-write metadata only from
`Default-*\\Game\\Chapters`. It does not read save contents and does not monitor
the separate checkpoint directory. A changed top-level chapter-progress file
arms one reset after a three-second transition delay, while a 60-second cooldown
prevents duplicate resets. Foreground hangs and process-I/O activity never arm
automatic recovery. The manual hotkey is read separately.

## What it never does

- no driver, BIOS, firmware, power-plan or registry modification;
- no firewall or network change;
- no shader-cache deletion or replacement;
- no cache prefetch or working-set manipulation;
- no DLL injection or Vulkan wrapper;
- no runtime memory patching;
- no RTSS, overlay, priority or Windows power-throttling change;
- no anti-cheat bypass.

If automatic restoration is interrupted, Steam Verify integrity can restore the
game executable.
