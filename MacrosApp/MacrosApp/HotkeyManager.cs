using System.Runtime.InteropServices;

namespace MacrosApp;

public class HotkeyManager : IDisposable
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    // Modifier flags
    private const uint MOD_NONE = 0x0000;
    private const uint MOD_ALT = 0x0001;
    private const uint MOD_CONTROL = 0x0002;
    private const uint MOD_SHIFT = 0x0004;
    private const uint MOD_NOREPEAT = 0x4000;

    // Virtual key codes
    private const uint VK_F1 = 0x70;
    private const uint VK_F2 = 0x71;
    private const uint VK_F3 = 0x72;
    private const uint VK_F4 = 0x73;
    private const uint VK_F5 = 0x74;
    private const uint VK_F12 = 0x7B;
    private const uint VK_ESCAPE = 0x1B;
    private const uint VK_Z = 0x5A;

    // WM_HOTKEY
    public const int WM_HOTKEY = 0x0312;

    // Hotkey IDs
    public const int HOTKEY_SLASH_MACRO = 1;     // F1
    public const int HOTKEY_AUTOCLICKER = 2;     // F2
    public const int HOTKEY_TURBO_HOLD = 3;      // F3
    public const int HOTKEY_PURE_HOLD = 4;       // F4
    public const int HOTKEY_RECORDER = 5;        // F5
    public const int HOTKEY_PLAYBACK = 6;        // F12
    public const int HOTKEY_SHOW_HIDE = 7;       // Ctrl+Shift+Alt+Z
    public const int HOTKEY_CANCEL = 8;          // Escape

    private readonly IntPtr _windowHandle;
    private readonly List<int> _registeredIds = new();
    private bool _disposed;

    public event Action<int>? HotkeyPressed;

    public HotkeyManager(IntPtr windowHandle)
    {
        _windowHandle = windowHandle;
    }

    public void RegisterAll()
    {
        Register(HOTKEY_SLASH_MACRO, MOD_NOREPEAT, VK_F1);
        Register(HOTKEY_AUTOCLICKER, MOD_NOREPEAT, VK_F2);
        Register(HOTKEY_TURBO_HOLD, MOD_NOREPEAT, VK_F3);
        Register(HOTKEY_PURE_HOLD, MOD_NOREPEAT, VK_F4);
        Register(HOTKEY_RECORDER, MOD_NOREPEAT, VK_F5);
        Register(HOTKEY_PLAYBACK, MOD_NOREPEAT, VK_F12);
        Register(HOTKEY_SHOW_HIDE, MOD_CONTROL | MOD_SHIFT | MOD_ALT | MOD_NOREPEAT, VK_Z);
        Register(HOTKEY_CANCEL, MOD_NOREPEAT, VK_ESCAPE);
    }

    public void UnregisterAll()
    {
        foreach (var id in _registeredIds)
        {
            UnregisterHotKey(_windowHandle, id);
        }
        _registeredIds.Clear();
    }

    private readonly List<int> _failedIds = new();

    /// <summary>
    /// IDs of hotkeys that failed to register (e.g., another app holds them).
    /// </summary>
    public IReadOnlyList<int> FailedRegistrations => _failedIds;

    private bool Register(int id, uint modifiers, uint vk)
    {
        // Unregister first in case we already registered this ID (prevent duplicates)
        if (_registeredIds.Contains(id))
        {
            UnregisterHotKey(_windowHandle, id);
            _registeredIds.Remove(id);
        }

        bool result = RegisterHotKey(_windowHandle, id, modifiers, vk);
        if (result)
        {
            _registeredIds.Add(id);
            _failedIds.Remove(id);
        }
        else
        {
            int error = Marshal.GetLastWin32Error();
            System.Diagnostics.Debug.WriteLine(
                $"[HotkeyManager] Failed to register {GetHotkeyName(id)}: Win32 error {error}");
            if (!_failedIds.Contains(id))
                _failedIds.Add(id);
        }
        return result;
    }

    public void ProcessHotkeyMessage(int hotkeyId)
    {
        HotkeyPressed?.Invoke(hotkeyId);
    }

    public static string GetHotkeyName(int id) => id switch
    {
        HOTKEY_SLASH_MACRO => "Slash Macro (F1)",
        HOTKEY_AUTOCLICKER => "Autoclicker (F2)",
        HOTKEY_TURBO_HOLD => "Turbo Hold (F3)",
        HOTKEY_PURE_HOLD => "Pure Hold (F4)",
        HOTKEY_RECORDER => "Recorder (F5)",
        HOTKEY_PLAYBACK => "Playback (F12)",
        HOTKEY_SHOW_HIDE => "Show/Hide (Ctrl+Shift+Alt+Z)",
        HOTKEY_CANCEL => "Cancel (Esc)",
        _ => $"Unknown ({id})"
    };

    public void Dispose()
    {
        if (!_disposed)
        {
            UnregisterAll();
            _disposed = true;
        }
        GC.SuppressFinalize(this);
    }
}
