# Anti-cheat policy

Anti-cheat compatibility is evaluated per game and per technique. File location, benign intent, or offline testing does not make a modified protected executable safe to use with anti-cheat.

## Public classifications

- **Compatible by design:** the fix does not alter, inject into, hook, or spoof the protected process and uses a mechanism permitted by the game.
- **Unprotected title:** no anti-cheat boundary applies to the tested game, but normal file-integrity and restoration rules still apply.
- **Offline only:** the method modifies a protected executable or otherwise cannot be represented as anti-cheat-compatible. It must not be used with EAC or online services.

## Repository rules

- Never label an executable patch EAC-compatible without explicit publisher or anti-cheat approval.
- Never distribute or link to a bypass, modified launcher, injector, trainer, or spoofing layer.
- Never restore game network access before the exact vanilla file has been verified.
- Keep diagnostic tools outside the protected process whenever investigating an online-compatible solution.
- Prefer a vendor report over a risky public workaround when an offline-only boundary cannot be enforced clearly.

The Inazuma release is classified **offline only**. Jurassic World Evolution 3
is treated as an unprotected single-player executable patch. Kena uses a
data-only PAK and does not modify an executable. The Isle profile is classified
**compatible by design** because it changes only per-user INI configuration and
does not modify, inject into, hook or spoof the protected process. This remains
a design assessment, not an official approval or anti-cheat guarantee.
