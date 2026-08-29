[CmdletBinding()]
param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

trap {
    if (-not $ValidateOnly) {
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

$legacyRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$launcher = Join-Path $legacyRoot 'Launch-LegacyMacros.ps1'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw "Legacy launcher was not found beside this installer: $launcher"
}

& $launcher -ValidateOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Legacy launcher validation failed.' }

$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'Macros - Frozen Legacy 05226d8.lnk'
$powerShell = Join-Path $PSHOME 'powershell.exe'
$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $launcher

if ($ValidateOnly) {
    [pscustomobject]@{ Shortcut = $shortcutPath; Target = $powerShell; Arguments = $arguments; WorkingDirectory = $legacyRoot }
    exit 0
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powerShell
$shortcut.Arguments = $arguments
$shortcut.WorkingDirectory = $legacyRoot
$shortcut.Description = 'Launch frozen non-GUI Macros.ahk at commit 05226d8'
$shortcut.IconLocation = "$powerShell,0"
$shortcut.Save()

$verified = $shell.CreateShortcut($shortcutPath)
if ($verified.TargetPath -ne $powerShell -or $verified.Arguments -ne $arguments -or $verified.WorkingDirectory -ne $legacyRoot) {
    throw "Shortcut verification failed: $shortcutPath"
}
Write-Host "Created and verified: $shortcutPath"
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show(
    "Created and verified:$([Environment]::NewLine)$shortcutPath",
    'Macros legacy shortcut installed',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
