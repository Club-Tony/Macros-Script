[CmdletBinding()]
param(
    [switch]$ValidateOnly,
    [Parameter(DontShow)]
    [int]$ShutdownProbeProcessId
)

$ErrorActionPreference = 'Stop'
$expectedCommit = '05226d8e50eb619bf4ce394f732536aa0cb7e9d7'
$toolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolsRoot)
$legacyRoot = Join-Path $repoRoot 'legacy\frozen-05226d8'
$manifestPath = Join-Path $legacyRoot 'manifest.json'
$scriptPath = Join-Path $legacyRoot 'Macros.ahk'
$ahkPath = 'C:\Program Files\AutoHotkey\v1.1.37.02\AutoHotkeyU64.exe'

function Assert-LegacyIdentity {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Frozen legacy manifest was not found: $manifestPath"
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.sourceCommit -ne $expectedCommit -or -not $manifest.immutable) {
        throw "Frozen legacy manifest identity mismatch. Expected immutable commit $expectedCommit."
    }
    foreach ($file in $manifest.files) {
        $relativePath = ([string]$file.path).Replace('/', [IO.Path]::DirectorySeparatorChar)
        $path = Join-Path $legacyRoot $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Frozen legacy runtime file is missing: $relativePath"
        }
        $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne ([string]$file.sha256).ToLowerInvariant()) {
            throw "Frozen legacy runtime hash mismatch for $relativePath."
        }
        if ((Get-Item -LiteralPath $path).Length -ne [long]$file.bytes) {
            throw "Frozen legacy runtime size mismatch for $relativePath."
        }
    }
    if (-not (Test-Path -LiteralPath $ahkPath -PathType Leaf)) {
        throw "Required AutoHotkey v1 runtime was not found: $ahkPath"
    }
    $version = (Get-Item -LiteralPath $ahkPath).VersionInfo.FileVersion
    if ($version -notmatch '^1\.1\.37\.(02|2)') {
        throw "Unexpected AutoHotkey runtime version '$version' at $ahkPath."
    }
}

function Get-OtherMacrosRuntimes {
    $escapedLegacy = [regex]::Escape($scriptPath)
    @(Get-CimInstance Win32_Process | Where-Object {
        if ($_.ProcessId -eq $PID) { return $false }
        $command = [string]$_.CommandLine
        ($_.Name -ieq 'MacrosApp.exe') -or
        (($_.Name -like 'AutoHotkey*.exe') -and
            $command -match '(?i)Macros(?:_v2)?\.ahk' -and
            $command -notmatch $escapedLegacy)
    })
}

function Request-MacrosAppShutdown {
    try {
        $pipeName = 'MacrosApp.Control.' + $env:USERNAME
        $pipe = [System.IO.Pipes.NamedPipeClientStream]::new('.', $pipeName,
            [System.IO.Pipes.PipeDirection]::InOut)
        try {
            $pipe.Connect(1200)
            $writer = [System.IO.StreamWriter]::new($pipe)
            $reader = [System.IO.StreamReader]::new($pipe)
            $writer.AutoFlush = $true
            $writer.WriteLine('shutdown')
            return $reader.ReadLine() -eq 'ok'
        }
        finally { $pipe.Dispose() }
    }
    catch { return $false }
}

function Request-AutoHotkeyShutdown([int]$ProcessId) {
    if (-not ('MacrosLegacy.AhkWindowControl' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace MacrosLegacy
{
    public static class AhkWindowControl
    {
        private const uint WmCommand = 0x0111;
        private const int AhkExitCommand = 65405;
        private delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassName(IntPtr window, StringBuilder className, int capacity);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

        public static bool RequestExit(int targetProcessId)
        {
            bool posted = false;
            EnumWindows((window, parameter) =>
            {
                uint processId;
                GetWindowThreadProcessId(window, out processId);
                if (processId != (uint)targetProcessId)
                    return true;

                var className = new StringBuilder(64);
                GetClassName(window, className, className.Capacity);
                if (className.ToString() == "AutoHotkey")
                    posted |= PostMessage(window, WmCommand, new IntPtr(AhkExitCommand), IntPtr.Zero);
                return true;
            }, IntPtr.Zero);
            return posted;
        }
    }
}
'@
    }

    if ($null -eq (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return $true }
    return [MacrosLegacy.AhkWindowControl]::RequestExit($ProcessId)
}

function Show-LegacyActiveNotification {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $notification = New-Object System.Windows.Forms.NotifyIcon
    try {
        $notification.Icon = [System.Drawing.SystemIcons]::Information
        $notification.Visible = $true
        $notification.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $notification.BalloonTipTitle = 'Macros legacy is active'
        $notification.BalloonTipText = "Frozen non-GUI Macros.ahk is running.`nPinned commit: 05226d8"
        $notification.ShowBalloonTip(5000)
        Start-Sleep -Milliseconds 5200
    }
    finally {
        $notification.Visible = $false
        $notification.Dispose()
    }
}

Assert-LegacyIdentity
if ($ShutdownProbeProcessId -gt 0) {
    if (-not (Request-AutoHotkeyShutdown -ProcessId $ShutdownProbeProcessId)) {
        throw "No hidden AutoHotkey control window was found for probe PID $ShutdownProbeProcessId."
    }
    return
}
if ($ValidateOnly) {
    [pscustomobject]@{
        Commit = $expectedCommit
        Manifest = $manifestPath
        Script = $scriptPath
        Runtime = $ahkPath
        RuntimeVersion = (Get-Item -LiteralPath $ahkPath).VersionInfo.FileVersion
    }
    return
}

$otherRuntimes = @(Get-OtherMacrosRuntimes)
if ($otherRuntimes.Count -gt 0) {
    Add-Type -AssemblyName System.Windows.Forms
    $names = ($otherRuntimes | ForEach-Object { '{0} (PID {1})' -f $_.Name, $_.ProcessId }) -join [Environment]::NewLine
    $choice = [System.Windows.Forms.MessageBox]::Show(
        "Another Macros runtime is active:$([Environment]::NewLine)$names$([Environment]::NewLine)$([Environment]::NewLine)Switch to the frozen legacy runtime?",
        'Switch Macros runtime', 'YesNo', 'Warning', 'Button2')
    if ($choice -ne 'Yes') { exit 2 }

    foreach ($runtime in $otherRuntimes) {
        if ($runtime.Name -ieq 'MacrosApp.exe') {
            [void](Request-MacrosAppShutdown)
        }
        else {
            [void](Request-AutoHotkeyShutdown -ProcessId $runtime.ProcessId)
        }
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        Start-Sleep -Milliseconds 100
        $remaining = @(Get-OtherMacrosRuntimes)
    } while ($remaining.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline)

    if ($remaining.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show(
            'The active runtime did not shut down cleanly. Legacy launch was cancelled; no process was force-killed.',
            'Macros switch cancelled', 'OK', 'Error') | Out-Null
        exit 3
    }
}

Start-Process -FilePath $ahkPath -ArgumentList ('"{0}"' -f $scriptPath) -WorkingDirectory $legacyRoot
Start-Sleep -Milliseconds 500
$escapedScriptPath = [regex]::Escape($scriptPath)
$legacyRuntime = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -like 'AutoHotkey*.exe' -and ([string]$_.CommandLine -match $escapedScriptPath)
} | Select-Object -First 1
if (-not $legacyRuntime) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        'The frozen AutoHotkey process did not remain active after launch.',
        'Macros legacy launch failed', 'OK', 'Error') | Out-Null
    exit 4
}
Show-LegacyActiveNotification
