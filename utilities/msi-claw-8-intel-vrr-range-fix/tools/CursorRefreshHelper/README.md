# ClawLab Cursor Refresh Engine source

The primary engine is implemented by
`ClawLabCursorRefreshNativeDxgi.cs`. It owns a native 2×2 Win32 window in the
extreme lower-right corner and presents through a D3D11/DXGI flip-model swap
chain. It clears each backbuffer to alternating opaque black and near-black
values before presenting, so DWM cannot coalesce the frames as unchanged.
Background Raw Input wakes the surface for visible mouse activity. The engine
presents during a bounded 30-second sign-in warm-up and for 1.5 seconds after
the latest mouse packet.

At idle, it stops presenting and blocks on kernel events. There is no polling
loop and no active high-resolution timer request. Controller/game use naturally
leaves the process in this deep-idle state because it produces no usable mouse
packets. The engine does not inspect ClawTweaks, MSI Center M, Steam or any
other profile manager.

The dedicated limited-user logon task has no delay and uses Task Scheduler
priority 2 (`AboveNormal`) instead of the background default 7 (`BelowNormal`).
The executable reasserts `AboveNormal` for alternate launch paths without
requesting administrator rights. Only that task starts the helper at logon.

Three named-event channels coordinate the resident process without restarting
it:

- Ready publishes a verified runtime state after initialization;
- Resync recreates the DXGI device/swap chain in place after final Intel/display
  startup verification;
- Shutdown requests cooperative exit before update or removal.

If native D3D11/DXGI initialization fails, the process automatically starts the
isolated compatibility implementation in
`ClawLabCursorRefreshHelperWpf.cs`. This fallback affects only the desktop
surface. It never restores or changes VRR, EDID or Intel LFC.

The engine uses standard Win32, Raw Input, DWM, D3D11 and DXGI APIs only. It
does not enumerate, hook, inject into or monitor game processes, and it does
not modify game files, anti-cheat components, display-driver files or panel
firmware. Hidden cursors suppress normal mouse-triggered presentation; Windows
Xbox Full Screen Experience and controller profiles therefore remain outside
the helper's active path.

`Build-CursorRefreshHelper.ps1` compiles both source files into the public
single executable with the inbox .NET Framework C# compiler. Its isolated test
arguments use test-specific mutexes, events and runtime-state files so the
native engine can be exercised without touching the installed helper or any
display profile.
