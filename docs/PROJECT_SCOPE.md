# Project scope

The Intel Handheld and Arc GPU Laboratory investigates game-specific rendering
defects, frame-time stalls, crashes, compatibility failures and narrowly scoped
system-display issues that remain after ordinary settings and supported driver
updates have been tested.

## In scope

- read-only ETW, PresentMon, logs, configuration, and binary-structure analysis;
- exact, reversible executable patches for unprotected titles;
- data-only mods and engine-native overrides;
- documented vendor display APIs and narrowly validated system display utilities;
- display-specific Windows EDID overrides with exact hardware checks, backups, explicit experimental labeling, and emergency recovery;
- offline-only research fixes for protected titles when their incompatibility with anti-cheat and online use is explicit and technically enforced where possible;
- documentation and vendor reports that enable an official upstream correction.

## Out of scope

- generic boost or debloat suites;
- modifying external optimization applications;
- cheats, trainers, competitive advantages, account manipulation, or network-service circumvention;
- anti-cheat bypass distribution or instructions;
- driver packages, copyrighted executable redistribution, or universal fixes without validation;
- generic or cross-panel EDID modifications without exact display validation.

The preferred final outcome is always an official game or driver correction. Local fixes exist to make affected hardware usable while preserving clear boundaries and recovery.
