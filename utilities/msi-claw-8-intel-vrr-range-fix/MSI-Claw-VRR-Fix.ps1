[CmdletBinding()]
param(
    [ValidateSet('Status', 'Install48', 'Install30', 'Restore', 'EmergencyRestoreEdid', 'ApplyStartup')]
    [string]$Action = 'Status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fixVersion = '1.0.1'
$targetManufacturer = 'CSW'
$targetProductCode = '0801'
$targetPanelName = 'PN8007QB1-2'
$targetMinimumHz = 48.0
$experimentalMinimumHz = 30.0
$targetMaximumHz = 120.0
$profileExcellent = 2
$profileCustom = 7
$stateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-Arc-Sync-Full-Range'
$backupPath = Join-Path $stateRoot 'original-profile.json'
$experimentalStatePath = Join-Path $stateRoot 'experimental-edid.json'
$installedScriptPath = Join-Path $stateRoot 'MSI-Claw-VRR-Fix.ps1'
$startupStatusPath = Join-Path $stateRoot 'startup-last-run.json'
$startupTaskName = 'ClawLab MSI Claw 8 VRR Range'
$validatedPhysicalEdidSha256 = 'E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0'
$validatedExperimentalEdidSha256 = '14CDDC390CF69367C4B6821A46728518200446A33F708A1A87CA673B68B66918'
$validatedExperimentalBlock0Sha256 = '597D5A95C28171B7B9DF111C1BB12830532F63831EA38111E02D618850E76698'
$validatedExperimentalBlock1Sha256 = 'C2000A5E8A3D91C80DCE75DC5BB2F63269C77501338FD059B4CF71CD0CE94743'

function Convert-WmiText {
    param([AllowNull()][object]$Values)

    if ($null -eq $Values) {
        return ''
    }
    return (-join @($Values | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }))
}

function Get-ValidatedPanel {
    $matches = @(
        Get-CimInstance -Namespace 'root\wmi' -ClassName 'WmiMonitorID' -ErrorAction Stop |
            ForEach-Object {
                [pscustomobject]@{
                    InstanceName = [string]$_.InstanceName
                    Manufacturer = Convert-WmiText -Values $_.ManufacturerName
                    ProductCode = Convert-WmiText -Values $_.ProductCodeID
                    Name = Convert-WmiText -Values $_.UserFriendlyName
                }
            } |
            Where-Object {
                $_.Manufacturer -eq $targetManufacturer -and
                $_.ProductCode -eq $targetProductCode -and
                $_.Name -eq $targetPanelName
            }
    )

    if ($matches.Count -ne 1) {
        throw "The validated $targetPanelName panel was not found exactly once. No display setting was changed."
    }
    return $matches[0]
}

function Get-IntelGpu {
    $gpus = @(
        Get-CimInstance -ClassName 'Win32_VideoController' -ErrorAction Stop |
            Where-Object { $_.PNPDeviceID -like 'PCI\VEN_8086&*' }
    )
    if ($gpus.Count -lt 1) {
        throw 'No Intel graphics adapter was found. No display setting was changed.'
    }
    return $gpus[0]
}

function Get-ByteArraySha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Test-ByteArrayEqual {
    param(
        [AllowNull()][byte[]]$Left,
        [AllowNull()][byte[]]$Right
    )

    if ($null -eq $Left -or $null -eq $Right -or $Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }
    return $true
}

function Get-PanelRegistryContext {
    param([Parameter(Mandatory)][object]$Panel)

    $instanceId = $Panel.InstanceName -replace '_\d+$', ''
    if ($instanceId -notlike 'DISPLAY\CSW0801\*') {
        throw "Unexpected validated-panel instance ID: $instanceId"
    }

    $deviceParameters = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\$instanceId\Device Parameters"
    if (-not (Test-Path -LiteralPath $deviceParameters -PathType Container)) {
        throw 'The validated panel registry key is missing.'
    }

    $physicalEdid = [byte[]](Get-ItemPropertyValue -LiteralPath $deviceParameters -Name 'EDID' -ErrorAction Stop)
    if ($physicalEdid.Length -ne 256) {
        throw "Unexpected panel EDID length: $($physicalEdid.Length) bytes."
    }

    [pscustomobject]@{
        InstanceId = $instanceId
        DeviceParametersPath = $deviceParameters
        OverridePath = Join-Path $deviceParameters 'EDID_OVERRIDE'
        PhysicalEdid = $physicalEdid
        PhysicalEdidSha256 = Get-ByteArraySha256 -Bytes $physicalEdid
    }
}

