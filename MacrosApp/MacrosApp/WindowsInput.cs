using MacrosApp.Models;
using System.Runtime.InteropServices;

namespace MacrosApp;

internal static class WindowsInput
{
    private const uint INPUT_MOUSE = 0;
    private const uint INPUT_KEYBOARD = 1;
    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;
    private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint KEYEVENTF_SCANCODE = 0x0008;

    public static bool SendLeftClick(SendModeType sendMode)
    {
        if (ResolveSendMode(sendMode) == SendModeType.Event)
        {
            mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
            mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
            return true;
        }

        var inputs = new[]
        {
            CreateMouseInput(MOUSEEVENTF_LEFTDOWN),
            CreateMouseInput(MOUSEEVENTF_LEFTUP)
        };

        return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>()) == inputs.Length;
    }

    public static bool SendKeyDown(Keys key, SendModeType sendMode)
    {
        if (ResolveSendMode(sendMode) == SendModeType.Event)
            return SendKeyEvent(key, keyUp: false);

        var input = CreateKeyboardInput(key, keyUp: false);
        return SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>()) == 1;
    }

    public static bool SendKeyUp(Keys key, SendModeType sendMode)
    {
        if (ResolveSendMode(sendMode) == SendModeType.Event)
            return SendKeyEvent(key, keyUp: true);

        var input = CreateKeyboardInput(key, keyUp: true);
        return SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>()) == 1;
    }

    public static bool SendKeyPress(Keys key, SendModeType sendMode)
    {
        if (ResolveSendMode(sendMode) == SendModeType.Event)
            return SendKeyEvent(key, keyUp: false) && SendKeyEvent(key, keyUp: true);

        var inputs = new[]
        {
            CreateKeyboardInput(key, keyUp: false),
            CreateKeyboardInput(key, keyUp: true)
        };

        return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>()) == inputs.Length;
    }

    // True journal-playback SendPlay is unsupported on modern Windows, so direct Play mode falls back to SendInput.
    private static SendModeType ResolveSendMode(SendModeType sendMode)
    {
        return sendMode == SendModeType.Play ? SendModeType.Input : sendMode;
    }

    private static bool SendKeyEvent(Keys key, bool keyUp)
    {
        byte virtualKey = (byte)(key & Keys.KeyCode);
        byte scanCode = (byte)MapVirtualKey(virtualKey, 0);
        uint flags = keyUp ? KEYEVENTF_KEYUP : 0;

        if (IsExtendedKey((Keys)(key & Keys.KeyCode)))
            flags |= KEYEVENTF_EXTENDEDKEY;

        keybd_event(virtualKey, scanCode, flags, UIntPtr.Zero);
        return true;
    }

    private static INPUT CreateMouseInput(uint flags)
    {
        return new INPUT
        {
            type = INPUT_MOUSE,
            U = new InputUnion
            {
                mi = new MOUSEINPUT
                {
                    dwFlags = flags
                }
            }
        };
    }

    private static INPUT CreateKeyboardInput(Keys key, bool keyUp)
    {
        ushort virtualKey = (ushort)(key & Keys.KeyCode);
        uint scanCode = MapVirtualKey(virtualKey, 0);
        uint flags = keyUp ? KEYEVENTF_KEYUP : 0;

        if (scanCode != 0)
        {
            flags |= KEYEVENTF_SCANCODE;
            virtualKey = 0;
        }

        if (IsExtendedKey((Keys)(key & Keys.KeyCode)))
            flags |= KEYEVENTF_EXTENDEDKEY;

        return new INPUT
        {
            type = INPUT_KEYBOARD,
            U = new InputUnion
            {
                ki = new KEYBDINPUT
                {
                    wVk = virtualKey,
                    wScan = (ushort)scanCode,
                    dwFlags = flags
                }
            }
        };
    }

    private static bool IsExtendedKey(Keys key)
    {
        return key switch
        {
            Keys.Insert or
            Keys.Delete or
            Keys.Home or
            Keys.End or
            Keys.PageUp or
            Keys.PageDown or
            Keys.Up or
            Keys.Down or
            Keys.Left or
            Keys.Right or
            Keys.NumLock or
            Keys.RControlKey or
            Keys.RMenu or
            Keys.RWin or
            Keys.LWin or
            Keys.Apps or
            Keys.PrintScreen or
            Keys.Divide => true,
            _ => false
        };
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)]
        public MOUSEINPUT mi;

        [FieldOffset(0)]
        public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    private static extern uint MapVirtualKey(uint uCode, uint uMapType);
}
