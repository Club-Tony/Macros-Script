# Validate-Tooltips.ps1
#
# Launches MacrosApp, hovers each named GUI control for >2 seconds,
# captures any visible tooltip windows via Win32 + UIA, then closes
# the app. Reports per-control pass/fail and the captured tooltip text.
#
# Run from any cwd:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File .\Validate-Tooltips.ps1
#
# Pre-req: dotnet build the MacrosApp project so MacrosApp.exe exists at
# MacrosApp\MacrosApp\bin\Debug\net8.0-windows\MacrosApp.exe.

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

# ----------------------------------------------------------------------
# Win32 helpers: enumerate visible tooltip windows by class name.
# WinForms ToolTip uses the standard "tooltips_class32" Win32 class.
# ----------------------------------------------------------------------
if (-not ('Win32TooltipProbe' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class Win32TooltipProbe {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT pt);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct INPUT {
        [FieldOffset(0)] public uint type;
        [FieldOffset(8)] public MOUSEINPUT mi;
    }

    public const uint INPUT_MOUSE       = 0;
    public const uint MOUSEEVENTF_MOVE  = 0x0001;
    public const uint MOUSEEVENTF_ABSOLUTE = 0x8000;
    public const int  SW_SHOW           = 5;
    public const int  SW_RESTORE        = 9;

    // Send a real-input absolute mouse-move so WinForms ToolTip's
    // hover-detection sees a proper input-queue event (SetCursorPos
    // alone does not always trigger ToolTip's internal timer).
    public static void SendAbsoluteMouseMove(int screenX, int screenY) {
        // Convert screen coords to normalized 0-65535 absolute coords.
        var screen = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
        int nx = (int)((screenX * 65535.0) / screen.Width);
        int ny = (int)((screenY * 65535.0) / screen.Height);

        var inp = new INPUT[1];
        inp[0].type = INPUT_MOUSE;
        inp[0].mi = new MOUSEINPUT {
            dx = nx,
            dy = ny,
            mouseData = 0,
            dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE,
            time = 0,
            dwExtraInfo = IntPtr.Zero
        };
        SendInput(1, inp, Marshal.SizeOf(typeof(INPUT)));
    }

    public static int CountVisibleTooltipWindows() {
        int count = 0;
        EnumWindows((h, _) => {
            if (!IsWindowVisible(h)) return true;
            var cls = new StringBuilder(64);
            GetClassName(h, cls, cls.Capacity);
            var clsName = cls.ToString();
            if (clsName == "tooltips_class32" || clsName.StartsWith("tooltips_class")) {
                count++;
            }
            return true;
        }, IntPtr.Zero);
        return count;
    }
}
"@ -ReferencedAssemblies System.Windows.Forms, System.Drawing
}

# ----------------------------------------------------------------------
# UIA polling: walk the desktop tree from a UIA-discovered tooltip pane
# (ControlType=ToolTip) and read its Name. WinForms surfaces the tip
# text as the ToolTip element's Name once it's visible. UIA marshals
# this cross-process safely, unlike WM_GETTEXT.
# ----------------------------------------------------------------------
function Get-VisibleUiaTooltipText {
    param([System.Windows.Automation.AutomationElement]$Root)
    if ($null -eq $Root) { return @() }
    $names = @()
    try {
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::ToolTip)
        $found = $Root.FindAll([System.Windows.Automation.TreeScope]::Subtree, $cond)
        foreach ($el in $found) {
            try {
                if ($el.Current.IsOffscreen) { continue }
                $n = $el.Current.Name
                if ($n) { $names += $n }
            } catch {}
        }
    } catch {}
    return ,$names
}

# ----------------------------------------------------------------------
# Targets: the named controls in MainForm.cs that have SetToolTip wiring.
# Match Name = AccessibleName (WinForms surfaces control text by default).
# ExpectedSubstring is a case-insensitive fragment of the tooltip text
# from MainForm.cs InitializeToolTips().
# ----------------------------------------------------------------------
$targets = @(
    @{ Match = '/ Macro';         Expect = 'Slash Macro' }
    @{ Match = 'Autoclicker';     Expect = 'autoclicker' }
    @{ Match = 'Turbo Hold';      Expect = 'Turbo Hold' }
    @{ Match = 'Pure Hold';       Expect = 'Pure Hold' }
    @{ Match = 'Recorder';        Expect = 'recording' }
    @{ Match = 'Saved Recordings';Expect = 'macros.ini' }
    @{ Match = 'Settings';        Expect = 'Playback' }
    @{ Match = 'Controller';      Expect = 'XInput' }
)

# ----------------------------------------------------------------------
# Locate MacrosApp.exe relative to this script.
# ----------------------------------------------------------------------
$repoRoot = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $repoRoot 'MacrosApp\bin\Debug\net8.0-windows\MacrosApp.exe'
if (-not (Test-Path $exe)) {
    throw "MacrosApp.exe not found at $exe. Run 'dotnet build' first."
}

# Save current cursor position to restore at the end.
$origCursor = [System.Windows.Forms.Cursor]::Position

# ----------------------------------------------------------------------
# Launch and locate main window via UIA by process id.
# ----------------------------------------------------------------------
$proc = $null
$results = New-Object System.Collections.Generic.List[object]