function New-ExperimentalEdid {
    param([Parameter(Mandatory)][byte[]]$PhysicalEdid)

    $physicalHash = Get-ByteArraySha256 -Bytes $PhysicalEdid
    if ($physicalHash -ne $validatedPhysicalEdidSha256) {
        throw "Unsupported panel EDID: $physicalHash. Experimental mode is restricted to the validated EDID."
    }
    if ($PhysicalEdid[95] -ne 48 -or $PhysicalEdid[142] -ne 48) {
        throw 'The validated EDID no longer contains the expected 48 Hz range fields.'
    }

    foreach ($start in @(0, 128)) {
        $sum = 0
        for ($offset = $start; $offset -lt ($start + 128); $offset++) {
            $sum += $PhysicalEdid[$offset]
        }
        if (($sum % 256) -ne 0) {
            throw "The physical EDID block at offset $start has an invalid checksum."
        }
    }

    $modified = [byte[]]$PhysicalEdid.Clone()
    $modified[95] = [byte]$experimentalMinimumHz
    $modified[127] = 0
    $sum = 0
    for ($offset = 0; $offset -lt 127; $offset++) {
        $sum += $modified[$offset]
    }
    $modified[127] = [byte]((256 - ($sum % 256)) % 256)

    $modified[142] = [byte]$experimentalMinimumHz
    $modified[255] = 0
    $sum = 0
    for ($offset = 128; $offset -lt 255; $offset++) {
        $sum += $modified[$offset]
    }
    $modified[255] = [byte]((256 - ($sum % 256)) % 256)

    $modifiedHash = Get-ByteArraySha256 -Bytes $modified
    if ($modifiedHash -ne $validatedExperimentalEdidSha256) {
        throw "Internal experimental EDID verification failed: $modifiedHash"
    }

    [pscustomobject]@{
        Complete = $modified
        Block0 = [byte[]]$modified[0..127]
        Block1 = [byte[]]$modified[128..255]
        Sha256 = $modifiedHash
    }
}

function Get-EdidOverrideState {
    param(
        [Parameter(Mandatory)][object]$RegistryContext,
        [Parameter(Mandatory)][object]$ExperimentalEdid
    )

    if (-not (Test-Path -LiteralPath $RegistryContext.OverridePath -PathType Container)) {
        return [pscustomobject]@{ State = 'NONE'; Block0 = $null; Block1 = $null }
    }

    $block0 = $null
    $block1 = $null
    try { $block0 = [byte[]](Get-ItemPropertyValue -LiteralPath $RegistryContext.OverridePath -Name '0' -ErrorAction Stop) } catch {}
    try { $block1 = [byte[]](Get-ItemPropertyValue -LiteralPath $RegistryContext.OverridePath -Name '1' -ErrorAction Stop) } catch {}

    $state = if ($null -eq $block0 -and $null -eq $block1) {
        'NONE'
    }
    elseif ((Test-ByteArrayEqual -Left $block0 -Right $ExperimentalEdid.Block0) -and
        (Test-ByteArrayEqual -Left $block1 -Right $ExperimentalEdid.Block1)) {
        'CLAWLAB_30_120'
    }
    else {
        'UNKNOWN_OVERRIDE'
    }

    return [pscustomobject]@{ State = $state; Block0 = $block0; Block1 = $block1 }
}

function Confirm-AdministratorOrRelaunch {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return
    }

    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action $Action"
    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $process.ExitCode
}

function Get-StartupReapplyState {
    $task = Get-ScheduledTask -TaskName $startupTaskName -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        return 'NOT_INSTALLED'
    }
    if (-not (Test-Path -LiteralPath $installedScriptPath -PathType Leaf)) {
        return 'TASK_WITHOUT_SCRIPT'
    }
    return [string]$task.State
}

function Install-StartupReapply {
    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    [IO.File]::Copy($PSCommandPath, $installedScriptPath, $true)

    $sourceHash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
    $installedHash = (Get-FileHash -LiteralPath $installedScriptPath -Algorithm SHA256).Hash
    if ($sourceHash -ne $installedHash) {
        throw 'The installed startup script failed its integrity check.'
    }

    $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installedScriptPath`" -Action ApplyStartup"
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
    $trigger.Delay = 'PT45S'
    $taskAction = New-ScheduledTaskAction -Execute $powerShellPath -Argument $arguments
    $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
    $task = New-ScheduledTask -Action $taskAction -Trigger $trigger -Principal $principal `
        -Settings $settings -Description 'Reapplies the verified MSI Claw Intel Arc Sync VRR profile after sign-in.'
    Register-ScheduledTask -TaskName $startupTaskName -InputObject $task -Force | Out-Null

    if ((Get-StartupReapplyState) -eq 'NOT_INSTALLED') {
        throw 'The startup reapply task could not be verified.'
    }
}

