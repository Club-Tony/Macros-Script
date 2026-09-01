[CmdletBinding()]
param(
    [switch]$ValidateOnly,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

trap {
    if (-not $ValidateOnly -and -not $Quiet) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'Macros legacy shortcut - installation failed',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
    Write-Error $_
    exit 1
}

$toolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolsRoot)
$runtimeRoot = Join-Path $repoRoot 'legacy\frozen-05226d8'
$launcher = Join-Path $toolsRoot 'Launch-LegacyMacros.ps1'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw "Legacy launcher was not found beside this installer: $launcher"
}

& $launcher -ValidateOnly | Out-Null

$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'Macros - Frozen Legacy 05226d8.lnk'
$powerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $powerShell -PathType Leaf)) {
    throw "Windows PowerShell was not found: $powerShell"
}
$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $launcher

if ($ValidateOnly) {
    [pscustomobject]@{ Shortcut = $shortcutPath; Target = $powerShell; Arguments = $arguments; WorkingDirectory = $runtimeRoot }
    return
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powerShell
$shortcut.Arguments = $arguments
$shortcut.WorkingDirectory = $runtimeRoot
$shortcut.Description = 'Launch frozen non-GUI Macros.ahk at commit 05226d8'
$shortcut.IconLocation = "$powerShell,0"
$shortcut.Save()

$verified = $shell.CreateShortcut($shortcutPath)
if ($verified.TargetPath -ne $powerShell -or $verified.Arguments -ne $arguments -or $verified.WorkingDirectory -ne $runtimeRoot) {
    throw "Shortcut verification failed: $shortcutPath"
}
Write-Host "Created and verified: $shortcutPath"
if (-not $Quiet) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Created and verified:$([Environment]::NewLine)$shortcutPath",
        'Macros legacy shortcut installed',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}
