# Direct Intel display-driver interface used by the ClawLab LFC fix.
# It does not depend on Intel Graphics Command Center or Intel Graphics
# Software application assemblies.
[CmdletBinding()]
param(
    [ValidateSet('Status', 'EnableLowFps', 'DisableLowFps', 'EnableHighFps', 'DisableHighFps')]
    [string]$Action = 'Status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace ClawLab.IntelVrr
{
    public sealed class VrrState
    {
        public UInt32 NtStatus { get; set; }
        public bool Supported { get; set; }
        public bool Enabled { get; set; }
        public bool HighFpsSolutionEnabled { get; set; }
        public bool LowFpsSolutionEnabled { get; set; }
        public UInt32 DisplayCount { get; set; }
        public UInt32 TargetId { get; set; }
        public UInt32 MinimumHz { get; set; }
        public UInt32 MaximumHz { get; set; }
        public string DisplayDeviceName { get; set; }
    }

    public static class DirectVrrEscape
    {
        private const int DISPLAY_DEVICE_ATTACHED_TO_DESKTOP = 0x1;
        private const UInt32 D3DKMT_ESCAPE_DRIVERPRIVATE = 0;
        private const int PrivateDataSize = 124;
        private const int HeaderSize = 16;
        private const UInt32 DisplayEscapeMajor = 1;
        private const UInt32 VrrEscapeMinor = 10;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DISPLAY_DEVICE
        {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct LUID
        {
            public UInt32 LowPart;
            public Int32 HighPart;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct D3DKMT_OPENADAPTERFROMHDC
        {
            public IntPtr hDc;
            public UInt32 hAdapter;
            public LUID AdapterLuid;
            public UInt32 VidPnSourceId;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct D3DKMT_CLOSEADAPTER
        {
            public UInt32 hAdapter;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct D3DKMT_ESCAPE
        {
            public UInt32 hAdapter;
            public UInt32 hDevice;
            public UInt32 Type;
            public UInt32 Flags;
            public IntPtr pPrivateDriverData;
            public UInt32 PrivateDriverDataSize;
            public UInt32 hContext;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool EnumDisplayDevices(
            string lpDevice,
            int iDevNum,
            ref DISPLAY_DEVICE lpDisplayDevice,
            int dwFlags);

        [DllImport("gdi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateDC(
            string lpszDriver,
            string lpszDevice,
            string lpszOutput,
            IntPtr lpInitData);

        [DllImport("gdi32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DeleteDC(IntPtr hdc);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern int D3DKMTOpenAdapterFromHdc(ref D3DKMT_OPENADAPTERFROMHDC data);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern int D3DKMTCloseAdapter(ref D3DKMT_CLOSEADAPTER data);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern int D3DKMTEscape(ref D3DKMT_ESCAPE data);

        private static string GetSingleActiveIntelDisplay()
        {
            var matches = new List<string>();
            for (int index = 0; ; index++)
            {
                var device = new DISPLAY_DEVICE();
                device.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
                if (!EnumDisplayDevices(null, index, ref device, 0))
                {
                    break;
                }
                if ((device.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) == 0)
                {
                    continue;
                }
                if (String.IsNullOrEmpty(device.DeviceID) ||
                    device.DeviceID.IndexOf("VEN_8086", StringComparison.OrdinalIgnoreCase) < 0)
                {
                    continue;
                }
                matches.Add(device.DeviceName);
            }
            if (matches.Count != 1)
            {
                throw new InvalidOperationException(
                    "Expected exactly one active Intel display adapter; found " + matches.Count + ".");
            }
            return matches[0];
        }

        private static void WriteUInt32(byte[] data, int offset, UInt32 value)
        {
            byte[] raw = BitConverter.GetBytes(value);
            Buffer.BlockCopy(raw, 0, data, offset, raw.Length);
        }

        private static UInt32 ReadUInt32(byte[] data, int offset)
        {
            return BitConverter.ToUInt32(data, offset);
        }

        public static VrrState Invoke(UInt32 operation)
        {
            string displayName = GetSingleActiveIntelDisplay();
            IntPtr hdc = IntPtr.Zero;
            UInt32 adapterHandle = 0;
            IntPtr privateData = IntPtr.Zero;
            try
            {
                hdc = CreateDC(null, displayName, null, IntPtr.Zero);
                if (hdc == IntPtr.Zero)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateDC failed.");
                }

                var open = new D3DKMT_OPENADAPTERFROMHDC();
                open.hDc = hdc;
                int openStatus = D3DKMTOpenAdapterFromHdc(ref open);
                if (openStatus != 0 || open.hAdapter == 0)
                {
                    throw new InvalidOperationException(
                        "D3DKMTOpenAdapterFromHdc failed: 0x" + ((UInt32)openStatus).ToString("X8"));
                }
                adapterHandle = open.hAdapter;

                var payload = new byte[PrivateDataSize];
                WriteUInt32(payload, 8, DisplayEscapeMajor);
                WriteUInt32(payload, 12, VrrEscapeMinor);
                WriteUInt32(payload, HeaderSize, operation);

                privateData = Marshal.AllocHGlobal(payload.Length);
                Marshal.Copy(payload, 0, privateData, payload.Length);
                var escape = new D3DKMT_ESCAPE();
                escape.hAdapter = adapterHandle;
                escape.Type = D3DKMT_ESCAPE_DRIVERPRIVATE;
                escape.pPrivateDriverData = privateData;
                escape.PrivateDriverDataSize = (UInt32)payload.Length;

                int status = D3DKMTEscape(ref escape);
                UInt32 ntStatus = unchecked((UInt32)status);
                Marshal.Copy(privateData, payload, 0, payload.Length);

                var state = new VrrState();
                state.NtStatus = ntStatus;
                state.DisplayDeviceName = displayName;
                if (ntStatus != 0)
                {
                    return state;
                }
                state.Supported = payload[20] == 1;
                state.Enabled = payload[21] == 1;
                state.HighFpsSolutionEnabled = payload[22] == 1;
                state.LowFpsSolutionEnabled = payload[23] == 1;
                state.DisplayCount = ReadUInt32(payload, 24);
                if (state.DisplayCount > 0)
                {
                    state.TargetId = ReadUInt32(payload, 28);
                    state.MinimumHz = ReadUInt32(payload, 32);
                    state.MaximumHz = ReadUInt32(payload, 36);
                }
                return state;
            }
            finally
            {
                if (privateData != IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(privateData);
                }
                if (adapterHandle != 0)
                {
                    var close = new D3DKMT_CLOSEADAPTER();
                    close.hAdapter = adapterHandle;
                    D3DKMTCloseAdapter(ref close);
                }
                if (hdc != IntPtr.Zero)
                {
                    DeleteDC(hdc);
                }
            }
        }
    }
}
'@

if (-not ('ClawLab.IntelVrr.DirectVrrEscape' -as [type])) {
    Add-Type -TypeDefinition $source -Language CSharp
}

$operation = switch ($Action) {
    'Status' { [uint32]0 }
    'EnableLowFps' { [uint32]3 }
    'DisableLowFps' { [uint32]4 }
    'EnableHighFps' { [uint32]5 }
    'DisableHighFps' { [uint32]6 }
}
$result = [ClawLab.IntelVrr.DirectVrrEscape]::Invoke($operation)
if ($result.NtStatus -ne 0) {
    throw ('Intel private VRR escape failed: 0x{0:X8}' -f $result.NtStatus)
}
$result