function Remove-StartupReapply {
    $task = Get-ScheduledTask -TaskName $startupTaskName -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        Unregister-ScheduledTask -TaskName $startupTaskName -Confirm:$false -ErrorAction Stop
    }
    [IO.File]::Delete($installedScriptPath)
    [IO.File]::Delete($startupStatusPath)
    if ((Get-StartupReapplyState) -ne 'NOT_INSTALLED') {
        throw 'The startup reapply task could not be removed completely.'
    }
}

function Write-StartupResult {
    param(
        [Parameter(Mandatory)][bool]$Success,
        [Parameter(Mandatory)][string]$Message
    )

    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    $result = [ordered]@{
        SchemaVersion = 1
        FixVersion = $fixVersion
        Timestamp = (Get-Date).ToString('o')
        Success = $Success
        Message = $Message
    }
    [IO.File]::WriteAllText(
        $startupStatusPath,
        ($result | ConvertTo-Json),
        [Text.UTF8Encoding]::new($false)
    )
}

function Add-ArcSyncControlType {
    if ($null -ne ('ClawLab.VrrFix.ArcSyncControl' -as [type])) {
        return
    }

    $controlLibrary = Join-Path $env:SystemRoot 'System32\ControlLib.dll'
    if (-not (Test-Path -LiteralPath $controlLibrary -PathType Leaf)) {
        throw 'Intel Control Library (ControlLib.dll) is missing. Install a current Intel graphics driver first.'
    }

    $source = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace ClawLab.VrrFix
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

    public static class ArcSyncControl
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

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlSetIntelArcSyncProfile(IntPtr display, ref ArcSyncProfileParams parameters);

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

        public static int SetProfile(int targetAdapterIndex, int targetDisplayIndex,
            float expectedMonitorMinimumHz, float expectedMonitorMaximumHz, int profileId,
            float minimumHz, float maximumHz, UInt32 maxIncreaseUs, UInt32 maxDecreaseUs)
        {
            CtlInitArgs init = CreateInitArgs();
            IntPtr api;
            int result = ctlInit(ref init, out api);
            if (result != 0)
                return result;

            IntPtr adapters = IntPtr.Zero;
            try
            {
                UInt32 adapterCount = 0;
                result = ctlEnumerateDevices(api, ref adapterCount, IntPtr.Zero);
                if (result != 0)
                    return result;
                if (targetAdapterIndex < 0 || targetAdapterIndex >= adapterCount)
                    return unchecked((int)0x40000017);

                adapters = Marshal.AllocHGlobal(checked((int)adapterCount * IntPtr.Size));
                result = ctlEnumerateDevices(api, ref adapterCount, adapters);
                if (result != 0)
                    return result;

                IntPtr adapter = Marshal.ReadIntPtr(adapters, targetAdapterIndex * IntPtr.Size);
                UInt32 displayCount = 0;
                result = ctlEnumerateDisplayOutputs(adapter, ref displayCount, IntPtr.Zero);
                if (result != 0)
                    return result;
                if (targetDisplayIndex < 0 || targetDisplayIndex >= displayCount)
                    return unchecked((int)0x40000017);

                IntPtr displays = Marshal.AllocHGlobal(checked((int)displayCount * IntPtr.Size));
                try
                {
                    result = ctlEnumerateDisplayOutputs(adapter, ref displayCount, displays);
                    if (result != 0)
                        return result;

                    IntPtr display = Marshal.ReadIntPtr(displays, targetDisplayIndex * IntPtr.Size);
                    ArcSyncMonitorParams monitor = new ArcSyncMonitorParams
                    {
                        Size = (UInt32)Marshal.SizeOf(typeof(ArcSyncMonitorParams)),
                        Version = 0
                    };
                    result = ctlGetIntelArcSyncInfoForMonitor(display, ref monitor);
                    if (result != 0 || !monitor.IsSupported)
                        return result != 0 ? result : unchecked((int)0x40000017);
                    if (Math.Abs(monitor.MinimumRefreshRateInHz - expectedMonitorMinimumHz) > 0.1f ||
                        Math.Abs(monitor.MaximumRefreshRateInHz - expectedMonitorMaximumHz) > 0.1f)
                        return unchecked((int)0x40000017);

                    ArcSyncProfileParams profile = new ArcSyncProfileParams
                    {
                        Size = (UInt32)Marshal.SizeOf(typeof(ArcSyncProfileParams)),
                        Version = 0,
                        Profile = profileId,
                        MinRefreshRateInHz = minimumHz,
                        MaxRefreshRateInHz = maximumHz,
                        MaxFrameTimeIncreaseInUs = maxIncreaseUs,
                        MaxFrameTimeDecreaseInUs = maxDecreaseUs
                    };
                    return ctlSetIntelArcSyncProfile(display, ref profile);
                }
                finally
                {
                    Marshal.FreeHGlobal(displays);
                }
            }
            finally
            {
                if (adapters != IntPtr.Zero)
                    Marshal.FreeHGlobal(adapters);
                ctlClose(api);
            }
        }
    }
}
'@

    Add-Type -TypeDefinition $source -Language CSharp
}

