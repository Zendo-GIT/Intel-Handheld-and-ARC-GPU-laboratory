[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($null -eq ('ClawLab.A1MDiagnostics.ArcSyncReadOnly' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace ClawLab.A1MDiagnostics
{
    [StructLayout(LayoutKind.Sequential)]
    public struct CtlApplicationId
    {
        public UInt32 Data1;
        public UInt16 Data2;
        public UInt16 Data3;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
        public byte[] Data4;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct CtlInitArgs
    {
        public UInt32 Size;
        public byte Version;
        public UInt32 AppVersion;
        public UInt32 Flags;
        public UInt32 SupportedVersion;
        public CtlApplicationId ApplicationUid;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct ArcSyncMonitorParams
    {
        public UInt32 Size;
        public byte Version;
        [MarshalAs(UnmanagedType.U1)] public bool IsSupported;
        public float MinimumRefreshRateInHz;
        public float MaximumRefreshRateInHz;
        public UInt32 MaxFrameTimeIncreaseInUs;
        public UInt32 MaxFrameTimeDecreaseInUs;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct ArcSyncProfileParams
    {
        public UInt32 Size;
        public byte Version;
        public Int32 Profile;
        public float MaxRefreshRateInHz;
        public float MinRefreshRateInHz;
        public UInt32 MaxFrameTimeIncreaseInUs;
        public UInt32 MaxFrameTimeDecreaseInUs;
    }

    public sealed class ArcSyncSnapshot
    {
        public int AdapterIndex { get; set; }
        public int DisplayIndex { get; set; }
        public int MonitorResult { get; set; }
        public bool Supported { get; set; }
        public float MonitorMinimumHz { get; set; }
        public float MonitorMaximumHz { get; set; }
        public UInt32 MonitorMaxIncreaseUs { get; set; }
        public UInt32 MonitorMaxDecreaseUs { get; set; }
        public int ProfileResult { get; set; }
        public int ProfileId { get; set; }
        public string ProfileName { get; set; }
        public float ActiveMinimumHz { get; set; }
        public float ActiveMaximumHz { get; set; }
        public UInt32 ActiveMaxIncreaseUs { get; set; }
        public UInt32 ActiveMaxDecreaseUs { get; set; }
    }

    public static class ArcSyncReadOnly
    {
        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlInit(ref CtlInitArgs args, out IntPtr api);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlClose(IntPtr api);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlEnumerateDevices(IntPtr api, ref UInt32 count, IntPtr devices);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlEnumerateDisplayOutputs(IntPtr adapter, ref UInt32 count, IntPtr displays);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlGetIntelArcSyncInfoForMonitor(IntPtr display, ref ArcSyncMonitorParams parameters);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlGetIntelArcSyncProfile(IntPtr display, ref ArcSyncProfileParams parameters);

        private static CtlInitArgs CreateInitArgs()
        {
            return new CtlInitArgs
            {
                Size = (UInt32)Marshal.SizeOf(typeof(CtlInitArgs)),
                Version = 0,
                AppVersion = 0x00010001,
                Flags = 0,
                ApplicationUid = new CtlApplicationId { Data4 = new byte[8] }
            };
        }

        private static string GetProfileName(int profile)
        {
            string[] names = { "INVALID", "RECOMMENDED", "EXCELLENT", "GOOD", "COMPATIBLE", "OFF", "VESA", "CUSTOM" };
            return profile >= 0 && profile < names.Length ? names[profile] : "UNKNOWN_" + profile;
        }

        public static ArcSyncSnapshot[] Query()
        {
            List<ArcSyncSnapshot> results = new List<ArcSyncSnapshot>();
            CtlInitArgs init = CreateInitArgs();
            IntPtr api;
            int result = ctlInit(ref init, out api);
            if (result != 0)
                throw new InvalidOperationException("ctlInit failed: 0x" + result.ToString("X8"));

            IntPtr adapters = IntPtr.Zero;
            try
            {
                UInt32 adapterCount = 0;
                result = ctlEnumerateDevices(api, ref adapterCount, IntPtr.Zero);
                if (result != 0)
                    throw new InvalidOperationException("ctlEnumerateDevices(count) failed: 0x" + result.ToString("X8"));

                adapters = Marshal.AllocHGlobal(checked((int)adapterCount * IntPtr.Size));
                result = ctlEnumerateDevices(api, ref adapterCount, adapters);
                if (result != 0)
                    throw new InvalidOperationException("ctlEnumerateDevices(list) failed: 0x" + result.ToString("X8"));

                for (int adapterIndex = 0; adapterIndex < adapterCount; adapterIndex++)
                {
                    IntPtr adapter = Marshal.ReadIntPtr(adapters, adapterIndex * IntPtr.Size);
                    UInt32 displayCount = 0;
                    result = ctlEnumerateDisplayOutputs(adapter, ref displayCount, IntPtr.Zero);
                    if (result != 0 || displayCount == 0)
                        continue;

                    IntPtr displays = Marshal.AllocHGlobal(checked((int)displayCount * IntPtr.Size));
                    try
                    {
                        result = ctlEnumerateDisplayOutputs(adapter, ref displayCount, displays);
                        if (result != 0)
                            continue;

                        for (int displayIndex = 0; displayIndex < displayCount; displayIndex++)
                        {
                            IntPtr display = Marshal.ReadIntPtr(displays, displayIndex * IntPtr.Size);
                            ArcSyncMonitorParams monitor = new ArcSyncMonitorParams
                            {
                                Size = (UInt32)Marshal.SizeOf(typeof(ArcSyncMonitorParams)),
                                Version = 0
                            };
                            int monitorResult = ctlGetIntelArcSyncInfoForMonitor(display, ref monitor);

                            ArcSyncProfileParams profile = new ArcSyncProfileParams
                            {
                                Size = (UInt32)Marshal.SizeOf(typeof(ArcSyncProfileParams)),
                                Version = 0
                            };
                            int profileResult = ctlGetIntelArcSyncProfile(display, ref profile);

                            results.Add(new ArcSyncSnapshot
                            {
                                AdapterIndex = adapterIndex,
                                DisplayIndex = displayIndex,
                                MonitorResult = monitorResult,
                                Supported = monitor.IsSupported,
                                MonitorMinimumHz = monitor.MinimumRefreshRateInHz,
                                MonitorMaximumHz = monitor.MaximumRefreshRateInHz,
                                MonitorMaxIncreaseUs = monitor.MaxFrameTimeIncreaseInUs,
                                MonitorMaxDecreaseUs = monitor.MaxFrameTimeDecreaseInUs,
                                ProfileResult = profileResult,
                                ProfileId = profile.Profile,
                                ProfileName = GetProfileName(profile.Profile),
                                ActiveMinimumHz = profile.MinRefreshRateInHz,
                                ActiveMaximumHz = profile.MaxRefreshRateInHz,
                                ActiveMaxIncreaseUs = profile.MaxFrameTimeIncreaseInUs,
                                ActiveMaxDecreaseUs = profile.MaxFrameTimeDecreaseInUs
                            });
                        }
                    }
                    finally
                    {
                        Marshal.FreeHGlobal(displays);
                    }
                }
            }
            finally
            {
                if (adapters != IntPtr.Zero)
                    Marshal.FreeHGlobal(adapters);
                ctlClose(api);
            }
            return results.ToArray();
        }
    }
}
'@
}

@([ClawLab.A1MDiagnostics.ArcSyncReadOnly]::Query())
