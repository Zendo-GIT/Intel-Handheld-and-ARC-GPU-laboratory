using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Reflection;
using System.Threading;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

[assembly: AssemblyTitle("ClawLab Cursor Refresh Helper")]
[assembly: AssemblyDescription("Event-driven MSI Claw desktop cursor refresh helper")]
[assembly: AssemblyCompany("ClawLab")]
[assembly: AssemblyProduct("MSI Claw Intel VRR Range Fix")]
[assembly: AssemblyVersion("2.3.0.0")]
[assembly: AssemblyFileVersion("2.3.0.0")]

namespace ClawLab.CursorRefresh
{
    internal static class Program
    {
        private const string MutexName = "Local\\ClawLab.MSIClaw.CursorRefreshHelper";

        [STAThread]
        private static int Main(string[] args)
        {
            TryPromoteProcessPriority();
            int testSeconds = 0;
            bool visibleTest = false;
            bool continuousTest = false;
            foreach (string argument in args)
            {
                if (argument.StartsWith("--test-seconds=", StringComparison.OrdinalIgnoreCase))
                {
                    int.TryParse(argument.Substring("--test-seconds=".Length), out testSeconds);
                    testSeconds = Math.Max(5, Math.Min(300, testSeconds));
                }
                else if (string.Equals(argument, "--visible-test", StringComparison.OrdinalIgnoreCase))
                {
                    visibleTest = true;
                }
                else if (string.Equals(argument, "--continuous-test", StringComparison.OrdinalIgnoreCase))
                {
                    continuousTest = true;
                }
            }

            bool testInstance = testSeconds > 0;
            string mutexName = testInstance
                ? MutexName + ".Test." + Process.GetCurrentProcess().Id
                : MutexName;
            bool createdNew;
            using (var mutex = new Mutex(true, mutexName, out createdNew))
            {
                if (!createdNew)
                    return 2;

                CursorRefreshControl.Initialize(testInstance);
                try
                {
                    WaitForInteractiveDesktop();
                    try
                    {
                        int nativeResult = NativeDxgiRefreshEngine.Run(
                            testSeconds,
                            visibleTest,
                            continuousTest);
                        GC.KeepAlive(mutex);
                        return nativeResult;
                    }
                    catch (Exception nativeFailure)
                    {
                        CursorRefreshControl.WriteRuntimeState(
                            "WPF_FALLBACK",
                            nativeFailure.Message,
                            0,
                            0,
                            0,
                            0);
                        var application = new Application
                        {
                            ShutdownMode = ShutdownMode.OnMainWindowClose
                        };
                        var surface = new RefreshSurface(
                            testSeconds,
                            visibleTest,
                            continuousTest,
                            nativeFailure.Message);
                        application.Run(surface);
                        GC.KeepAlive(mutex);
                        return 0;
                    }
                }
                finally
                {
                    CursorRefreshControl.Dispose();
                }
            }
        }

        private static void TryPromoteProcessPriority()
        {
            try
            {
                // Task Scheduler priority 2 starts the helper as AboveNormal.
                // Reassert it in-process as a defense against alternate startup
                // paths while retaining a limited, non-administrator token.
                Process.GetCurrentProcess().PriorityClass =
                    ProcessPriorityClass.AboveNormal;
            }
            catch
            {
                // A priority-policy restriction must not prevent the helper
                // from starting; task-level priority remains the primary path.
            }
        }

        internal static void WaitForInteractiveDesktop()
        {
            // The sign-in launcher intentionally starts this process before
            // PowerShell/WMI. Do not create the DWM surface until the user's
            // shell and desktop composition are actually ready, otherwise an
            // early but still-running window can remain ineffective.
            var timeout = Stopwatch.StartNew();
            while (timeout.Elapsed < TimeSpan.FromSeconds(30))
            {
                bool compositionEnabled;
                int result = DwmIsCompositionEnabled(out compositionEnabled);
                if (GetShellWindow() != IntPtr.Zero && result >= 0 && compositionEnabled)
                    return;
                Thread.Sleep(100);
            }
        }

        [DllImport("user32.dll")]
        private static extern IntPtr GetShellWindow();

