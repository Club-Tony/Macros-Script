using System.Diagnostics;
using System.Runtime.InteropServices;

namespace MacrosApp;

public sealed class KeyboardToggleBinding : IDisposable
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;
    private const uint LLKHF_LOWER_IL_INJECTED = 0x02;
    private const uint LLKHF_INJECTED = 0x10;

    private readonly Keys _targetKey;
    private readonly Action _onToggle;
    private readonly LowLevelProc _keyboardProc;
    private IntPtr _keyboardHook;
    private bool _keyDown;
    private bool _disposed;

    public KeyboardToggleBinding(Keys targetKey, Action onToggle)
    {
        _targetKey = targetKey & Keys.KeyCode;
        _onToggle = onToggle;
        _keyboardProc = KeyboardHookCallback;
    }

    public bool Start()
    {
        if (_keyboardHook != IntPtr.Zero)
            return true;

        IntPtr moduleHandle = GetCurrentModuleHandle();
        _keyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, _keyboardProc, moduleHandle, 0);
        return _keyboardHook != IntPtr.Zero;
    }

    public void Stop()
    {
        if (_keyboardHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_keyboardHook);
            _keyboardHook = IntPtr.Zero;
        }

        _keyDown = false;
    }

    public void Dispose()
    {
        if (_disposed)
            return;

        Stop();
        _disposed = true;
        GC.SuppressFinalize(this);
    }

    private IntPtr KeyboardHookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0)
            return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);

        int message = unchecked((int)wParam.ToInt64());
        var data = Marshal.PtrToStructure<KbdLlHookStruct>(lParam);
        bool injected = (data.flags & (LLKHF_INJECTED | LLKHF_LOWER_IL_INJECTED)) != 0;

        if (injected || !MatchesKey((Keys)data.vkCode))
            return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);

        if (message == WM_KEYDOWN || message == WM_SYSKEYDOWN)
        {
            if (!_keyDown)
            {
                _keyDown = true;
                try
                {
                    _onToggle();
                }
                catch
                {
                    // Keep the hook stable even if UI handling fails.
                }
            }

            return (IntPtr)1;
        }

        if (message == WM_KEYUP || message == WM_SYSKEYUP)
        {
            _keyDown = false;
            return (IntPtr)1;
        }

        return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
    }

    private bool MatchesKey(Keys incomingKey)
    {
        Keys normalizedIncoming = incomingKey & Keys.KeyCode;
        if (normalizedIncoming == _targetKey)
            return true;

        return _targetKey switch
        {
            Keys.ShiftKey => normalizedIncoming is Keys.LShiftKey or Keys.RShiftKey,
            Keys.ControlKey => normalizedIncoming is Keys.LControlKey or Keys.RControlKey,
            Keys.Menu => normalizedIncoming is Keys.LMenu or Keys.RMenu,
            _ => false
        };
    }

    private static IntPtr GetCurrentModuleHandle()
    {
        using var process = Process.GetCurrentProcess();
        string? moduleName = process.MainModule?.ModuleName;
        return string.IsNullOrEmpty(moduleName) ? IntPtr.Zero : GetModuleHandle(moduleName);
    }

    private delegate IntPtr LowLevelProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct KbdLlHookStruct
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);
}
