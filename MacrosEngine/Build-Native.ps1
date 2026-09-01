[CmdletBinding()]
param(
    [string]$BuildDirectory
)

$ErrorActionPreference = 'Stop'
$engineRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path $engineRoot 'build-x64'
}
$cachePath = Join-Path $BuildDirectory 'CMakeCache.txt'

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw 'CMake is required to build MacrosEngine.'
}

if (-not (Test-Path -LiteralPath $cachePath)) {
    $gcc = Get-Command gcc -ErrorAction SilentlyContinue
    if (-not $gcc) {
        throw 'A MinGW GCC compiler is required for a fresh MacrosEngine build.'
    }

    & cmake -S $engineRoot -B $BuildDirectory -G 'MinGW Makefiles' "-DCMAKE_C_COMPILER=$($gcc.Source)"
    if ($LASTEXITCODE -ne 0) {
        throw "MacrosEngine CMake configure failed with exit code $LASTEXITCODE."
    }
}
else {
    & cmake -S $engineRoot -B $BuildDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "MacrosEngine CMake refresh failed with exit code $LASTEXITCODE."
    }
}

& cmake --build $BuildDirectory
if ($LASTEXITCODE -ne 0) {
    throw "MacrosEngine build failed with exit code $LASTEXITCODE."
}

$outputPath = Join-Path $BuildDirectory 'MacrosEngine.dll'
if (-not (Test-Path -LiteralPath $outputPath)) {
    throw "MacrosEngine build completed without producing $outputPath."
}

Write-Host "MacrosEngine ready: $outputPath"