function Get-TargetSnapshot {
    param([int]$Attempts = 1)

    $lastError = $null
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $candidates = @(
                [ClawLab.VrrFix.ArcSyncControl]::Query() |
                    Where-Object {
                        $_.MonitorResult -eq 0 -and
                        $_.ProfileResult -eq 0 -and
                        $_.Supported
                    }
            )
            if ($candidates.Count -eq 1) {
                if ([Math]::Abs($candidates[0].MonitorMaximumHz - $targetMaximumHz) -gt 0.1 -or
                    ([Math]::Abs($candidates[0].MonitorMinimumHz - $targetMinimumHz) -gt 0.1 -and
                    [Math]::Abs($candidates[0].MonitorMinimumHz - $experimentalMinimumHz) -gt 0.1)) {
                    throw "Unexpected Arc Sync monitor range: $($candidates[0].MonitorMinimumHz)-$($candidates[0].MonitorMaximumHz) Hz."
                }
                return $candidates[0]
            }
            $lastError = "Expected exactly one active Intel Arc Sync output; found $($candidates.Count). Disconnect external VRR displays and retry."
        }
        catch {
            $lastError = $_.Exception.Message
        }

        if ($attempt -lt $Attempts) {
            Start-Sleep -Milliseconds 500
        }
    }
    throw "$lastError No display setting was changed."
}

function Get-OriginalProfile {
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        return $null
    }
    $backup = Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json
    foreach ($property in @(
        'ProfileId',
        'ProfileName',
        'MinRefreshRateInHz',
        'MaxRefreshRateInHz',
        'MaxFrameTimeIncreaseInUs',
        'MaxFrameTimeDecreaseInUs'
    )) {
        if ($property -notin $backup.PSObject.Properties.Name) {
            throw "The saved original profile is invalid: missing $property. No display setting was changed."
        }
    }
    if ([int]$backup.ProfileId -lt 1 -or [int]$backup.ProfileId -gt 7) {
        throw 'The saved original profile ID is invalid. No display setting was changed.'
    }
    return $backup
}

function Save-OriginalProfile {
    param(
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Gpu
    )

    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        [void](Get-OriginalProfile)
        return
    }

    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    $backup = [ordered]@{
        SchemaVersion = 1
        FixVersion = $fixVersion
        SavedAt = (Get-Date).ToString('o')
        PanelInstanceName = $Panel.InstanceName
        PanelName = $Panel.Name
        IntelDriverVersion = [string]$Gpu.DriverVersion
        ProfileId = $Snapshot.ProfileId
        ProfileName = $Snapshot.ProfileName
        MinRefreshRateInHz = $Snapshot.ActiveMinimumHz
        MaxRefreshRateInHz = $Snapshot.ActiveMaximumHz
        MaxFrameTimeIncreaseInUs = $Snapshot.ActiveMaxIncreaseUs
        MaxFrameTimeDecreaseInUs = $Snapshot.ActiveMaxDecreaseUs
    }
    [IO.File]::WriteAllText(
        $backupPath,
        ($backup | ConvertTo-Json),
        [Text.UTF8Encoding]::new($false)
    )
}

