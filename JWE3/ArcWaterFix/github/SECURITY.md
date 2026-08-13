# Security policy

## Supported release

Only the latest public release and its explicitly listed JWE3 executable hash
are supported.

## Reporting a vulnerability

After the public repository is created, report vulnerabilities privately using
GitHub's **Security advisories → Report a vulnerability** feature. Do not open a
public issue for a vulnerability that could cause unintended file modification,
data loss or unsafe targeting.

Include the fix version, PowerShell version, Windows version, exact command and
reproduction steps. Do not attach any proprietary game executable.

## Design boundaries

The project intentionally does not:

- inject DLLs;
- hook graphics APIs;
- patch a running process;
- download or execute remote code;
- bypass anti-cheat or DRM;
- accept unknown executable hashes;
- silently overwrite an unverifiable backup.

A change that removes one of these boundaries should be treated as a security
regression.