        [DllImport("dwmapi.dll")]
        private static extern int DwmIsCompositionEnabled(
            [MarshalAs(UnmanagedType.Bool)] out bool enabled);
    }

    internal sealed class RefreshSurface : Window
    {
        private const int WmInput = 0x00FF;
        private const int GwlExStyle = -20;
        private const long WsExTransparent = 0x00000020L;
        private const long WsExToolWindow = 0x00000080L;
        private const long WsExNoActivate = 0x08000000L;
        private const int RidevInputSink = 0x00000100;
        private const int CursorShowing = 0x00000001;

        private static readonly long TailTicks = Stopwatch.Frequency * 1500L / 1000L;
        private static readonly long StartupWarmupTicks = Stopwatch.Frequency * 30000L / 1000L;
        private static readonly Brush NearBlackBrush = CreateNearBlackBrush();

        private readonly DispatcherTimer animationTimer;
        private readonly DispatcherTimer testTimer;
        private readonly DispatcherTimer controlTimer;
        private readonly bool visibleTest;
        private readonly bool continuousTest;
        private readonly string nativeFailure;
        private long activityUntil;
        private bool toggle;
        private bool timerResolutionActive;
        private bool deepIdle;
        private bool startupWarmupActive;
        private long rawInputEvents;
        private long animationTicks;
        private long suppressedInputEvents;
        private long deepIdleEntries;
        private long timerResolutionAcquisitions;
        private long timerResolutionReleases;
        private long workingSetTrimAttempts;
        private HwndSource source;

        internal RefreshSurface(
            int testSeconds,
            bool visibleTest,
            bool continuousTest,
            string nativeFailure)
        {
            this.visibleTest = visibleTest;
            this.continuousTest = continuousTest;
            this.nativeFailure = nativeFailure ?? string.Empty;

            Title = "ClawLab Cursor Refresh Helper";
            Width = visibleTest ? 16 : 2;
            Height = visibleTest ? 16 : 2;
            Left = visibleTest
                ? Math.Max(0, SystemParameters.PrimaryScreenWidth - Width - 16)
                : Math.Max(0, SystemParameters.PrimaryScreenWidth - Width);
            Top = visibleTest
                ? Math.Max(0, SystemParameters.PrimaryScreenHeight - Height - 64)
                : Math.Max(0, SystemParameters.PrimaryScreenHeight - Height);
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false;
            ShowActivated = false;
            Topmost = true;
            AllowsTransparency = true;
            Background = Brushes.Black;
            Opacity = continuousTest ? (visibleTest ? 1.0 : 0.01) : 0;

            animationTimer = new DispatcherTimer(DispatcherPriority.Render)
            {
                Interval = TimeSpan.FromMilliseconds(8)
            };
            animationTimer.Tick += Animate;

            // This timer exists only in the compatibility fallback. The
            // primary Win32/DXGI engine waits directly on named kernel events
            // and therefore performs no control-channel polling.
            controlTimer = new DispatcherTimer(DispatcherPriority.Background)
            {
                Interval = TimeSpan.FromMilliseconds(100)
            };
            controlTimer.Tick += CheckControlEvents;

            if (testSeconds > 0)
            {
                testTimer = new DispatcherTimer(DispatcherPriority.Normal)
                {
                    Interval = TimeSpan.FromSeconds(testSeconds)
                };
                testTimer.Tick += delegate
                {
                    testTimer.Stop();
                    Close();
                };
            }

            SourceInitialized += OnSourceInitialized;
            Closed += OnClosed;
        }

