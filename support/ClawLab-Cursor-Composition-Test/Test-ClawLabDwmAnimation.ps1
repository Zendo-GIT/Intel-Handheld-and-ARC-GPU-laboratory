[CmdletBinding()]
param(
    [ValidateRange(0, 30)]
    [int]$CountdownSeconds = 5,

    [ValidateRange(5, 60)]
    [int]$TestSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ClawLabDwmAnimationNative
{
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    public static extern IntPtr GetWindowLongPtr(IntPtr window, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    public static extern IntPtr SetWindowLongPtr(IntPtr window, int index, IntPtr value);

    [DllImport("winmm.dll")]
    public static extern uint timeBeginPeriod(uint period);

    [DllImport("winmm.dll")]
    public static extern uint timeEndPeriod(uint period);
}
'@

$gwlExStyle = -20
$wsExTransparent = 0x00000020L
$wsExToolWindow = 0x00000080L
$wsExNoActivate = 0x08000000L
$timerResolutionActive = $false
$originalTitle = $Host.UI.RawUI.WindowTitle

try {
    $Host.UI.RawUI.WindowTitle = 'ClawLab - real DWM animation test'

    Write-Host 'ClawLab real DWM animation test' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'This creates a genuine animated 4x4 pixel DWM surface for 20 seconds.'
    Write-Host 'A tiny flashing square will appear in the lower-right corner. This is intentional.' -ForegroundColor Yellow
    Write-Host 'It does NOT modify the Intel LFC fix, VRR profile, EDID, registry, driver files, or scheduled tasks.'
    Write-Host ''
    Write-Host 'Keep the refresh-rate monitor visible. Observe the panel while the square is animated.'
    Write-Host ''

    for ($remaining = $CountdownSeconds; $remaining -gt 0; $remaining--) {
        Write-Host ("Starting in {0}..." -f $remaining)
        Start-Sleep -Seconds 1
    }

    $periodResult = [ClawLabDwmAnimationNative]::timeBeginPeriod(1)
    if ($periodResult -eq 0) {
        $timerResolutionActive = $true
    }

    $window = New-Object System.Windows.Window
    $window.Title = 'ClawLab DWM animation surface'
    $window.Width = 4
    $window.Height = 4
    $window.Left = [Math]::Max(0, [System.Windows.SystemParameters]::PrimaryScreenWidth - 6)
    $window.Top = [Math]::Max(0, [System.Windows.SystemParameters]::PrimaryScreenHeight - 6)
    $window.WindowStyle = [System.Windows.WindowStyle]::None
    $window.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $window.ShowInTaskbar = $false
    $window.ShowActivated = $false
    $window.Topmost = $true
    $window.AllowsTransparency = $true
    $window.Background = [System.Windows.Media.Brushes]::Black

    $window.Add_SourceInitialized({
        $handle = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
        $currentStyle = [ClawLabDwmAnimationNative]::GetWindowLongPtr($handle, $gwlExStyle).ToInt64()
        $newStyle = $currentStyle -bor $wsExTransparent -bor $wsExToolWindow -bor $wsExNoActivate
        [void][ClawLabDwmAnimationNative]::SetWindowLongPtr($handle, $gwlExStyle, [IntPtr]$newStyle)
    })

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $toggle = $false
    $renderCount = 0L
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(8)
    $timer.Add_Tick({
        if ($stopwatch.Elapsed.TotalSeconds -ge $TestSeconds) {
            $timer.Stop()
            $window.Close()
            return
        }

        $script:toggle = -not $script:toggle
        if ($script:toggle) {
            $window.Background = [System.Windows.Media.Brushes]::White
        }
        else {
            $window.Background = [System.Windows.Media.Brushes]::Black
        }
        $script:renderCount++
    })

    Write-Host ''
    Write-Host ("REAL DWM ANIMATION ACTIVE FOR {0} SECONDS" -f $TestSeconds) -ForegroundColor Cyan
    $timer.Start()
    [void]$window.ShowDialog()
    $stopwatch.Stop()

    Write-Host ("Animation stopped and surface removed. Requested updates: {0}." -f $renderCount) -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host ("TEST ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
finally {
    if ($timerResolutionActive) {
        [void][ClawLabDwmAnimationNative]::timeEndPeriod(1)
    }
    $Host.UI.RawUI.WindowTitle = $originalTitle
}
