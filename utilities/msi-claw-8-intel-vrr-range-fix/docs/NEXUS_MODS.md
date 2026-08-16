# Optional Nexus Mods publication draft

- Title: **MSI Claw Intel VRR Range Fix**
- Version: **2.1.2**
- Category: **Utilities** or **Bug Fixes**
- Installation: **Manual only**

## Short description

Corrected 30-120 Hz and official Intel/MSI 48-120 Hz profiles with a shared
Intel LFC x2 correction, event-driven 120 Hz desktop cursor refresh, exact
panel/EDID checks, backup, windowless sign-in reapply and complete recovery.

## Required disclosure

The 30-120 profile is outside MSI's official 48 Hz floor and may flicker on an
individual panel. The package is restricted to exact pinned Claw 8/8 EX
`CSW0801 / PN8007QB1-2` and Claw A1M / Claw 7 AI+
`TMA2027 / TL070FVXS02-0` identities and EDIDs. Unknown CRU overrides are
refused. The shared A1M / Claw 7 AI+ EDID generation is verified, but real
driver/LFC and panel testing remains community-validation pending for both
models.

The former 48-144 and 30-144 installers were removed in 2.0.2. Version 2.1.2
also supports driver installations where Intel Graphics Software is absent.
The retired signatures remain only to restore an older ClawLab installation
safely to 120 Hz. Do not advertise 144 Hz as an available feature.

State this installation requirement prominently: if CRU was ever used on the
same Windows installation, no matter when or whether it now appears inactive,
the user must obtain the current official
[CRU release](https://www.monitortests.com/forum/Thread-Custom-Resolution-Utility-CRU),
run its included `reset-all.exe`, and restart before installing ClawLab.

The LFC correction uses a readable Windows D3DKMT request to Intel's
driver-private display interface. It saves and disables both Intel low/high-FPS
solutions, verifies the result and installs no continuous LFC watcher. It never
opens, patches or injects into a game process.

The event-driven Cursor Refresh Helper raises the Windows desktop to 120 Hz
during visible mouse movement by animating a nearly transparent 2x2 WPF/DWM
surface at the extreme lower-right corner. It stops at idle, is suppressed for
hidden cursors and supports Xbox Full Screen Experience. Its complete C# source
and rebuild script are included.

After 1.5 seconds without usable mouse input, the helper releases its 1 ms timer
request, trims its own working set and waits for the next raw-mouse packet. This
tool-independent deep idle covers controller/game profiles without monitoring
ClawTweaks, MSI Center M, another utility or any game process.

The archive contains no driver, Intel DLL, CRU binary, EDID dump, game file,
injector or anti-cheat component. Its only executable is the 13 KB rebuildable
.NET Framework Cursor Refresh Helper described above.

Version 2.1.2 additionally handles the exact zero-padded EDID representation
observed on Core Ultra 5 and Core Ultra 7 A1M units, migrates a verified LFC
backup across Intel-driver monitor-instance renames, separates core/helper
health, and includes a one-click JSON support export. Tell users never to
manually delete `%LOCALAPPDATA%\ClawLab`.
