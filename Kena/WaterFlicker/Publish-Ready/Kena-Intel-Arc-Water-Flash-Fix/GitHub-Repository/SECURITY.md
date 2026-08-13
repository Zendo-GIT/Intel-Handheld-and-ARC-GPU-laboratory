# Security policy

## Supported release

Security and packaging reports are accepted for the latest release only.

## Design boundary

The mod is a passive, data-only Unreal PAK. It must never install or execute a
DLL, executable, driver, service, scheduled task, hook, injector, proxy,
overlay, or memory patch. It must not bypass or interact with anti-cheat
software.

## Reporting

Use a private GitHub security advisory when the repository enables that
feature. Do not publish exploit details or suspicious replacement binaries in
a public issue. Compatibility problems that do not create a security risk can
use the normal issue templates.