        private void OnSourceInitialized(object sender, EventArgs e)
        {
            IntPtr handle = new WindowInteropHelper(this).Handle;
            long currentStyle = NativeMethods.GetWindowLongPtr(handle, GwlExStyle).ToInt64();
            long newStyle = currentStyle | WsExTransparent | WsExToolWindow | WsExNoActivate;
            NativeMethods.SetWindowLongPtr(handle, GwlExStyle, new IntPtr(newStyle));

            source = HwndSource.FromHwnd(handle);
            if (source == null)
                throw new InvalidOperationException("The WPF HWND source could not be created.");
            source.AddHook(WindowProcedure);
            RegisterForRawMouseInput(handle);
            CursorRefreshControl.WriteRuntimeState(
                "WPF_FALLBACK",
                nativeFailure,
                0,
                0,
                0,
                0);
            CursorRefreshControl.SignalReady();
            controlTimer.Start();

            if (continuousTest)
            {
                ExitDeepIdle();
                activityUntil = long.MaxValue;
                animationTimer.Start();
            }
            else
            {
                // Keep the tiny DWM surface active while the Windows shell,
                // Steam and Intel Graphics Software finish their asynchronous
                // sign-in initialization. A named in-process resynchronization
                // after final Arc Sync verification starts the same bounded
                // warm-up against the settled display pipeline without a gap.
                BeginStartupWarmup();
            }
            if (testTimer != null)
                testTimer.Start();
        }

        private void CheckControlEvents(object sender, EventArgs e)
        {
            if (CursorRefreshControl.IsShutdownRequested())
            {
                Close();
                return;
            }
            if (CursorRefreshControl.ConsumeResyncRequest())
                BeginStartupWarmup();
        }

        private IntPtr WindowProcedure(
            IntPtr window,
            int message,
            IntPtr wParam,
            IntPtr lParam,
            ref bool handled)
        {
            // Only the generic-desktop mouse usage is registered below, so
            // every WM_INPUT delivered to this HWND is already mouse input.
            // Avoid per-packet native buffer allocation on high-polling-rate
            // devices.
            if (message == WmInput)
            {
                rawInputEvents++;
                if (!IsSystemCursorVisible())
                {
                    suppressedInputEvents++;
                    if (!startupWarmupActive && !continuousTest)
                        EnterDeepIdle();
                    return IntPtr.Zero;
                }

                long mouseTailUntil = Stopwatch.GetTimestamp() + TailTicks;
                if (mouseTailUntil > activityUntil)
                    activityUntil = mouseTailUntil;
                ExitDeepIdle();
                if (!animationTimer.IsEnabled)
                {
                    animationTimer.Start();
                    Animate(this, EventArgs.Empty);
                }
            }
            return IntPtr.Zero;
        }

        private static bool IsSystemCursorVisible()
        {
            var cursor = new CursorInfo
            {
                Size = Marshal.SizeOf(typeof(CursorInfo))
            };
            return NativeMethods.GetCursorInfo(ref cursor) &&
                (cursor.Flags & CursorShowing) != 0;
        }

        private void Animate(object sender, EventArgs e)
        {
            if (!continuousTest && Stopwatch.GetTimestamp() > activityUntil)
            {
                startupWarmupActive = false;
                EnterDeepIdle();
                return;
            }

            toggle = !toggle;
            animationTicks++;
            if (visibleTest)
                Background = toggle ? Brushes.Magenta : Brushes.Cyan;
            else
                Background = toggle
                    ? NearBlackBrush
                    : Brushes.Black;
        }

        private void ExitDeepIdle()
        {
            deepIdle = false;
            Opacity = visibleTest ? 1.0 : 0.01;
            if (!timerResolutionActive)
            {
                timerResolutionActive = NativeMethods.timeBeginPeriod(1) == 0;
                if (timerResolutionActive)
                    timerResolutionAcquisitions++;
            }
        }

        private void BeginStartupWarmup()
        {
            startupWarmupActive = true;
            activityUntil = Stopwatch.GetTimestamp() + StartupWarmupTicks;
            ExitDeepIdle();
            if (!animationTimer.IsEnabled)
            {
                animationTimer.Start();
                Animate(this, EventArgs.Empty);
            }
        }

        private void EnterDeepIdle()
        {
            startupWarmupActive = false;
            animationTimer.Stop();
            activityUntil = 0;
            toggle = false;
            Background = Brushes.Black;
            Opacity = 0;

            if (timerResolutionActive)
            {
                NativeMethods.timeEndPeriod(1);
                timerResolutionActive = false;
                timerResolutionReleases++;
            }

            if (!deepIdle)
            {
                deepIdle = true;
                deepIdleEntries++;
                workingSetTrimAttempts++;
                NativeMethods.SetProcessWorkingSetSize(
                    NativeMethods.GetCurrentProcess(),
                    new IntPtr(-1),
                    new IntPtr(-1));
            }
        }

