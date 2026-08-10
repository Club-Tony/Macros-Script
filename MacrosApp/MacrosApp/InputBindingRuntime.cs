using MacrosApp.Models;
using System.Runtime.InteropServices;

namespace MacrosApp;

public sealed class BindingMatcher
{
    private AppSettings _settings;
    private readonly HashSet<MacroAction> _keyboardLatched = new();
    private readonly HashSet<MacroAction> _controllerLatched = new();

    public BindingMatcher(AppSettings settings) => _settings = settings;

    public void UpdateSettings(AppSettings settings)
    {
        _settings = settings;
        _keyboardLatched.Clear();
        _controllerLatched.Clear();
    }

    public IReadOnlyList<MacroAction> EvaluateKeyboard(IEnumerable<Keys> currentlyDown)
    {
        var down = currentlyDown.Select(BindingText.NormalizeKey).ToHashSet();
        return Evaluate(
            _settings.Bindings.Select(pair => (pair.Key, Required: pair.Value.Keyboard.Select(BindingText.NormalizeKey).ToHashSet())),
            down,
            _keyboardLatched);
    }

    public IReadOnlyList<MacroAction> EvaluateController(IEnumerable<ControllerControl> currentlyDown)
    {
        var down = currentlyDown.ToHashSet();
        return Evaluate(
            _settings.Bindings.Select(pair => (pair.Key, Required: pair.Value.Controller.ToHashSet())),
            down,
            _controllerLatched);
    }

    private static IReadOnlyList<MacroAction> Evaluate<T>(
        IEnumerable<(MacroAction Action, HashSet<T> Required)> bindings,
        HashSet<T> down,
        HashSet<MacroAction> latched) where T : notnull
    {
        var triggered = new List<MacroAction>();
        foreach (var (action, required) in bindings)
        {
            bool active = required.Count > 0 && required.IsSubsetOf(down);
            if (active && latched.Add(action))
                triggered.Add(action);
            else if (!active)
                latched.Remove(action);
        }
        return triggered;
    }
}

public sealed class InputBindingRuntime : NativeWindow, IDisposable
{
    private const int WmInput = 0x00FF;
    private const int RidInput = 0x10000003;
    private const uint RidevInputSink = 0x00000100;
    private const ushort UsagePageGeneric = 0x01;
    private const ushort UsageKeyboard = 0x06;
    private const ushort RiKeyBreak = 0x0001;
    private const ushort RiKeyE0 = 0x0002;
    private const ushort RiKeyE1 = 0x0004;

    private readonly BindingMatcher _matcher;
    private readonly HashSet<Keys> _keysDown = new();
    private readonly System.Windows.Forms.Timer _controllerTimer;
    private bool _disposed;

    public event Action<MacroAction>? ActionTriggered;

    public InputBindingRuntime(AppSettings settings)
    {
        _matcher = new BindingMatcher(settings);
        CreateHandle(new CreateParams
        {
            Caption = "MacrosApp Input Sink",
            Parent = new IntPtr(-3), // HWND_MESSAGE
            Style = 0,
            ExStyle = 0
        });
        RegisterKeyboardInput();

        _controllerTimer = new System.Windows.Forms.Timer { Interval = 30 };
        _controllerTimer.Tick += (_, _) => PollController();
        _controllerTimer.Start();
    }

