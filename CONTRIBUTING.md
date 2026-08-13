# Contributing

Contributions are welcome when they are evidence-based, narrowly scoped, reversible, and safe for the affected game's protection model.

## Before opening a pull request

1. Select exactly one game project unless the change affects shared repository infrastructure.
2. Reproduce the defect on a documented build and record the hardware, driver, settings, and scene.
3. Separate the suspected cause from confirmed evidence.
4. Use the smallest change that addresses the reproduced defect.
5. Document installation, uninstallation, vanilla recovery, known limits, and hash/build constraints.
6. Run `tools/Validate-Repository.ps1` and the relevant game release builder.

## Prohibited content

Do not commit or attach:

- proprietary game executables or executable backups;
- save files, private crash dumps, unreviewed ETL traces, authentication data, or personal paths;
- trainers, injectors, proxy DLLs, modified anti-cheat components, bypasses, bypass links, or replacement launchers;
- a patch for an unknown executable hash;
- claims of EAC or online safety without publisher approval.

## New executable builds

A new build requires the full vanilla SHA-256, exact size, target bytes, expected patched SHA-256, restoration proof, and real-hardware validation. Pattern-only matching is not sufficient for a public executable patch.

## AI assistance

Disclose material AI assistance in the contribution. Human contributors remain responsible for technical accuracy, licensing, testing, and publication-platform compliance.