function Invoke-SetProfile {
    param(
        [Parameter(Mandatory)][object]$Target,
        [Parameter(Mandatory)][int]$ProfileId,
        [float]$MinimumHz = 0,
        [float]$MaximumHz = 0,
        [uint32]$MaxIncreaseUs = 0,
        [uint32]$MaxDecreaseUs = 0
    )

    $result = [ClawLab.VrrFix.ArcSyncControl]::SetProfile(
        [int]$Target.AdapterIndex,
        [int]$Target.DisplayIndex,
        [float]$Target.MonitorMinimumHz,
        [float]$Target.MonitorMaximumHz,
        $ProfileId,
        $MinimumHz,
        $MaximumHz,
        $MaxIncreaseUs,
        $MaxDecreaseUs
    )
    if ($result -ne 0) {
        throw ('Intel ctlSetIntelArcSyncProfile failed with code 0x{0:X8}.' -f ([int64]$result))
    }
}

function Restore-SnapshotProfile {
    param(
        [Parameter(Mandatory)][object]$Target,
        [Parameter(Mandatory)][object]$Profile
    )

    if ([int]$Profile.ProfileId -eq $profileCustom) {
        Invoke-SetProfile -Target $Target -ProfileId ([int]$Profile.ProfileId) `
            -MinimumHz ([float]$Profile.MinRefreshRateInHz) `
            -MaximumHz ([float]$Profile.MaxRefreshRateInHz) `
            -MaxIncreaseUs ([uint32]$Profile.MaxFrameTimeIncreaseInUs) `
            -MaxDecreaseUs ([uint32]$Profile.MaxFrameTimeDecreaseInUs)
    }
    else {
        Invoke-SetProfile -Target $Target -ProfileId ([int]$Profile.ProfileId)
    }
}

function Get-StatusObject {
    param(
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Gpu,
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][object]$OverrideState
    )

    $officialRangeActive = (
        $Snapshot.ProfileId -eq $profileExcellent -and
        [Math]::Abs($Snapshot.ActiveMinimumHz - $targetMinimumHz) -le 0.1 -and
        [Math]::Abs($Snapshot.ActiveMaximumHz - $targetMaximumHz) -le 0.1
    )
    $experimentalRangeActive = (
        $OverrideState.State -eq 'CLAWLAB_30_120' -and
        $Snapshot.ProfileId -eq $profileExcellent -and
        [Math]::Abs($Snapshot.ActiveMinimumHz - $experimentalMinimumHz) -le 0.1 -and
        [Math]::Abs($Snapshot.ActiveMaximumHz - $targetMaximumHz) -le 0.1
    )

    $state = if ($experimentalRangeActive) {
        'EXPERIMENTAL_30_120_ACTIVE'
    }
    elseif ($OverrideState.State -eq 'CLAWLAB_30_120') {
        'EXPERIMENTAL_OVERRIDE_PENDING_RESTART'
    }
    elseif ($OverrideState.State -eq 'UNKNOWN_OVERRIDE') {
        'UNKNOWN_EDID_OVERRIDE'
    }
    elseif ($officialRangeActive) {
        'OFFICIAL_48_120_ACTIVE'
    }
    else {
        'DRIVER_PROFILE_CONSTRAINED'
    }

    [pscustomobject]@{
        FixVersion = $fixVersion
        State = $state
        Panel = $Panel.Name
        PanelId = "$($Panel.Manufacturer)$($Panel.ProductCode)"
        IntelGpu = [string]$Gpu.Name
        IntelDriver = [string]$Gpu.DriverVersion
        MonitorSupportedRange = '{0:0.#}-{1:0.#} Hz' -f $Snapshot.MonitorMinimumHz, $Snapshot.MonitorMaximumHz
        DriverProfile = $Snapshot.ProfileName
        DriverActiveRange = '{0:0.#}-{1:0.#} Hz' -f $Snapshot.ActiveMinimumHz, $Snapshot.ActiveMaximumHz
        OriginalProfileSaved = Test-Path -LiteralPath $backupPath -PathType Leaf
        BackupPath = $backupPath
        StartupReapply = Get-StartupReapplyState
        EdidOverride = $OverrideState.State
        RestartRequired = $OverrideState.State -eq 'CLAWLAB_30_120' -and -not $experimentalRangeActive
        RegistryModified = $OverrideState.State -eq 'CLAWLAB_30_120'
        DriverFilesModified = $false
    }
}

