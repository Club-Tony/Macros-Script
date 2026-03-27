using System.Runtime.InteropServices;

namespace MacrosApp;

/// <summary>
/// Mirrors the C ControllerState struct with explicit Pack=1 to match
/// the C compiler's layout (bool=1 byte, then uint16_t with possible padding).
/// Using Pack=2 matches the natural alignment of the C struct.
/// </summary>
[StructLayout(LayoutKind.Sequential, Pack = 2)]
public struct ControllerState
{
    [MarshalAs(UnmanagedType.I1)] public bool Connected;
    public ushort Buttons;
    public short LeftThumbX, LeftThumbY;
    public short RightThumbX, RightThumbY;
    public byte LeftTrigger, RightTrigger;
}

public static class NativeEngine
{
    private const string DllName = "MacrosEngine.dll";

    private static bool _available;
    private static bool _checked;

    /// <summary>
    /// Whether the native DLL is loaded and available.
    /// </summary>
    public static bool IsAvailable
    {
        get
        {
            if (!_checked)
            {
                _checked = true;
                try
                {
                    var version = Engine_GetVersion();
                    _available = version != null;
                }
                catch (DllNotFoundException)
                {
                    _available = false;
                }
                catch (EntryPointNotFoundException)
                {
                    _available = false;
                }
            }
            return _available;
        }
    }

    // ================================================================
    // Engine lifecycle
    // ================================================================

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool Engine_Init();

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern void Engine_Shutdown();

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool Engine_IsInitialized();

    // ================================================================
    // Controller polling
    // ================================================================

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool Engine_StartPolling(uint intervalMs);

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern void Engine_StopPolling();

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool Engine_GetControllerState(uint playerIndex, out ControllerState state);

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern void Engine_SetDeadzone(uint playerIndex, short thumbDeadzone, byte triggerDeadzone);

    // ================================================================
    // Recording
    // ================================================================

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool Engine_StartRecording();

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern void Engine_StopRecording();

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool Engine_IsRecording();

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern uint Engine_GetRecordedEventCount();

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool Engine_RecordKeyEvent(
        [MarshalAs(UnmanagedType.I1)] bool down, ushort vkCode, ushort scanCode);

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool Engine_RecordMouseMove(int x, int y);

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool Engine_RecordMouseButton(
        [MarshalAs(UnmanagedType.I1)] bool down, ushort button);

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool Engine_RecordMouseWheel(int delta);

    // ================================================================
    // Playback
    // ================================================================

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool Engine_StartPlayback(IntPtr events, uint count, uint loopCount);

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern void Engine_StopPlayback();

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern void Engine_PausePlayback();

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern void Engine_ResumePlayback();

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool Engine_IsPlaying();

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool Engine_IsPaused();

    // ================================================================
    // Event file I/O
    // ================================================================

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    public static extern uint Engine_LoadEventsFromFile(string path, IntPtr buffer, uint bufferSize);

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool Engine_SaveEventsToFile(string path, IntPtr events, uint count);

    // ================================================================
    // Version
    // ================================================================

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.LPStr)]
    public static extern string Engine_GetVersion();

    // ================================================================
    // Safe wrappers that check availability first
    // ================================================================

    public static bool TryInit()
    {
        if (!IsAvailable) return false;
        try { return Engine_Init(); }
        catch { return false; }
    }

    public static void TryShutdown()
    {
        if (!IsAvailable) return;
        try { Engine_Shutdown(); } catch { }
    }

    public static bool TryGetControllerState(uint playerIndex, out ControllerState state)
    {
        state = default;
        if (!IsAvailable) return false;
        try { return Engine_GetControllerState(playerIndex, out state); }
        catch { return false; }
    }

    public static bool TryStartPolling(uint intervalMs)
    {
        if (!IsAvailable) return false;
        try { return Engine_StartPolling(intervalMs); }
        catch { return false; }
    }

    public static void TryStopPolling()
    {
        if (!IsAvailable) return;
        try { Engine_StopPolling(); } catch { }
    }

    public static bool TryStartRecording()
    {
        if (!IsAvailable) return false;
        try { return Engine_StartRecording(); }
        catch { return false; }
    }

    public static void TryStopRecording()
    {
        if (!IsAvailable) return;
        try { Engine_StopRecording(); } catch { }
    }

    public static bool TryIsRecording()
    {
        if (!IsAvailable) return false;
        try { return Engine_IsRecording(); }
        catch { return false; }
    }

    public static bool TryStartPlayback(IntPtr events, uint count, uint loopCount)
    {
        if (!IsAvailable) return false;
        try { return Engine_StartPlayback(events, count, loopCount); }
        catch { return false; }
    }

    public static void TryStopPlayback()
    {
        if (!IsAvailable) return;
        try { Engine_StopPlayback(); } catch { }
    }

    public static bool TryIsPlaying()
    {
        if (!IsAvailable) return false;
        try { return Engine_IsPlaying(); }
        catch { return false; }
    }

    public static bool TryIsPaused()
    {
        if (!IsAvailable) return false;
        try { return Engine_IsPaused(); }
        catch { return false; }
    }

    public static void TryPausePlayback()
    {
        if (!IsAvailable) return;
        try { Engine_PausePlayback(); } catch { }
    }

    public static void TryResumePlayback()
    {
        if (!IsAvailable) return;
        try { Engine_ResumePlayback(); } catch { }
    }
}
