[CmdletBinding()]
param(
    [ValidateRange(0, 30)]
    [int]$CountdownSeconds = 5,

    [ValidateRange(5, 60)]
    [int]$BoostSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ClawLabCompositorClock
{
    [DllImport("dcomp.dll", ExactSpelling = true)]
    public static extern int DCompositionBoostCompositorClock(
        [MarshalAs(UnmanagedType.Bool)] bool enable);
}
'@

function Assert-HResult {
    param(
        [Parameter(Mandatory)]
        [int]$Result,

        [Parameter(Mandatory)]
        [string]$Operation
    )

    if ($Result -lt 0) {
        $hex = '0x{0:X8}' -f ([uint32]$Result)
        throw "$Operation failed with HRESULT $hex."
    }
}

$originalTitle = $Host.UI.RawUI.WindowTitle
$boostEnabled = $false

try {
    $Host.UI.RawUI.WindowTitle = 'ClawLab - temporary compositor boost test'

    Write-Host 'ClawLab compositor boost test' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'This test does NOT change the Intel LFC fix, VRR profile, EDID, registry, driver files, or scheduled tasks.'
    Write-Host 'It asks the Windows compositor to use its high clock temporarily, then releases the request.'
    Write-Host ''
    Write-Host 'Keep your refresh-rate monitor visible. During the blue test period:' -ForegroundColor Yellow
    Write-Host '  1. Leave the desktop idle briefly.'
    Write-Host '  2. Move only the mouse pointer.'
    Write-Host '  3. Note whether the panel reaches its maximum refresh rate and the pointer feels smoother.'
    Write-Host ''

    for ($remaining = $CountdownSeconds; $remaining -gt 0; $remaining--) {
        Write-Host ("Starting in {0}..." -f $remaining)
        Start-Sleep -Seconds 1
    }

    $enableResult = [ClawLabCompositorClock]::DCompositionBoostCompositorClock($true)
    Assert-HResult -Result $enableResult -Operation 'DCompositionBoostCompositorClock(TRUE)'
    $boostEnabled = $true

    Write-Host ''
    Write-Host ("COMPOSITOR BOOST ACTIVE FOR {0} SECONDS" -f $BoostSeconds) -ForegroundColor Cyan
    for ($remaining = $BoostSeconds; $remaining -gt 0; $remaining--) {
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
    if ($boostEnabled) {
        $disableResult = [ClawLabCompositorClock]::DCompositionBoostCompositorClock($false)
        if ($disableResult -lt 0) {
            $disableHex = '0x{0:X8}' -f ([uint32]$disableResult)
            Write-Host ("WARNING: compositor boost release returned {0}. Closing this process also releases the request." -f $disableHex) -ForegroundColor Yellow
        }
        else {
            Write-Host ''
            Write-Host 'Compositor boost released. The system has returned to its previous behavior.' -ForegroundColor Green
        }
    }
    $Host.UI.RawUI.WindowTitle = $originalTitle
}