try {
    if ($Action -eq 'EmergencyRestoreEdid') {
        Confirm-AdministratorOrRelaunch
        if (-not (Test-Path -LiteralPath $experimentalStatePath -PathType Leaf)) {
            throw 'The ClawLab experimental EDID state file is missing. Nothing was removed.'
        }
        $emergencyState = Get-Content -LiteralPath $experimentalStatePath -Raw | ConvertFrom-Json
        if ('RegistryPath' -notin $emergencyState.PSObject.Properties.Name) {
            throw 'The ClawLab experimental EDID state file is invalid. Nothing was removed.'
        }
        $emergencyOverridePath = [string]$emergencyState.RegistryPath
        if ($emergencyOverridePath -notlike 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\DISPLAY\CSW0801\*\Device Parameters\EDID_OVERRIDE') {
            throw "Unsafe or unexpected EDID override path: $emergencyOverridePath"
        }
        $emergencyBlock0 = [byte[]](Get-ItemPropertyValue -LiteralPath $emergencyOverridePath -Name '0' -ErrorAction Stop)
        $emergencyBlock1 = [byte[]](Get-ItemPropertyValue -LiteralPath $emergencyOverridePath -Name '1' -ErrorAction Stop)
        if ((Get-ByteArraySha256 -Bytes $emergencyBlock0) -ne $validatedExperimentalBlock0Sha256 -or
            (Get-ByteArraySha256 -Bytes $emergencyBlock1) -ne $validatedExperimentalBlock1Sha256) {
            throw 'The installed EDID override does not match ClawLab experimental mode. Nothing was removed.'
        }
        Remove-ItemProperty -LiteralPath $emergencyOverridePath -Name '0' -ErrorAction Stop
        Remove-ItemProperty -LiteralPath $emergencyOverridePath -Name '1' -ErrorAction Stop
        [IO.File]::Delete($experimentalStatePath)
        Write-Host 'Removed the verified ClawLab experimental EDID override.' -ForegroundColor Green
        Write-Host 'Restart the PC. Then run RESTORE_ORIGINAL_VRR.bat in normal Windows to restore the saved Intel profile.' -ForegroundColor Yellow
        exit 0
    }

    if ($Action -eq 'ApplyStartup') {
        $graphicsSoftwareDeadline = (Get-Date).AddSeconds(90)
        $graphicsSoftwareSeen = $false
        do {
            $graphicsSoftwareSeen = $null -ne (Get-Process -Name 'IntelGraphicsSoftware' -ErrorAction SilentlyContinue)
            if (-not $graphicsSoftwareSeen) {
                Start-Sleep -Seconds 2
            }
        } while (-not $graphicsSoftwareSeen -and (Get-Date) -lt $graphicsSoftwareDeadline)

        if ($graphicsSoftwareSeen) {
            Start-Sleep -Seconds 10
        }
    }

    $panel = Get-ValidatedPanel
    $gpu = Get-IntelGpu
    $registryContext = Get-PanelRegistryContext -Panel $panel
    $experimentalEdid = New-ExperimentalEdid -PhysicalEdid $registryContext.PhysicalEdid
    $overrideState = Get-EdidOverrideState -RegistryContext $registryContext -ExperimentalEdid $experimentalEdid
    Add-ArcSyncControlType
    $before = Get-TargetSnapshot -Attempts 5

    switch ($Action) {
        'Status' {
            Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $before -OverrideState $overrideState
        }

        'ApplyStartup' {
            if ($overrideState.State -eq 'UNKNOWN_OVERRIDE') {
                throw 'An unknown EDID override is installed. Startup reapply was cancelled.'
            }
            $expectedMinimumHz = if ($overrideState.State -eq 'CLAWLAB_30_120') {
                $experimentalMinimumHz
            }
            else {
                $targetMinimumHz
            }
            if ([Math]::Abs($before.MonitorMinimumHz - $expectedMinimumHz) -gt 0.1 -or
                [Math]::Abs($before.MonitorMaximumHz - $targetMaximumHz) -gt 0.1) {
                throw "Startup reapply found an unexpected monitor range: $($before.MonitorMinimumHz)-$($before.MonitorMaximumHz) Hz."
            }

            Invoke-SetProfile -Target $before -ProfileId $profileExcellent
            $after = Get-TargetSnapshot -Attempts 10
            if ($after.ProfileId -ne $profileExcellent -or
                [Math]::Abs($after.ActiveMinimumHz - $expectedMinimumHz) -gt 0.1 -or
                [Math]::Abs($after.ActiveMaximumHz - $targetMaximumHz) -gt 0.1) {
                throw "Startup profile verification failed: $($after.ProfileName), $($after.ActiveMinimumHz)-$($after.ActiveMaximumHz) Hz."
            }
            Write-StartupResult -Success $true -Message ("{0}, {1}-{2} Hz" -f $after.ProfileName, $after.ActiveMinimumHz, $after.ActiveMaximumHz)
            exit 0
        }

        'Install48' {
            if ($overrideState.State -eq 'UNKNOWN_OVERRIDE') {
                throw 'An unknown EDID override is installed. Remove it with its original tool before using official mode.'
            }
            if ($overrideState.State -eq 'CLAWLAB_30_120') {
                throw 'Experimental 30-120 mode is installed. Run RESTORE_ORIGINAL_VRR.bat before installing official mode.'
            }
            if ([Math]::Abs($before.MonitorMinimumHz - $targetMinimumHz) -gt 0.1) {
                throw "Official mode expected the panel's native 48-120 Hz range, but the driver reports $($before.MonitorMinimumHz)-$($before.MonitorMaximumHz) Hz."
            }

            Save-OriginalProfile -Snapshot $before -Panel $panel -Gpu $gpu
            if ($before.ProfileId -eq $profileExcellent -and
                [Math]::Abs($before.ActiveMinimumHz - $targetMinimumHz) -le 0.1 -and
                [Math]::Abs($before.ActiveMaximumHz - $targetMaximumHz) -le 0.1) {
                Install-StartupReapply
                Write-Host 'Official Intel Arc Sync 48-120 Hz mode is already active.' -ForegroundColor Green
                Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $before -OverrideState $overrideState
                break
            }

            try {
                Invoke-SetProfile -Target $before -ProfileId $profileExcellent
                $after = Get-TargetSnapshot -Attempts 10
                if ($after.ProfileId -ne $profileExcellent -or
                    [Math]::Abs($after.ActiveMinimumHz - $targetMinimumHz) -gt 0.1 -or
                    [Math]::Abs($after.ActiveMaximumHz - $targetMaximumHz) -gt 0.1) {
                    throw "Driver verification failed: profile $($after.ProfileName), range $($after.ActiveMinimumHz)-$($after.ActiveMaximumHz) Hz."
                }
            }
            catch {
                try {
                    Restore-SnapshotProfile -Target $before -Profile $before
                }
                catch {
                    Write-Warning "Automatic rollback also failed: $($_.Exception.Message)"
                }
                throw
            }

            Install-StartupReapply
            Write-Host 'Official Intel Arc Sync 48-120 Hz mode is active and verified.' -ForegroundColor Green
            Write-Host 'Automatic reapply is installed for future Windows sign-ins.' -ForegroundColor Green
            Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $after -OverrideState $overrideState
        }

        'Install30' {
            if ($overrideState.State -eq 'UNKNOWN_OVERRIDE') {
                throw 'An unknown EDID override is installed. Remove it with its original tool before using experimental mode.'
            }

            Confirm-AdministratorOrRelaunch
            Save-OriginalProfile -Snapshot $before -Panel $panel -Gpu $gpu

            if ($overrideState.State -eq 'NONE') {
                if ([Math]::Abs($before.MonitorMinimumHz - $targetMinimumHz) -gt 0.1) {
                    throw "Experimental installation must start from the native 48-120 Hz EDID, but the driver reports $($before.MonitorMinimumHz)-$($before.MonitorMaximumHz) Hz."
                }

                Invoke-SetProfile -Target $before -ProfileId $profileExcellent
                $official = Get-TargetSnapshot -Attempts 10
                if ($official.ProfileId -ne $profileExcellent -or
                    [Math]::Abs($official.ActiveMinimumHz - $targetMinimumHz) -gt 0.1 -or
                    [Math]::Abs($official.ActiveMaximumHz - $targetMaximumHz) -gt 0.1) {
                    throw 'Could not establish the verified official 48-120 Hz baseline before applying the experimental EDID.'
                }

                [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
                $experimentalState = [ordered]@{
                    SchemaVersion = 1
                    FixVersion = $fixVersion
                    InstalledAt = (Get-Date).ToString('o')
                    PanelInstanceId = $registryContext.InstanceId
                    RegistryPath = $registryContext.OverridePath
                    PhysicalEdidSha256 = $registryContext.PhysicalEdidSha256
                    ExperimentalEdidSha256 = $experimentalEdid.Sha256
                    ExperimentalMinimumHz = $experimentalMinimumHz
                    MaximumHz = $targetMaximumHz
                }
                [IO.File]::WriteAllText(
                    $experimentalStatePath,
                    ($experimentalState | ConvertTo-Json),
                    [Text.UTF8Encoding]::new($false)
                )

                try {
                    New-Item -Path $registryContext.OverridePath -Force | Out-Null
                    New-ItemProperty -LiteralPath $registryContext.OverridePath -Name '0' -PropertyType Binary -Value $experimentalEdid.Block0 -Force | Out-Null
                    New-ItemProperty -LiteralPath $registryContext.OverridePath -Name '1' -PropertyType Binary -Value $experimentalEdid.Block1 -Force | Out-Null
                    $overrideState = Get-EdidOverrideState -RegistryContext $registryContext -ExperimentalEdid $experimentalEdid
                    if ($overrideState.State -ne 'CLAWLAB_30_120') {
                        throw 'The experimental EDID registry write did not verify.'
                    }
                }
                catch {
                    Remove-ItemProperty -LiteralPath $registryContext.OverridePath -Name '0' -ErrorAction SilentlyContinue
                    Remove-ItemProperty -LiteralPath $registryContext.OverridePath -Name '1' -ErrorAction SilentlyContinue
                    [IO.File]::Delete($experimentalStatePath)
                    try { Restore-SnapshotProfile -Target $official -Profile $before } catch {}
                    throw
                }

                Install-StartupReapply
                Write-Host 'Experimental 30-120 Hz EDID override is installed and verified.' -ForegroundColor Yellow
                Write-Host 'Restart the PC to make Windows and the Intel driver reload the display EDID.' -ForegroundColor Yellow
                $status = Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $official -OverrideState $overrideState
                $status.RestartRequired = $true
                $status
                break
            }

            if ([Math]::Abs($before.MonitorMinimumHz - $experimentalMinimumHz) -le 0.1) {
                Invoke-SetProfile -Target $before -ProfileId $profileExcellent
                $after = Get-TargetSnapshot -Attempts 10
                if ($after.ProfileId -ne $profileExcellent -or
                    [Math]::Abs($after.ActiveMinimumHz - $experimentalMinimumHz) -gt 0.1 -or
                    [Math]::Abs($after.ActiveMaximumHz - $targetMaximumHz) -gt 0.1) {
                    throw "Experimental driver verification failed: $($after.ProfileName), $($after.ActiveMinimumHz)-$($after.ActiveMaximumHz) Hz."
                }
                Install-StartupReapply
                Write-Host 'Experimental 30-120 Hz mode is active and verified by the Intel driver.' -ForegroundColor Yellow
                Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $after -OverrideState $overrideState
            }
            else {
                Install-StartupReapply
                Write-Host 'The experimental override is present but has not been loaded by Windows yet.' -ForegroundColor Yellow
                Write-Host 'Restart the PC, then run CHECK_STATUS.bat.' -ForegroundColor Yellow
                $status = Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $before -OverrideState $overrideState
                $status.RestartRequired = $true
                $status
            }
        }

        'Restore' {
            $original = Get-OriginalProfile
            if ($null -eq $original) {
                throw 'No saved original profile is available. No display setting was changed.'
            }

            if ($overrideState.State -eq 'UNKNOWN_OVERRIDE') {
                throw 'An unknown EDID override is installed. It was not created by this package and will not be removed.'
            }
            if ($overrideState.State -eq 'CLAWLAB_30_120') {
                Confirm-AdministratorOrRelaunch
            }

            Restore-SnapshotProfile -Target $before -Profile $original
            $after = Get-TargetSnapshot -Attempts 10
            if ($after.ProfileId -ne [int]$original.ProfileId) {
                throw "Original profile verification failed: expected ID $($original.ProfileId), got $($after.ProfileId)."
            }

            if ($overrideState.State -eq 'CLAWLAB_30_120') {
                Remove-ItemProperty -LiteralPath $registryContext.OverridePath -Name '0' -ErrorAction Stop
                Remove-ItemProperty -LiteralPath $registryContext.OverridePath -Name '1' -ErrorAction Stop
                $overrideState = Get-EdidOverrideState -RegistryContext $registryContext -ExperimentalEdid $experimentalEdid
                if ($overrideState.State -ne 'NONE') {
                    throw 'The experimental EDID override could not be removed completely.'
                }
            }
            Remove-StartupReapply
            [IO.File]::Delete($backupPath)
            [IO.File]::Delete($experimentalStatePath)
            Write-Host "Restored the original Intel Arc Sync profile: $($after.ProfileName)." -ForegroundColor Green
            Write-Host 'Restart the PC to make Windows reload the physical panel EDID.' -ForegroundColor Yellow
            $status = Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $after -OverrideState $overrideState
            $status.RestartRequired = $true
            $status
        }
    }
}
catch {
    if ($Action -eq 'ApplyStartup') {
        try { Write-StartupResult -Success $false -Message $_.Exception.Message } catch {}
    }
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
