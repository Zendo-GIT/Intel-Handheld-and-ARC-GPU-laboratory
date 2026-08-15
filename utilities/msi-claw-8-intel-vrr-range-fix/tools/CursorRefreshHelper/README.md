# ClawLab Cursor Refresh Helper source

This helper uses standard Windows Raw Input and DWM composition only. It does not hook or inject into applications, inspect game processes, modify game files, or change the Intel LFC configuration.

While raw mouse input is arriving, the helper animates a nearly transparent 2x2 pixel WPF/DWM surface. It keeps the surface active for 1.5 seconds after the latest mouse packet so short pauses do not cause unnecessary refresh transitions.

At idle, the animation stops, the 1 ms timer-resolution request is released, the helper trims its own working set, and the process waits in the normal Windows message loop. The first visible raw-mouse packet wakes it again. A controller/game profile naturally produces no usable mouse activity, so the same state machine enters deep idle regardless of whether the profile came from ClawTweaks, MSI Center M, another controller utility, or no profile manager at all. The helper does not inspect or control any of those applications.

Because only the mouse usage is registered, `WM_INPUT` is handled directly without allocating and parsing a native buffer for every packet.

The helper suppresses its animation when the system cursor is hidden. It does not inspect, inject into, or hook a game process. This also preserves compatibility with Windows Xbox Full Screen Experience, where the shell itself covers the complete monitor.

The source targets the inbox .NET Framework WPF runtime so that the public binary can be rebuilt with the Windows `csc.exe` compiler.
