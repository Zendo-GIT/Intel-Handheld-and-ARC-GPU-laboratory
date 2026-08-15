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
[assembly: AssemblyVersion("2.1.1.0")]
[assembly: AssemblyFileVersion("2.1.1.0")]

namespace ClawLab.CursorRefresh
{
    internal static class Program
    {
        private const string MutexName = "Local\\ClawLab.MSIClaw.CursorRefreshHelper";

        [STAThread]
        private static int Main(string[] args)
        {
            bool createdNew;
            using (var mutex = new Mutex(true, MutexName, out createdNew))
            {
                if (!createdNew)
                    return 2;

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

                var application = new Application
                {
                    ShutdownMode = ShutdownMode.OnMainWindowClose
                };
                var surface = new RefreshSurface(testSeconds, visibleTest, continuousTest);
                application.Run(surface);
                GC.KeepAlive(mutex);
                return 0;
            }
        }
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
        private static readonly Brush NearBlackBrush = CreateNearBlackBrush();

        private readonly DispatcherTimer animationTimer;
        private readonly DispatcherTimer testTimer;
        private readonly bool visibleTest;
        private readonly bool continuousTest;
        private long activityUntil;
        private bool toggle;
        private bool timerResolutionActive;
        private bool deepIdle;
        private long rawInputEvents;
        private long animationTicks;
        private long suppressedInputEvents;
        private long deepIdleEntries;
        private long timerResolutionAcquisitions;
        private long timerResolutionReleases;
        private long workingSetTrimAttempts;
        private HwndSource source;

        internal RefreshSurface(int testSeconds, bool visibleTest, bool continuousTest)
        {
            this.visibleTest = visibleTest;
            this.continuousTest = continuousTest;

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

            if (continuousTest)
            {
                ExitDeepIdle();
                activityUntil = long.MaxValue;
                animationTimer.Start();
            }
            else
            {
                EnterDeepIdle();
            }
            if (testTimer != null)
                testTimer.Start();
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
                    EnterDeepIdle();
                    return IntPtr.Zero;
                }

                activityUntil = Stopwatch.GetTimestamp() + TailTicks;
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

        private void EnterDeepIdle()
        {
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