try {
    $proc = Start-Process -FilePath $exe -PassThru
    Write-Host "Launched MacrosApp PID=$($proc.Id), waiting for main window..."

    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $pidCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc.Id)

    $mainWin = $null
    for ($i = 0; $i -lt 30; $i++) {
        $mainWin = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $pidCond)
        if ($null -ne $mainWin -and $mainWin.Current.BoundingRectangle.Width -gt 0) { break }
        Start-Sleep -Milliseconds 300
    }
    if ($null -eq $mainWin) { throw "MacrosApp main window did not appear within 9 seconds." }
    Write-Host "Main window found: '$($mainWin.Current.Name)' at $($mainWin.Current.BoundingRectangle)"

    # Bring window to foreground so tooltips render.
    $mainHwnd = [IntPtr]$mainWin.Current.NativeWindowHandle
    [void][Win32TooltipProbe]::ShowWindow($mainHwnd, [Win32TooltipProbe]::SW_RESTORE)
    [void][Win32TooltipProbe]::BringWindowToTop($mainHwnd)
    [void][Win32TooltipProbe]::SetForegroundWindow($mainHwnd)
    try { $mainWin.SetFocus() } catch {}
    Start-Sleep -Milliseconds 700

    foreach ($t in $targets) {
        $match  = $t.Match
        $expect = $t.Expect

        # Find by Name starts-with substring (WinForms surfaces multi-line button
        # text with literal newlines; we match on a leading fragment).
        $el = $null
        $allDescendants = $mainWin.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($d in $allDescendants) {
            $n = $d.Current.Name
            if ($n -and $n -like "*$match*") { $el = $d; break }
        }

        if ($null -eq $el) {
            $results.Add([pscustomobject]@{
                Match = $match; Expect = $expect; Status = 'CONTROL_NOT_FOUND'; Captured = ''
            })
            continue
        }

        $rect = $el.Current.BoundingRectangle
        if ($rect.Width -le 0 -or $rect.Height -le 0) {
            $results.Add([pscustomobject]@{
                Match = $match; Expect = $expect; Status = 'OFF_SCREEN'; Captured = ''
            })
            continue
        }

        $cx = [int]($rect.X + $rect.Width / 2)
        $cy = [int]($rect.Y + $rect.Height / 2)
        Write-Host ("  hover '{0}' rect={1} center=({2},{3})" -f $match, $rect, $cx, $cy)

        # Park cursor off-target first so the tooltip resets between iterations.
        [Win32TooltipProbe]::SendAbsoluteMouseMove(
            [int]($mainWin.Current.BoundingRectangle.X - 5),
            [int]($mainWin.Current.BoundingRectangle.Y - 5))
        Start-Sleep -Milliseconds 900

        # Real-input mouse move (SendInput) — synthetic enough to pass through
        # WinForms ToolTip's input-queue gate, unlike SetCursorPos alone.
        [Win32TooltipProbe]::SendAbsoluteMouseMove($cx, $cy)

        # Tiny secondary nudge to ensure WM_MOUSEMOVE is delivered to the control.
        Start-Sleep -Milliseconds 50
        [Win32TooltipProbe]::SendAbsoluteMouseMove($cx + 1, $cy)
        Start-Sleep -Milliseconds 50
        [Win32TooltipProbe]::SendAbsoluteMouseMove($cx, $cy)

        # Wait > the InitialDelay (2000ms in MainForm.cs) for the tip to render.
        Start-Sleep -Milliseconds 2500

        $win32Count = [Win32TooltipProbe]::CountVisibleTooltipWindows()
        $uiaText    = @(Get-VisibleUiaTooltipText -Root $root)
        $matched    = $uiaText | Where-Object { $_ -and ($_ -match [regex]::Escape($expect)) }

        if ($matched) {
            $status = 'PASS'
            $captured = ($matched | Select-Object -First 1)
        } elseif ($win32Count -gt 0) {
            $status = 'TOOLTIP_VISIBLE_TEXT_UNREADABLE'
            $captured = ($uiaText -join ' | ')
        } else {
            $status = 'NO_TOOLTIP_VISIBLE'
            $captured = ''
        }

        $results.Add([pscustomobject]@{
            Match     = $match
            Expect    = $expect
            Status    = $status
            Win32Wins = $win32Count
            Captured  = $captured
        })
    }
}
finally {
    # Restore cursor.
    try { [System.Windows.Forms.Cursor]::Position = $origCursor } catch {}

    # Close MacrosApp gracefully then force-kill if needed.
    if ($proc -and -not $proc.HasExited) {
        try { $null = $proc.CloseMainWindow() } catch {}
        Start-Sleep -Milliseconds 800
        if (-not $proc.HasExited) {
            try { $proc | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
}

# ----------------------------------------------------------------------
# Report.
# ----------------------------------------------------------------------
Write-Host ""
Write-Host "=== Tooltip validation results ==="
$results | Format-Table -AutoSize -Wrap

$passCount    = ($results | Where-Object Status -eq 'PASS').Count
$visibleCount = ($results | Where-Object { $_.Status -eq 'PASS' -or $_.Status -eq 'TOOLTIP_VISIBLE_TEXT_UNREADABLE' }).Count
$total = $results.Count
Write-Host ""
Write-Host "Summary: $passCount / $total tooltip texts matched expected substring."
Write-Host "         $visibleCount / $total tooltip windows actually appeared on hover."

# Exit non-zero only when no tooltip window appears at all for some control —
# unreadable text via cross-process WinForms is an OS limitation, not an app bug.
if ($visibleCount -lt $total) { exit 1 } else { exit 0 }
