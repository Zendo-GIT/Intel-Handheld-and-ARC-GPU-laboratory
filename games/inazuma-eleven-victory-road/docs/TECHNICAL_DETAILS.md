# Technical details

## Symptom

The reference system exhibited a visible hitch approximately every one to two seconds. FPS limiting, Steam offline mode, Steam Input changes, core-affinity experiments, PL1/PL2 increases, HAGS changes, fullscreen-optimization changes, VRR changes, and Intel V-Sync overrides did not remove the recurring pattern.

## ETW evidence

A Windows Performance Recorder and PresentMon trace ruled out sustained GPU saturation, storage reads, hard faults, DPC/ISR activity, EAC CPU load, and scheduler starvation as primary causes.

The main game thread's `WrAlertByThreadId` wait was readied by a secondary `nie.exe` thread at roughly sixteen times its normal rate in hitch windows. That secondary thread was itself readied by Steam's local `IPC:CSteamEngine` thread at roughly 15.6 times normal. Its sampled stack returned through `nie.exe+0x12EECA1`.

The enclosing game function begins at RVA `0x12EEC50`. It:

1. loads an EOS product-user identifier;
2. calls `EOS_ProductUserId_IsValid` at RVA `0x12EEC80`;
3. calls `SteamInternal_ContextInit` at RVA `0x12EEC92`;
4. invokes a Steam interface method;
5. combines the EOS and Steam results at RVA `0x12EECA1`.

## Exact patch

- target RVA: `0x12EEC70`
- target file offset: `0x12EE070`
- original bytes: `48 85 C0 74`
- patched bytes: `B0 01 EB 2F`

The original sequence begins the conditional validity-query path. The replacement sets the already-established validity result and jumps to RVA `0x12EECA3`, immediately after the EOS/Steam result combination. The remainder of the original state-machine logic still executes.

Only four bytes change. The full supported patched file SHA-256 is `4059F004915EC3462BB7E7348283A72C8738F9A3CCEB110C1475F2ADFBE2A3DF`.

## Measured result

In the reference 90-second run, the vanilla capture produced a 36.52 ms 99th percentile, an 83.40 ms maximum, and 44 detected hitch events. The patched capture produced a 19.36 ms 99th percentile, a 24.05 ms maximum, and no detected hitch event.

PresentMon itself caused small FPS drops in a later capture with a tight 60 FPS budget, so normal play was also evaluated without instrumentation. The recurring hitch remained absent.

## Limits

The patch does not eliminate initial shader, pipeline, or asset warm-up. It does not increase GPU throughput, and it cannot make a scene sustain an arbitrarily high FPS target. Its scope is the recurring synchronization hitch observed in the supported build.
