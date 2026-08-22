using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace ClawLab.CursorRefresh
{
    internal static class CursorRefreshControl
    {
        internal const string ReadyEventName =
            "Local\\ClawLab.MSIClaw.CursorRefresh.Ready";
        internal const string ResyncEventName =
            "Local\\ClawLab.MSIClaw.CursorRefresh.Resync";
        internal const string ShutdownEventName =
            "Local\\ClawLab.MSIClaw.CursorRefresh.Shutdown";

        private static EventWaitHandle readyEvent;
        private static EventWaitHandle resyncEvent;
        private static EventWaitHandle shutdownEvent;
        private static string runtimeStateFileName = "runtime-state.txt";

        internal static void Initialize(bool testInstance)
        {
            string suffix = testInstance
                ? ".Test." + Process.GetCurrentProcess().Id
                : string.Empty;
            runtimeStateFileName = testInstance
                ? "runtime-test-" + Process.GetCurrentProcess().Id + ".txt"
                : "runtime-state.txt";
            bool created;
            readyEvent = new EventWaitHandle(
                false,
                EventResetMode.ManualReset,
                ReadyEventName + suffix,
                out created);
            resyncEvent = new EventWaitHandle(
                false,
                EventResetMode.AutoReset,
                ResyncEventName + suffix,
                out created);
            shutdownEvent = new EventWaitHandle(
                false,
                EventResetMode.ManualReset,
                ShutdownEventName + suffix,
                out created);
            readyEvent.Reset();
            resyncEvent.Reset();
            shutdownEvent.Reset();
        }

        internal static IntPtr[] NativeWaitHandles
        {
            get
            {
                return new[]
                {
                    shutdownEvent.SafeWaitHandle.DangerousGetHandle(),
                    resyncEvent.SafeWaitHandle.DangerousGetHandle()
                };
            }
        }

        internal static void SignalReady()
        {
            readyEvent.Set();
        }

        internal static bool IsShutdownRequested()
        {
            return shutdownEvent.WaitOne(0);
        }

        internal static bool ConsumeResyncRequest()
        {
            return resyncEvent.WaitOne(0);
        }

        internal static void WriteRuntimeState(
            string engine,
            string fallbackReason,
            long rawInputEvents,
            long presentations,
            long resynchronizations,
            long occludedPresents)
        {
            try
            {
                string root = Path.Combine(
                    Environment.GetFolderPath(
                        Environment.SpecialFolder.LocalApplicationData),
                    "ClawLab",
                    "Cursor-Refresh-Helper");
                Directory.CreateDirectory(root);
                string content =
                    "SchemaVersion=2" + Environment.NewLine +
                    "FixVersion=2.3.0" + Environment.NewLine +
                    "Utc=" + DateTime.UtcNow.ToString("O") + Environment.NewLine +
                    "Engine=" + engine + Environment.NewLine +
                    "ProcessId=" + Process.GetCurrentProcess().Id + Environment.NewLine +
                    "SessionId=" + Process.GetCurrentProcess().SessionId + Environment.NewLine +
                    "ProcessPriority=" + GetProcessPriority() + Environment.NewLine +
                    "FallbackReason=" + Sanitize(fallbackReason) + Environment.NewLine +
                    "RawInputEvents=" + rawInputEvents + Environment.NewLine +
                    "Presentations=" + presentations + Environment.NewLine +
                    "Resynchronizations=" + resynchronizations + Environment.NewLine +
                    "OccludedPresents=" + occludedPresents + Environment.NewLine +
                    "SurfaceContent=ALTERNATING_OPAQUE_NEAR_BLACK" +
                        Environment.NewLine +
                    "IdleBehavior=KERNEL_EVENT_WAIT_NO_TIMER_RESOLUTION" +
                        Environment.NewLine;
                string finalPath = Path.Combine(root, runtimeStateFileName);
                string temporaryPath = finalPath + ".tmp";
                File.WriteAllText(temporaryPath, content);
                if (File.Exists(finalPath))
                    File.Replace(temporaryPath, finalPath, null);
                else
                    File.Move(temporaryPath, finalPath);
            }
            catch
            {
                // Runtime diagnostics must never make the helper fail.
            }
        }

        private static string Sanitize(string value)
        {
            return (value ?? string.Empty)
                .Replace("\r", " ")
                .Replace("\n", " ");
        }

        private static string GetProcessPriority()
        {
            try
            {
                return Process.GetCurrentProcess().PriorityClass.ToString();
            }
            catch
            {
                return "UNAVAILABLE";
            }
        }

        internal static void Dispose()
        {
            if (readyEvent != null)
            {
                readyEvent.Reset();
                readyEvent.Dispose();
                readyEvent = null;
            }
            if (resyncEvent != null)
            {
                resyncEvent.Dispose();
                resyncEvent = null;
            }
            if (shutdownEvent != null)
            {
                shutdownEvent.Dispose();
                shutdownEvent = null;
            }
        }
    }

    internal sealed class NativeDxgiRefreshEngine : IDisposable
    {
        private const int WmDestroy = 0x0002;
        private const int WmDisplayChange = 0x007E;
        private const int WmInput = 0x00FF;
        private const int WmDwmCompositionChanged = 0x031E;
        private const int CursorShowing = 0x00000001;
        private const int RidevInputSink = 0x00000100;
        private const int SmCxScreen = 0;
        private const int SmCyScreen = 1;
        private const int SwShowNoActivate = 4;
        private const int WsPopup = unchecked((int)0x80000000);
        private const int WsExTransparent = 0x00000020;
        private const int WsExToolWindow = 0x00000080;
        private const int WsExNoActivate = 0x08000000;
        private const int WsExTopmost = 0x00000008;
        private const uint SwpNoActivate = 0x0010;
        private const uint SwpShowWindow = 0x0040;
        private const uint PmRemove = 0x0001;
        private const uint QsAllInput = 0x04FF;
        private const uint MwmoInputAvailable = 0x0004;
        private const uint WaitObject0 = 0;
        private const uint WaitFailed = 0xFFFFFFFF;
        private const uint WaitTimeout = 0x00000102;
        private const uint Infinite = 0xFFFFFFFF;
        private const int BlackBrush = 4;
        private const int DxgiStatusOccluded = 0x087A0001;

        private static readonly long TailTicks =
            Stopwatch.Frequency * 1500L / 1000L;
        private static readonly long StartupWarmupTicks =
            Stopwatch.Frequency * 30000L / 1000L;

        private static NativeDxgiRefreshEngine current;

        private readonly int testSeconds;
        private readonly bool visibleTest;
        private readonly bool continuousTest;
        private readonly NativeMethods.WindowProcedure windowProcedure;
        private readonly Stopwatch lifetime;
        private readonly string windowClassName;
        private readonly IntPtr[] controlHandles;
        private ushort windowClassAtom;
        private IntPtr window;
        private DxgiPresenter presenter;
        private long activityUntil;
        private bool stopRequested;
        private bool resyncRequested;
        private long rawInputEvents;
        private long presentations;
        private long resynchronizations;
        private long occludedPresents;

        private NativeDxgiRefreshEngine(
            int testSeconds,
            bool visibleTest,
            bool continuousTest)
        {
            this.testSeconds = testSeconds;
            this.visibleTest = visibleTest;
            this.continuousTest = continuousTest;
            windowProcedure = WindowProcedure;
            lifetime = Stopwatch.StartNew();
            windowClassName =
                "ClawLab.CursorRefresh.Native." +
                Process.GetCurrentProcess().Id;
            controlHandles = CursorRefreshControl.NativeWaitHandles;
        }

        internal static int Run(
            int testSeconds,
            bool visibleTest,
            bool continuousTest)
        {
            using (var engine = new NativeDxgiRefreshEngine(
                testSeconds,
                visibleTest,
                continuousTest))
            {
                return engine.RunLoop();
            }
        }

        private int RunLoop()
        {
            TryEnablePerMonitorDpiAwareness();
            CreateWindowAndPresenter();
            BeginWarmup();
            WriteRuntimeState();
            // Publish the complete runtime identity before signalling ready so
            // status checks can never observe a ready event with stale or
            // missing engine metadata.
            CursorRefreshControl.SignalReady();

            while (!stopRequested)
            {
                PumpWindowMessages();
                if (stopRequested || CursorRefreshControl.IsShutdownRequested())
                    break;
                if (testSeconds > 0 &&
                    lifetime.Elapsed >= TimeSpan.FromSeconds(testSeconds))
                    break;

                uint controlResult = NativeMethods.MsgWaitForMultipleObjectsEx(
                    (uint)controlHandles.Length,
                    controlHandles,
                    0,
                    QsAllInput,
                    MwmoInputAvailable);
                if (ProcessWaitResult(controlResult))
                    continue;

                if (resyncRequested)
                    RecreatePresenterAndWarmup();

                bool active = continuousTest ||
                    Stopwatch.GetTimestamp() <= activityUntil;
                if (active)
                {
                    int result = presenter.Present();
                    presentations++;
                    if (result == DxgiStatusOccluded)
                    {
                        occludedPresents++;
                        ReassertWindowPosition();
                        Thread.Sleep(1);
                    }
                    else if (result < 0)
                    {
                        RecreatePresenterAndWarmup();
                    }
                    continue;
                }

                uint timeout = Infinite;
                if (testSeconds > 0)
                {
                    double remaining =
                        testSeconds - lifetime.Elapsed.TotalSeconds;
                    timeout = remaining <= 0
                        ? 0U
                        : (uint)Math.Max(1, Math.Min(
                            Int32.MaxValue,
                            remaining * 1000.0));
                }
                controlResult = NativeMethods.MsgWaitForMultipleObjectsEx(
                    (uint)controlHandles.Length,
                    controlHandles,
                    timeout,
                    QsAllInput,
                    MwmoInputAvailable);
                ProcessWaitResult(controlResult);
            }

            WriteRuntimeState();
            return 0;
        }

        private bool ProcessWaitResult(uint result)
        {
            if (result == WaitFailed)
            {
                throw new InvalidOperationException(
                    "MsgWaitForMultipleObjectsEx failed with Win32 error " +
                    Marshal.GetLastWin32Error() + ".");
            }
            if (result == WaitObject0)
            {
                stopRequested = true;
                return true;
            }
            if (result == WaitObject0 + 1)
            {
                resyncRequested = true;
                return true;
            }
            if (result == WaitObject0 + (uint)controlHandles.Length)
            {
                PumpWindowMessages();
                return true;
            }
            // WAIT_TIMEOUT means no control event or message interrupted the
            // active presentation interval; the caller must continue with
            // the pending DXGI Present rather than skip it.
            return false;
        }

        private void CreateWindowAndPresenter()
        {
            if (current != null)
                throw new InvalidOperationException(
                    "A native refresh engine already owns the process window.");
            current = this;

            IntPtr instance = NativeMethods.GetModuleHandle(null);
            var windowClass = new NativeMethods.WindowClassEx
            {
                Size = (uint)Marshal.SizeOf(typeof(NativeMethods.WindowClassEx)),
                Instance = instance,
                WindowProcedure = Marshal.GetFunctionPointerForDelegate(
                    windowProcedure),
                Background = NativeMethods.GetStockObject(BlackBrush),
                ClassName = windowClassName
            };
            windowClassAtom = NativeMethods.RegisterClassEx(ref windowClass);
            if (windowClassAtom == 0)
                throw new InvalidOperationException(
                    "RegisterClassEx failed with Win32 error " +
                    Marshal.GetLastWin32Error() + ".");

            int size = visibleTest ? 16 : 2;
            int x = Math.Max(0, NativeMethods.GetSystemMetrics(SmCxScreen) - size);
            int y = Math.Max(0, NativeMethods.GetSystemMetrics(SmCyScreen) - size);
            window = NativeMethods.CreateWindowEx(
                WsExTopmost | WsExTransparent | WsExToolWindow | WsExNoActivate,
                windowClassName,
                "ClawLab Cursor Refresh Engine",
                WsPopup,
                x,
                y,
                size,
                size,
                IntPtr.Zero,
                IntPtr.Zero,
                instance,
                IntPtr.Zero);
            if (window == IntPtr.Zero)
                throw new InvalidOperationException(
                    "CreateWindowEx failed with Win32 error " +
                    Marshal.GetLastWin32Error() + ".");

            RegisterRawMouseInput(window);
            NativeMethods.ShowWindow(window, SwShowNoActivate);
            ReassertWindowPosition();
            presenter = new DxgiPresenter(window, size, size);
        }

        private void RecreatePresenterAndWarmup()
        {
            resyncRequested = false;
            resynchronizations++;
            ReassertWindowPosition();
            if (presenter != null)
                presenter.Dispose();
            int size = visibleTest ? 16 : 2;
            presenter = new DxgiPresenter(window, size, size);
            BeginWarmup();
            WriteRuntimeState();
        }

        private void BeginWarmup()
        {
            activityUntil = Stopwatch.GetTimestamp() + StartupWarmupTicks;
        }

        private void ActivateMouseTail()
        {
            long until = Stopwatch.GetTimestamp() + TailTicks;
            if (until > activityUntil)
                activityUntil = until;
        }

        private void ReassertWindowPosition()
        {
            int size = visibleTest ? 16 : 2;
            int x = Math.Max(0, NativeMethods.GetSystemMetrics(SmCxScreen) - size);
            int y = Math.Max(0, NativeMethods.GetSystemMetrics(SmCyScreen) - size);
            NativeMethods.SetWindowPos(
                window,
                new IntPtr(-1),
                x,
                y,
                size,
                size,
                SwpNoActivate | SwpShowWindow);
        }

        private void PumpWindowMessages()
        {
            NativeMethods.Message message;
            while (NativeMethods.PeekMessage(
                out message,
                IntPtr.Zero,
                0,
                0,
                PmRemove))
            {
                NativeMethods.TranslateMessage(ref message);
                NativeMethods.DispatchMessage(ref message);
            }
        }

        private IntPtr WindowProcedure(
            IntPtr handle,
            uint message,
            IntPtr wParam,
            IntPtr lParam)
        {
            if (message == WmInput)
            {
                rawInputEvents++;
                if (IsSystemCursorVisible())
                    ActivateMouseTail();
                else if (!continuousTest)
                    activityUntil = 0;
            }
            else if (message == WmDisplayChange ||
                     message == WmDwmCompositionChanged)
            {
                resyncRequested = true;
            }
            else if (message == WmDestroy)
            {
                stopRequested = true;
            }
            return NativeMethods.DefWindowProc(
                handle,
                message,
                wParam,
                lParam);
        }

        private static bool IsSystemCursorVisible()
        {
            var info = new NativeMethods.CursorInfo
            {
                Size = Marshal.SizeOf(typeof(NativeMethods.CursorInfo))
            };
            return NativeMethods.GetCursorInfo(ref info) &&
                (info.Flags & CursorShowing) != 0;
        }

        private static void RegisterRawMouseInput(IntPtr handle)
        {
            var device = new NativeMethods.RawInputDevice
            {
                UsagePage = 0x01,
                Usage = 0x02,
                Flags = RidevInputSink,
                Target = handle
            };
            if (!NativeMethods.RegisterRawInputDevices(
                new[] { device },
                1,
                (uint)Marshal.SizeOf(typeof(NativeMethods.RawInputDevice))))
            {
                throw new InvalidOperationException(
                    "RegisterRawInputDevices failed with Win32 error " +
                    Marshal.GetLastWin32Error() + ".");
            }
        }

        private static void TryEnablePerMonitorDpiAwareness()
        {
            try
            {
                NativeMethods.SetProcessDpiAwarenessContext(new IntPtr(-4));
            }
            catch (EntryPointNotFoundException)
            {
                // Windows 11 always exposes this API; retain a safe fallback.
            }
        }

        private void WriteRuntimeState()
        {
            CursorRefreshControl.WriteRuntimeState(
                presenter == null
                    ? "NATIVE_WIN32_DXGI_INITIALIZING"
                    : presenter.PresentationModel,
                string.Empty,
                rawInputEvents,
                presentations,
                resynchronizations,
                occludedPresents);
        }

        public void Dispose()
        {
            WriteRuntimeState();
            if (presenter != null)
            {
                presenter.Dispose();
                presenter = null;
            }
            if (window != IntPtr.Zero)
            {
                NativeMethods.DestroyWindow(window);
                window = IntPtr.Zero;
            }
            if (windowClassAtom != 0)
            {
                NativeMethods.UnregisterClass(
                    windowClassName,
                    NativeMethods.GetModuleHandle(null));
                windowClassAtom = 0;
            }
            if (ReferenceEquals(current, this))
                current = null;
        }

        private sealed class DxgiPresenter : IDisposable
        {
            private const uint D3d11SdkVersion = 7;
            private const uint D3d11CreateDeviceBgraSupport = 0x20;
            private const uint DxgiUsageRenderTargetOutput = 0x20;
            private const int D3dDriverTypeHardware = 1;
            private const int DxgiFormatB8G8R8A8Unorm = 87;
            private const int DxgiSwapEffectSequential = 1;
            private const int DxgiSwapEffectFlipSequential = 3;
            private const int PresentVtableIndex = 8;
            private const int GetBufferVtableIndex = 9;
            private const int CreateRenderTargetViewVtableIndex = 9;
            private const int ClearRenderTargetViewVtableIndex = 50;

            private IntPtr swapChain;
            private IntPtr device;
            private IntPtr context;
            private IntPtr renderTargetView;
            private IntPtr blackColor;
            private IntPtr nearBlackColor;
            private GCHandle blackColorPin;
            private GCHandle nearBlackColorPin;
            private NativeMethods.PresentDelegate present;
            private NativeMethods.ClearRenderTargetViewDelegate clearRenderTargetView;
            private bool alternateFrame;

            internal DxgiPresenter(IntPtr window, int width, int height)
            {
                int result = Create(
                    window,
                    width,
                    height,
                    DxgiSwapEffectFlipSequential);
                if (result < 0)
                {
                    ReleaseInterfaces();
                    result = Create(
                        window,
                        width,
                        height,
                        DxgiSwapEffectSequential);
                    if (result < 0)
                        Marshal.ThrowExceptionForHR(result);
                    PresentationModel = "NATIVE_WIN32_DXGI_SEQUENTIAL_FALLBACK";
                }
                else
                {
                    PresentationModel = "NATIVE_WIN32_DXGI_FLIP_MODEL";
                }

                try
                {
                    InitializeFrameContentPipeline();

                    // Submit two genuinely different initial frames before
                    // signaling readiness. DWM can no longer coalesce the tiny
                    // flip-model surface as unchanged content.
                    Present();
                    Present();
                }
                catch
                {
                    ReleaseInterfaces();
                    throw;
                }
            }

            internal string PresentationModel { get; private set; }

            private void InitializeFrameContentPipeline()
            {
                IntPtr swapChainVtable = Marshal.ReadIntPtr(swapChain);
                IntPtr presentFunction = Marshal.ReadIntPtr(
                    swapChainVtable,
                    IntPtr.Size * PresentVtableIndex);
                present = (NativeMethods.PresentDelegate)
                    Marshal.GetDelegateForFunctionPointer(
                        presentFunction,
                        typeof(NativeMethods.PresentDelegate));

                IntPtr getBufferFunction = Marshal.ReadIntPtr(
                    swapChainVtable,
                    IntPtr.Size * GetBufferVtableIndex);
                var getBuffer = (NativeMethods.GetBufferDelegate)
                    Marshal.GetDelegateForFunctionPointer(
                        getBufferFunction,
                        typeof(NativeMethods.GetBufferDelegate));

                IntPtr deviceVtable = Marshal.ReadIntPtr(device);
                IntPtr createViewFunction = Marshal.ReadIntPtr(
                    deviceVtable,
                    IntPtr.Size * CreateRenderTargetViewVtableIndex);
                var createRenderTargetView =
                    (NativeMethods.CreateRenderTargetViewDelegate)
                    Marshal.GetDelegateForFunctionPointer(
                        createViewFunction,
                        typeof(NativeMethods.CreateRenderTargetViewDelegate));

                IntPtr contextVtable = Marshal.ReadIntPtr(context);
                IntPtr clearFunction = Marshal.ReadIntPtr(
                    contextVtable,
                    IntPtr.Size * ClearRenderTargetViewVtableIndex);
                clearRenderTargetView =
                    (NativeMethods.ClearRenderTargetViewDelegate)
                    Marshal.GetDelegateForFunctionPointer(
                        clearFunction,
                        typeof(NativeMethods.ClearRenderTargetViewDelegate));

                IntPtr backBuffer = IntPtr.Zero;
                try
                {
                    Guid texture2D = NativeMethods.IidD3d11Texture2D;
                    int result = getBuffer(
                        swapChain,
                        0,
                        ref texture2D,
                        out backBuffer);
                    if (result < 0)
                        Marshal.ThrowExceptionForHR(result);
                    result = createRenderTargetView(
                        device,
                        backBuffer,
                        IntPtr.Zero,
                        out renderTargetView);
                    if (result < 0)
                        Marshal.ThrowExceptionForHR(result);
                }
                finally
                {
                    if (backBuffer != IntPtr.Zero)
                        Marshal.Release(backBuffer);
                }

                blackColorPin = GCHandle.Alloc(
                    new[] { 0.0f, 0.0f, 0.0f, 1.0f },
                    GCHandleType.Pinned);
                nearBlackColorPin = GCHandle.Alloc(
                    new[]
                    {
                        1.0f / 255.0f,
                        1.0f / 255.0f,
                        1.0f / 255.0f,
                        1.0f
                    },
                    GCHandleType.Pinned);
                blackColor = blackColorPin.AddrOfPinnedObject();
                nearBlackColor = nearBlackColorPin.AddrOfPinnedObject();
            }

            private int Create(
                IntPtr window,
                int width,
                int height,
                int swapEffect)
            {
                var description = new NativeMethods.DxgiSwapChainDescription
                {
                    BufferDescription = new NativeMethods.DxgiModeDescription
                    {
                        Width = (uint)width,
                        Height = (uint)height,
                        RefreshRate = new NativeMethods.DxgiRational
                        {
                            Numerator = 0,
                            Denominator = 1
                        },
                        Format = DxgiFormatB8G8R8A8Unorm,
                        ScanlineOrdering = 0,
                        Scaling = 0
                    },
                    SampleDescription = new NativeMethods.DxgiSampleDescription
                    {
                        Count = 1,
                        Quality = 0
                    },
                    BufferUsage = DxgiUsageRenderTargetOutput,
                    BufferCount = 2,
                    OutputWindow = window,
                    Windowed = true,
                    SwapEffect = swapEffect,
                    Flags = 0
                };
                uint featureLevel;
                return NativeMethods.D3D11CreateDeviceAndSwapChain(
                    IntPtr.Zero,
                    D3dDriverTypeHardware,
                    IntPtr.Zero,
                    D3d11CreateDeviceBgraSupport,
                    IntPtr.Zero,
                    0,
                    D3d11SdkVersion,
                    ref description,
                    out swapChain,
                    out device,
                    out featureLevel,
                    out context);
            }

            internal int Present()
            {
                alternateFrame = !alternateFrame;
                clearRenderTargetView(
                    context,
                    renderTargetView,
                    alternateFrame ? nearBlackColor : blackColor);
                return present(swapChain, 1, 0);
            }

            private void ReleaseInterfaces()
            {
                present = null;
                clearRenderTargetView = null;
                if (renderTargetView != IntPtr.Zero)
                {
                    Marshal.Release(renderTargetView);
                    renderTargetView = IntPtr.Zero;
                }
                if (blackColor != IntPtr.Zero)
                {
                    blackColor = IntPtr.Zero;
                }
                if (nearBlackColor != IntPtr.Zero)
                {
                    nearBlackColor = IntPtr.Zero;
                }
                if (blackColorPin.IsAllocated)
                    blackColorPin.Free();
                if (nearBlackColorPin.IsAllocated)
                    nearBlackColorPin.Free();
                if (context != IntPtr.Zero)
                {
                    Marshal.Release(context);
                    context = IntPtr.Zero;
                }
                if (device != IntPtr.Zero)
                {
                    Marshal.Release(device);
                    device = IntPtr.Zero;
                }
                if (swapChain != IntPtr.Zero)
                {
                    Marshal.Release(swapChain);
                    swapChain = IntPtr.Zero;
                }
            }

            public void Dispose()
            {
                ReleaseInterfaces();
            }
        }

        private static class NativeMethods
        {
            [UnmanagedFunctionPointer(CallingConvention.StdCall)]
            internal delegate IntPtr WindowProcedure(
                IntPtr window,
                uint message,
                IntPtr wParam,
                IntPtr lParam);

            [UnmanagedFunctionPointer(CallingConvention.StdCall)]
            internal delegate int PresentDelegate(
                IntPtr swapChain,
                uint syncInterval,
                uint flags);

            [UnmanagedFunctionPointer(CallingConvention.StdCall)]
            internal delegate int GetBufferDelegate(
                IntPtr swapChain,
                uint buffer,
                ref Guid interfaceId,
                out IntPtr surface);

            [UnmanagedFunctionPointer(CallingConvention.StdCall)]
            internal delegate int CreateRenderTargetViewDelegate(
                IntPtr device,
                IntPtr resource,
                IntPtr description,
                out IntPtr renderTargetView);

            [UnmanagedFunctionPointer(CallingConvention.StdCall)]
            internal delegate void ClearRenderTargetViewDelegate(
                IntPtr context,
                IntPtr renderTargetView,
                IntPtr colorRgba);

            internal static readonly Guid IidD3d11Texture2D =
                new Guid("6F15AAF2-D208-4E89-9AB4-489535D34F9C");

            [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
            internal struct WindowClassEx
            {
                internal uint Size;
                internal uint Style;
                internal IntPtr WindowProcedure;
                internal int ClassExtra;
                internal int WindowExtra;
                internal IntPtr Instance;
                internal IntPtr Icon;
                internal IntPtr Cursor;
                internal IntPtr Background;
                [MarshalAs(UnmanagedType.LPWStr)]
                internal string MenuName;
                [MarshalAs(UnmanagedType.LPWStr)]
                internal string ClassName;
                internal IntPtr SmallIcon;
            }

            [StructLayout(LayoutKind.Sequential)]
            internal struct Message
            {
                internal IntPtr Window;
                internal uint Value;
                internal IntPtr WParam;
                internal IntPtr LParam;
                internal uint Time;
                internal System.Drawing.Point Point;
                internal uint Private;
            }

            [StructLayout(LayoutKind.Sequential)]
            internal struct RawInputDevice
            {
                internal ushort UsagePage;
                internal ushort Usage;
                internal int Flags;
                internal IntPtr Target;
            }

            [StructLayout(LayoutKind.Sequential)]
            internal struct CursorInfo
            {
                internal int Size;
                internal int Flags;
                internal IntPtr Cursor;
                internal System.Drawing.Point ScreenPosition;
            }

            [StructLayout(LayoutKind.Sequential)]
            internal struct DxgiRational
            {
                internal uint Numerator;
                internal uint Denominator;
            }

            [StructLayout(LayoutKind.Sequential)]
            internal struct DxgiModeDescription
            {
                internal uint Width;
                internal uint Height;
                internal DxgiRational RefreshRate;
                internal int Format;
                internal int ScanlineOrdering;
                internal int Scaling;
            }

            [StructLayout(LayoutKind.Sequential)]
            internal struct DxgiSampleDescription
            {
                internal uint Count;
                internal uint Quality;
            }

            [StructLayout(LayoutKind.Sequential)]
            internal struct DxgiSwapChainDescription
            {
                internal DxgiModeDescription BufferDescription;
                internal DxgiSampleDescription SampleDescription;
                internal uint BufferUsage;
                internal uint BufferCount;
                internal IntPtr OutputWindow;
                [MarshalAs(UnmanagedType.Bool)]
                internal bool Windowed;
                internal int SwapEffect;
                internal uint Flags;
            }

            [DllImport("user32.dll", CharSet = CharSet.Unicode,
                SetLastError = true)]
            internal static extern ushort RegisterClassEx(
                ref WindowClassEx windowClass);

            [DllImport("user32.dll", CharSet = CharSet.Unicode,
                SetLastError = true)]
            internal static extern IntPtr CreateWindowEx(
                int extendedStyle,
                string className,
                string windowName,
                int style,
                int x,
                int y,
                int width,
                int height,
                IntPtr parent,
                IntPtr menu,
                IntPtr instance,
                IntPtr parameter);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool DestroyWindow(IntPtr window);

            [DllImport("user32.dll", CharSet = CharSet.Unicode)]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool UnregisterClass(
                string className,
                IntPtr instance);

            [DllImport("user32.dll")]
            internal static extern IntPtr DefWindowProc(
                IntPtr window,
                uint message,
                IntPtr wParam,
                IntPtr lParam);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool ShowWindow(
                IntPtr window,
                int command);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool SetWindowPos(
                IntPtr window,
                IntPtr insertAfter,
                int x,
                int y,
                int width,
                int height,
                uint flags);

            [DllImport("user32.dll")]
            internal static extern int GetSystemMetrics(int index);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool PeekMessage(
                out Message message,
                IntPtr window,
                uint minimum,
                uint maximum,
                uint remove);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool TranslateMessage(ref Message message);

            [DllImport("user32.dll")]
            internal static extern IntPtr DispatchMessage(ref Message message);

            [DllImport("user32.dll")]
            internal static extern uint MsgWaitForMultipleObjectsEx(
                uint count,
                [In] IntPtr[] handles,
                uint milliseconds,
                uint wakeMask,
                uint flags);

            [DllImport("user32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool RegisterRawInputDevices(
                [In] RawInputDevice[] devices,
                uint deviceCount,
                uint structureSize);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool GetCursorInfo(ref CursorInfo cursorInfo);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool SetProcessDpiAwarenessContext(
                IntPtr value);

            [DllImport("gdi32.dll")]
            internal static extern IntPtr GetStockObject(int objectIndex);

            [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
            internal static extern IntPtr GetModuleHandle(string moduleName);

            [DllImport("d3d11.dll", CallingConvention = CallingConvention.StdCall)]
            internal static extern int D3D11CreateDeviceAndSwapChain(
                IntPtr adapter,
                int driverType,
                IntPtr software,
                uint flags,
                IntPtr featureLevels,
                uint featureLevelCount,
                uint sdkVersion,
                ref DxgiSwapChainDescription swapChainDescription,
                out IntPtr swapChain,
                out IntPtr device,
                out uint featureLevel,
                out IntPtr immediateContext);
        }
    }
}
