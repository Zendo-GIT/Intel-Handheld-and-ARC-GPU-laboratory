[CmdletBinding()]
param(
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot '..\..'
}

$compilerCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($compiler)) {
    throw 'The inbox .NET Framework C# compiler was not found.'
}

$source = Join-Path $PSScriptRoot 'ClawLabCursorRefreshHelperWpf.cs'
$wpfReferenceRoot = Join-Path (Split-Path -Parent $compiler) 'WPF'
$systemXamlReference = Join-Path (Split-Path -Parent $compiler) 'System.Xaml.dll'
$windowsBaseReference = Join-Path $wpfReferenceRoot 'WindowsBase.dll'
$presentationCoreReference = Join-Path $wpfReferenceRoot 'PresentationCore.dll'
$presentationFrameworkReference = Join-Path $wpfReferenceRoot 'PresentationFramework.dll'
foreach ($reference in @($systemXamlReference, $windowsBaseReference, $presentationCoreReference, $presentationFrameworkReference)) {
    if (-not (Test-Path -LiteralPath $reference -PathType Leaf)) {
        throw "Required inbox WPF reference was not found: $reference"
    }
}
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$output = Join-Path $outputRoot 'ClawLab-Cursor-Refresh-Helper.exe'

$arguments = @(
    '/nologo',
    '/target:winexe',
    '/optimize+',
    '/platform:anycpu',
    "/out:$output",
    '/reference:System.dll',
    '/reference:System.Drawing.dll',
    "/reference:$systemXamlReference",
    "/reference:$windowsBaseReference",
    "/reference:$presentationCoreReference",
    "/reference:$presentationFrameworkReference",
    $source
)

& $compiler @arguments
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output -PathType Leaf)) {
    throw "Cursor Refresh Helper compilation failed with exit code $LASTEXITCODE."
}

$hash = Get-FileHash -LiteralPath $output -Algorithm SHA256
[pscustomobject]@{
    Output = $output
    SHA256 = $hash.Hash
    Compiler = $compiler
}
