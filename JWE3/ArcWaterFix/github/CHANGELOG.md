# Changelog

All notable changes follow a simplified semantic-versioning format.

## 1.0.0 — 2026-08-13

- Initial public release.
- Forces JWE3 1.4.2.0 to use its classic VS/SM60 rendering path.
- Fix validated on Intel Arc 140V with graphics driver 32.0.101.8864.
- Adds automatic Steam-library detection.
- Verifies the executable version, expected bytes and SHA-256 before patching.
- Creates and verifies a byte-identical original backup.
- Includes one-click installation, status and uninstallation helpers.
- Uses no DLL injection or runtime memory modification.
