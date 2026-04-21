using System.Diagnostics;
using System.Runtime.InteropServices;

namespace MacrosApp;

public sealed class RecordingInputHook : IDisposable
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WH_MOUSE_LL = 14;

    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;

    private const int WM_MOUSEMOVE = 0x0200;
    private const int WM_LBUTTONDOWN = 0x0201;
    private const int WM_LBUTTONUP = 0x0202;
    private const int WM_RBUTTONDOWN = 0x0204;
    private const int WM_RBUTTONUP = 0x0205;
    private const int WM_MBUTTONDOWN = 0x0207;
    private const int WM_MBUTTONUP = 0x0208;
    private const int WM_MOUSEWHEEL = 0x020A;
    private const int WM_XBUTTONDOWN = 0x020B;
    private const int WM_XBUTTONUP = 0x020C;
    private const int WM_MOUSEHWHEEL = 0x020E;

    private const uint LLKHF_LOWER_IL_INJECTED = 0x02;
    private const uint LLKHF_INJECTED = 0x10;
    private const uint LLMHF_INJECTED = 0x01;
    private const uint LLMHF_LOWER_IL_INJECTED = 0x02;

    private readonly HashSet<uint> _keysDown = new();
    private readonly HashSet<ushort> _mouseButtonsDown = new();
    private readonly LowLevelProc _keyboardProc;
    private readonly LowLevelProc _mouseProc;
    private static readonly bool AllowInjectedInput =
        string.Equals(Environment.GetEnvironmentVariable("MACROSAPP_ALLOW_INJECTED_INPUT"), "1", StringComparison.OrdinalIgnoreCase);

    private IntPtr _keyboardHook;
    private IntPtr _mouseHook;
    private bool _disposed;

    public event Action<ushort, ushort, bool>? KeyCaptured;
    public event Action<int, int>? MouseMoveCaptured;
    public event Action<ushort, bool>? MouseButtonCaptured;
    public event Action<int>? MouseWheelCaptured;

    public RecordingInputHook()
    {
        _keyboardProc = KeyboardHookCallback;
        _mouseProc = MouseHookCallback;
    }

    public bool Start()
    {
        if (_keyboardHook != IntPtr.Zero || _mouseHook != IntPtr.Zero)
            return true;

        IntPtr moduleHandle = GetCurrentModuleHandle();
        _keyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, _keyboardProc, moduleHandle, 0);
        _mouseHook = SetWindowsHookEx(WH_MOUSE_LL, _mouseProc, moduleHandle, 0);

        if (_keyboardHook != IntPtr.Zero && _mouseHook != IntPtr.Zero)
            return true;

        Stop();
        return false;
    }

    public void Stop()
    {
        if (_keyboardHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_keyboardHook);
            _keyboardHook = IntPtr.Zero;
        }

        if (_mouseHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_mouseHook);
            _mouseHook = IntPtr.Zero;
        }

        _keysDown.Clear();
        _mouseButtonsDown.Clear();
    }

    private IntPtr KeyboardHookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int message = unchecked((int)wParam.ToInt64());
            var data = Marshal.PtrToStructure<KbdLlHookStruct>(lParam);
            bool injected = (data.flags & (LLKHF_INJECTED | LLKHF_LOWER_IL_INJECTED)) != 0;

            if (!injected || AllowInjectedInput)
            {
                if (message == WM_KEYDOWN || message == WM_SYSKEYDOWN)
                {
                    if (_keysDown.Add(data.vkCode))
                        KeyCaptured?.Invoke((ushort)data.vkCode, (ushort)data.scanCode, true);
                }
                else if (message == WM_KEYUP || message == WM_SYSKEYUP)
                {
                    if (_keysDown.Remove(data.vkCode))
                        KeyCaptured?.Invoke((ushort)data.vkCode, (ushort)data.scanCode, false);
                }
            }
        }

        return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
    }

    private IntPtr MouseHookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int message = unchecked((int)wParam.ToInt64());
            var data = Marshal.PtrToStructure<MsLlHookStruct>(lParam);
            bool injected = (data.flags & (LLMHF_INJECTED | LLMHF_LOWER_IL_INJECTED)) != 0;

            if (!injected || AllowInjectedInput)
            {
                switch (message)
                {
                    case WM_MOUSEMOVE:
                        MouseMoveCaptured?.Invoke(data.pt.x, data.pt.y);
                        break;
                    case WM_LBUTTONDOWN:
                        EmitMouseButton(1, true);
                        break;
                    case WM_LBUTTONUP:
                        EmitMouseButton(1, false);
                        break;
                    case WM_RBUTTONDOWN:
                        EmitMouseButton(2, true);
                        break;
                    case WM_RBUTTONUP:
                        EmitMouseButton(2, false);
                        break;
                    case WM_MBUTTONDOWN:
                        EmitMouseButton(3, true);
                        break;
                    case WM_MBUTTONUP:
                        EmitMouseButton(3, false);
                        break;
                    case WM_XBUTTONDOWN:
                        EmitMouseButton(GetXButtonId(data.mouseData), true);
                        break;
                    case WM_XBUTTONUP:
                        EmitMouseButton(GetXButtonId(data.mouseData), false);
                        break;
                    case WM_MOUSEWHEEL:
                    {
                        short delta = GetWheelDelta(data.mouseData);
                        if (delta != 0)
                            MouseWheelCaptured?.Invoke(delta);
                        break;
                    }
                    case WM_MOUSEHWHEEL:
                    {
                        short delta = GetWheelDelta(data.mouseData);
                        if (delta != 0)
                            MouseWheelCaptured?.Invoke(delta > 0 ? 1 : -1);
                        break;
                    }
                }
            }
        }

        return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
    }

    private void EmitMouseButton(ushort button, bool down)
    {
        if (button == 0)
            return;

        if (down)
        {
            if (_mouseButtonsDown.Add(button))
                MouseButtonCaptured?.Invoke(button, true);
            return;
        }

        if (_mouseButtonsDown.Remove(button))
            MouseButtonCaptured?.Invoke(button, false);
    }

    private static ushort GetXButtonId(uint mouseData)
    {
        ushort button = (ushort)((mouseData >> 16) & 0xFFFF);
        return button switch
        {
            1 => (ushort)4,
            2 => (ushort)5,
            _ => (ushort)0
        };
    }

    private static short GetWheelDelta(uint mouseData)
    {
        return unchecked((short)((mouseData >> 16) & 0xFFFF));
    }

    private static IntPtr GetCurrentModuleHandle()
    {
        using var process = Process.GetCurrentProcess();
        string? moduleName = process.MainModule?.ModuleName;
        return string.IsNullOrEmpty(moduleName) ? IntPtr.Zero : GetModuleHandle(moduleName);
    }

    public void Dispose()
    {
        if (_disposed)
            return;

        Stop();
        _disposed = true;
        GC.SuppressFinalize(this);
    }

    private delegate IntPtr LowLevelProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct PointStruct
    {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KbdLlHookStruct
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MsLlHookStruct
    {
        public PointStruct pt;
        public uint mouseData;
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
