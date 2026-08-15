# ClawLab Cursor Refresh Helper source

This helper uses standard Windows Raw Input and DWM composition only. It does not hook or inject into applications, inspect game processes, modify game files, or change the Intel LFC configuration.

While raw mouse input is arriving, the helper animates a nearly transparent 2x2 pixel WPF/DWM surface. It stops the animation 500 milliseconds after mouse input stops. At idle, the high-frequency timer is stopped and the process waits in the normal Windows message loop. Because only the mouse usage is registered, `WM_INPUT` is handled directly without allocating and parsing a native buffer for every packet.

The helper suppresses its animation when the system cursor is hidden. It does not inspect, inject into, or hook a game process. This also preserves compatibility with Windows Xbox Full Screen Experience, where the shell itself covers the complete monitor.

The source targets the inbox .NET Framework WPF runtime so that the public binary can be rebuilt with the Windows `csc.exe` compiler.
