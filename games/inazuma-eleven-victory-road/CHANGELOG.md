# Changelog

## 1.0.1 — 2026-08-15

- Fixed a strict-mode uninstaller error when exactly one ClawLab firewall rule
  remained. Vanilla restoration already completed safely, but the false final
  error could prevent the success status from being displayed.
- Added repository and release-build validation for the single-rule cleanup.

## 1.0.0 — 2026-08-14

- Added the validated four-byte offline synchronization patch for Steam build `24370575`.
- Added strict full-file SHA-256, size, and target-byte validation.
- Added automatic Steam library discovery and optional manual game path.
- Added verified vanilla backup and exact reverse-patch recovery.
- Added mandatory inbound and outbound Windows Firewall isolation for all game-directory executables.
- Added automatic network restoration only after vanilla executable verification.
- Added status reporting, English documentation, Nexus packaging, and a reproducible release builder.
