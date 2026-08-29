using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

namespace MacrosApp;

internal static partial class LegacyRuntimeGuard
{
    private const uint WmCommand = 0x0111;
    private const int AhkExitCommand = 65405;
    private static readonly TimeSpan ShutdownTimeout = TimeSpan.FromSeconds(5);

    public static bool AllowNativeStartup()
    {
        int[] runtimes = FindMacrosAutoHotkeyProcesses();
        if (runtimes.Length == 0)
            return true;

        string processes = string.Join(Environment.NewLine, runtimes.Select(pid => $"AutoHotkey (PID {pid})"));
        DialogResult choice = MessageBox.Show(
            $"A legacy Macros runtime is active:{Environment.NewLine}{processes}{Environment.NewLine}{Environment.NewLine}" +
            "Switch to the native Macros runtime?",
            "Switch Macros runtime",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2);
        if (choice != DialogResult.Yes)
            return false;

        foreach (int processId in runtimes)
            RequestGracefulExit(processId);

        Stopwatch wait = Stopwatch.StartNew();
        while (wait.Elapsed < ShutdownTimeout)
        {
            if (FindMacrosAutoHotkeyProcesses().Length == 0)
                return true;
            Thread.Sleep(100);
        }

        MessageBox.Show(
            "The legacy runtime did not shut down cleanly. Native startup was cancelled; no process was force-killed.",
            "Macros switch cancelled",
            MessageBoxButtons.OK,
            MessageBoxIcon.Error);
        return false;
    }

    private static int[] FindMacrosAutoHotkeyProcesses()
    {
        var processIds = new HashSet<int>();
        EnumWindows((window, parameter) =>
        {
            var className = new StringBuilder(64);
            if (GetClassName(window, className, className.Capacity) == 0 || className.ToString() != "AutoHotkey")
                return true;

            int titleLength = GetWindowTextLength(window);
            var title = new StringBuilder(Math.Max(titleLength + 1, 256));
            _ = GetWindowText(window, title, title.Capacity);
            if (!MacrosScriptTitle().IsMatch(title.ToString()))
                return true;

            _ = GetWindowThreadProcessId(window, out uint processId);
            if (processId == 0)
                return true;

            try
            {
                using Process process = Process.GetProcessById((int)processId);
                if (process.ProcessName.StartsWith("AutoHotkey", StringComparison.OrdinalIgnoreCase))
                    processIds.Add((int)processId);
            }
            catch (ArgumentException) { }
            catch (InvalidOperationException) { }
            return true;
        }, IntPtr.Zero);
        return processIds.OrderBy(id => id).ToArray();
    }

    private static void RequestGracefulExit(int targetProcessId)
    {
        EnumWindows((window, parameter) =>
        {
            _ = GetWindowThreadProcessId(window, out uint processId);
            if (processId != (uint)targetProcessId)
                return true;

            var className = new StringBuilder(64);
            if (GetClassName(window, className, className.Capacity) > 0 && className.ToString() == "AutoHotkey")
                _ = PostMessage(window, WmCommand, new IntPtr(AhkExitCommand), IntPtr.Zero);
            return true;
        }, IntPtr.Zero);
    }

    [GeneratedRegex(@"(?i)(?:^|[\\/])Macros(?:_v2)?\.ahk(?:\s|$)")]
    private static partial Regex MacrosScriptTitle();

    private delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr window, StringBuilder className, int capacity);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr window, StringBuilder text, int capacity);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextLength(IntPtr window);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
}