    public void UpdateSettings(AppSettings settings) => _matcher.UpdateSettings(settings);

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmInput)
            ProcessRawInput(m.LParam);
        base.WndProc(ref m);
    }

    private void RegisterKeyboardInput()
    {
        var device = new RawInputDevice
        {
            UsagePage = UsagePageGeneric,
            Usage = UsageKeyboard,
            Flags = RidevInputSink,
            Target = Handle
        };
        if (!RegisterRawInputDevices(new[] { device }, 1, (uint)Marshal.SizeOf<RawInputDevice>()))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Unable to register background keyboard input.");
    }

    private void ProcessRawInput(IntPtr rawInputHandle)
    {
        uint size = 0;
        _ = GetRawInputData(rawInputHandle, RidInput, IntPtr.Zero, ref size, (uint)Marshal.SizeOf<RawInputHeader>());
        if (size == 0)
            return;

        IntPtr buffer = Marshal.AllocHGlobal((int)size);
        try
        {
            if (GetRawInputData(rawInputHandle, RidInput, buffer, ref size, (uint)Marshal.SizeOf<RawInputHeader>()) != size)
                return;

            RawInput input = Marshal.PtrToStructure<RawInput>(buffer);
            Keys key = NormalizeRawKey(input.Keyboard);
            if (key == Keys.None)
                return;

            bool released = (input.Keyboard.Flags & RiKeyBreak) != 0;
            if (released)
                _keysDown.Remove(key);
            else
                _keysDown.Add(key);

            foreach (MacroAction action in _matcher.EvaluateKeyboard(_keysDown))
                ActionTriggered?.Invoke(action);
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private static Keys NormalizeRawKey(RawKeyboard keyboard)
    {
        Keys key = (Keys)keyboard.VKey;
        if (key == Keys.ControlKey)
            return Keys.ControlKey;
        if (key == Keys.ShiftKey)
            return Keys.ShiftKey;
        if (key == Keys.Menu)
            return Keys.Menu;
        if (key == Keys.Return && (keyboard.Flags & RiKeyE0) != 0)
            return Keys.Enter;
        if ((keyboard.Flags & RiKeyE1) != 0 && key == Keys.Pause)
            return Keys.Pause;
        return BindingText.NormalizeKey(key);
    }

    private void PollController()
    {
        var down = NativeEngine.TryGetControllerState(0, out ControllerState state) && state.Connected
            ? ControllerControls.FromState(state)
            : Array.Empty<ControllerControl>();

        foreach (MacroAction action in _matcher.EvaluateController(down))
            ActionTriggered?.Invoke(action);
    }

    public void Dispose()
    {
        if (_disposed)
            return;
        _disposed = true;
        _controllerTimer.Stop();
        _controllerTimer.Dispose();
        DestroyHandle();
        GC.SuppressFinalize(this);
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterRawInputDevices(
        [In] RawInputDevice[] devices,
        uint deviceCount,
        uint size);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetRawInputData(
        IntPtr rawInput,
        int command,
        IntPtr data,
        ref uint size,
        uint headerSize);

    [StructLayout(LayoutKind.Sequential)]
    private struct RawInputDevice
    {
        public ushort UsagePage;
        public ushort Usage;
        public uint Flags;
        public IntPtr Target;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RawInputHeader
    {
        public uint Type;
        public uint Size;
        public IntPtr Device;
        public IntPtr WParam;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RawKeyboard
    {
        public ushort MakeCode;
        public ushort Flags;
        public ushort Reserved;
        public ushort VKey;
        public uint Message;
        public uint ExtraInformation;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RawInput
    {
        public RawInputHeader Header;
        public RawKeyboard Keyboard;
    }
}

public static class ControllerControls
{
    private const ushort DPadUp = 0x0001;
    private const ushort DPadDown = 0x0002;
    private const ushort DPadLeft = 0x0004;
    private const ushort DPadRight = 0x0008;
    private const ushort Start = 0x0010;
    private const ushort Back = 0x0020;
    private const ushort LeftThumb = 0x0040;
    private const ushort RightThumb = 0x0080;
    private const ushort LeftShoulder = 0x0100;
    private const ushort RightShoulder = 0x0200;
    private const ushort A = 0x1000;
    private const ushort B = 0x2000;
    private const ushort X = 0x4000;
    private const ushort Y = 0x8000;
    public const byte TriggerThreshold = 30;

    public static ControllerControl[] FromState(ControllerState state)
    {
        var controls = new List<ControllerControl>();
        Add(DPadUp, ControllerControl.DPadUp);
        Add(DPadDown, ControllerControl.DPadDown);
        Add(DPadLeft, ControllerControl.DPadLeft);
        Add(DPadRight, ControllerControl.DPadRight);
        Add(Start, ControllerControl.Start);
        Add(Back, ControllerControl.Back);
        Add(LeftThumb, ControllerControl.LeftThumb);
        Add(RightThumb, ControllerControl.RightThumb);
        Add(LeftShoulder, ControllerControl.LeftShoulder);
        Add(RightShoulder, ControllerControl.RightShoulder);
        Add(A, ControllerControl.A);
        Add(B, ControllerControl.B);
        Add(X, ControllerControl.X);
        Add(Y, ControllerControl.Y);
        if (state.LeftTrigger >= TriggerThreshold) controls.Add(ControllerControl.LeftTrigger);
        if (state.RightTrigger >= TriggerThreshold) controls.Add(ControllerControl.RightTrigger);
        return controls.ToArray();

        void Add(ushort mask, ControllerControl control)
        {
            if ((state.Buttons & mask) != 0)
                controls.Add(control);
        }
    }
}