        private void OnClosed(object sender, EventArgs e)
        {
            animationTimer.Stop();
            controlTimer.Stop();
            if (testTimer != null)
                testTimer.Stop();
            if (source != null)
                source.RemoveHook(WindowProcedure);
            if (timerResolutionActive)
            {
                NativeMethods.timeEndPeriod(1);
                timerResolutionActive = false;
                timerResolutionReleases++;
            }
            if (testTimer != null || visibleTest || continuousTest)
                WriteTestLog();
        }

        private void RegisterForRawMouseInput(IntPtr handle)
        {
            var device = new RawInputDevice
            {
                UsagePage = 0x01,
                Usage = 0x02,
                Flags = RidevInputSink,
                Target = handle
            };
            if (!NativeMethods.RegisterRawInputDevices(
                    new[] { device },
                    1,
                    (uint)Marshal.SizeOf(typeof(RawInputDevice))))
            {
                throw new InvalidOperationException(
                    "RegisterRawInputDevices failed with Win32 error " + Marshal.GetLastWin32Error() + ".");
            }
        }

        private static Brush CreateNearBlackBrush()
        {
            var brush = new SolidColorBrush(Color.FromRgb(1, 1, 1));
            brush.Freeze();
            return brush;
        }

        private void WriteTestLog()
        {
            try
            {
                string root = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "ClawLab",
                    "Cursor-Refresh-Helper");
                Directory.CreateDirectory(root);
                string content =
                    "Utc=" + DateTime.UtcNow.ToString("O") + Environment.NewLine +
                    "Renderer=WPF" + Environment.NewLine +
                    "NativeFailure=" + nativeFailure + Environment.NewLine +
                    "VisibleTest=" + visibleTest + Environment.NewLine +
                    "ContinuousTest=" + continuousTest + Environment.NewLine +
                    "RawInputEvents=" + rawInputEvents + Environment.NewLine +
                    "AnimationTicks=" + animationTicks + Environment.NewLine +
                    "SuppressedInputEvents=" + suppressedInputEvents + Environment.NewLine +
                    "DeepIdleEntries=" + deepIdleEntries + Environment.NewLine +
                    "TimerResolutionAcquisitions=" + timerResolutionAcquisitions + Environment.NewLine +
                    "TimerResolutionReleases=" + timerResolutionReleases + Environment.NewLine +
                    "WorkingSetTrimAttempts=" + workingSetTrimAttempts + Environment.NewLine;
                File.WriteAllText(Path.Combine(root, "last-test.txt"), content);
            }
            catch
            {
                // Diagnostics must never make the helper fail during shutdown.
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct RawInputDevice
        {
            internal ushort UsagePage;
            internal ushort Usage;
            internal int Flags;
            internal IntPtr Target;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CursorInfo
        {
            internal int Size;
            internal int Flags;
            internal IntPtr Cursor;
            internal System.Drawing.Point ScreenPosition;
        }

        [StructLayout(LayoutKind.Sequential)]
        private static class NativeMethods
        {
            [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
            internal static extern IntPtr GetWindowLongPtr(IntPtr window, int index);

            [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
            internal static extern IntPtr SetWindowLongPtr(IntPtr window, int index, IntPtr value);

            [DllImport("user32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool RegisterRawInputDevices(
                [In] RawInputDevice[] devices,
                uint deviceCount,
                uint structureSize);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool GetCursorInfo(ref CursorInfo cursorInfo);

            [DllImport("winmm.dll")]
            internal static extern uint timeBeginPeriod(uint period);

            [DllImport("winmm.dll")]
            internal static extern uint timeEndPeriod(uint period);

            [DllImport("kernel32.dll")]
            internal static extern IntPtr GetCurrentProcess();

            [DllImport("kernel32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool SetProcessWorkingSetSize(
                IntPtr process,
                IntPtr minimumWorkingSetSize,
                IntPtr maximumWorkingSetSize);
        }
    }
}
