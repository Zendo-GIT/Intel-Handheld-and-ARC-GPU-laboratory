[CmdletBinding()]
param(
    [ValidateRange(0, 30)]
    [int]$CountdownSeconds = 5,

    [ValidateRange(5, 60)]
    [int]$TestSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ClawLabMouseTrails
{
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SystemParametersInfo(
        uint action,
        uint parameter,
        ref uint value,
        uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SystemParametersInfo(
        uint action,
        uint parameter,
        IntPtr value,
        uint flags);
}
'@

$spiGetMouseTrails = [uint32]0x005E
$spiSetMouseTrails = [uint32]0x005D
$originalTrails = [uint32]0
$originalStateRead = $false
$temporaryStateApplied = $false
$originalTitle = $Host.UI.RawUI.WindowTitle

function Set-MouseTrails {
    param([Parameter(Mandatory)][uint32]$Count)

    $ok = [ClawLabMouseTrails]::SystemParametersInfo(
        $spiSetMouseTrails,
        $Count,
        [IntPtr]::Zero,
        [uint32]0)
    if (-not $ok) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "SystemParametersInfo(SPI_SETMOUSETRAILS) failed with Win32 error $errorCode."
    }
}

try {
    $Host.UI.RawUI.WindowTitle = 'ClawLab - temporary software-composed cursor test'

    $getOk = [ClawLabMouseTrails]::SystemParametersInfo(
        $spiGetMouseTrails,
        [uint32]0,
        [ref]$originalTrails,
        [uint32]0)
    if (-not $getOk) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "SystemParametersInfo(SPI_GETMOUSETRAILS) failed with Win32 error $errorCode."
    }
    $originalStateRead = $true

    Write-Host 'ClawLab software-composed cursor test' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'This test changes only the Windows mouse-trails session setting and restores it automatically.'
    Write-Host 'It does NOT modify the Intel LFC fix, VRR profile, EDID, registry, driver files, or scheduled tasks.'
    Write-Host ''
    Write-Host 'A very short cursor trail will be visible during the test. This is intentional.' -ForegroundColor Yellow
    Write-Host 'Keep the refresh-rate monitor visible and move only the mouse during the blue period.'
    Write-Host ''

    for ($remaining = $CountdownSeconds; $remaining -gt 0; $remaining--) {
        Write-Host ("Starting in {0}..." -f $remaining)
        Start-Sleep -Seconds 1
    }

    Set-MouseTrails -Count ([uint32]2)
    $temporaryStateApplied = $true

    Write-Host ''
    Write-Host ("SOFTWARE-COMPOSED CURSOR TEST ACTIVE FOR {0} SECONDS" -f $TestSeconds) -ForegroundColor Cyan
    for ($remaining = $TestSeconds; $remaining -gt 0; $remaining--) {
        Write-Host ("  {0} second(s) remaining" -f $remaining)
        Start-Sleep -Seconds 1
    }
}
catch {
    Write-Host ''
    Write-Host ("TEST ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
finally {
    if ($temporaryStateApplied -and $originalStateRead) {
        try {
            Set-MouseTrails -Count $originalTrails
            Write-Host ''
            Write-Host ("Original Windows mouse setting restored (MouseTrails={0})." -f $originalTrails) -ForegroundColor Green
        }
        catch {
            Write-Host ("WARNING: automatic mouse-setting restoration failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
            Write-Host 'Open Windows mouse settings and disable pointer trails manually.' -ForegroundColor Yellow
        }
    }
    $Host.UI.RawUI.WindowTitle = $originalTitle
}

