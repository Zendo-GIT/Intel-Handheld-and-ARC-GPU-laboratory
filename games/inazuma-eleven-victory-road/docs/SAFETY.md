# Safety and offline boundary

## Easy Anti-Cheat

The patch changes `nie.exe`, so it must be treated as incompatible with Easy Anti-Cheat. A local firewall rule does not make a modified executable EAC-safe.

Never launch the patched file through EAC. Never use the patch for an online match, online competition, account progression, or any network service. No third party can promise that an unauthorized executable modification carries zero account risk.

This repository intentionally does not contain or link to an EAC bypass, modified launcher, trainer, injector, proxy DLL, or memory tool. Requests for bypass instructions are outside the project scope.

## Network isolation

Installation creates inbound and outbound Windows Firewall block rules for every `.exe` found below the resolved game directory, including `nie.exe`, the official bootstrapper, the EAC launcher, EAC setup, and EOS setup when present.

The isolation is intentionally limited to the game directory. Steam itself remains online. This prevents the patched game executables from opening direct connections, but it is not a substitute for the offline-only usage requirement.

The uninstaller removes the project's firewall rules only after it verifies that `nie.exe` is the exact supported vanilla file. If the file is unknown, it leaves the rules active and instructs the user to verify the game through Steam.

## Backups and restoration

Before installation, the original executable is copied to `%LOCALAPPDATA%\ClawLab\IEVR-Offline-Stutter-Fix` and checked against the full vanilla SHA-256. The backup is never included in a release archive.

Restoration uses the verified backup when available. Otherwise, it reverses the four exact bytes and checks that the entire restored executable matches the vanilla SHA-256. Unknown files are never overwritten.

## Updates

Steam can replace `nie.exe` during an update or file verification. Run `CHECK_STATUS.bat` after every game update. Do not attempt to force version 1.0.0 onto a new hash. A new build requires a new analysis and release.
