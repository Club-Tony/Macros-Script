using System.Text.Json.Serialization;

namespace MacrosApp.Models;

public enum MacroAction
{
    Palette,
    SlashMacro,
    Autoclicker,
    TurboHold,
    PureHold,
    Recorder,
    Playback,
    Cancel
}

public enum ControllerControl
{
    DPadUp,
    DPadDown,
    DPadLeft,
    DPadRight,
    Start,
    Back,
    LeftThumb,
    RightThumb,
    LeftShoulder,
    RightShoulder,
    LeftTrigger,
    RightTrigger,
    A,
    B,
    X,
    Y
}

public sealed class ActionBinding
{
    public List<Keys> Keyboard { get; set; } = new();
    public List<ControllerControl> Controller { get; set; } = new();

    [JsonIgnore]
    public string KeyboardText => Keyboard.Count == 0
        ? "Not set"
        : string.Join(" + ", Keyboard.Select(BindingText.KeyName));

    [JsonIgnore]
    public string ControllerText => Controller.Count == 0
        ? "Not set"
        : string.Join(" + ", Controller.Select(BindingText.ControllerName));

    public ActionBinding Clone() => new()
    {
        Keyboard = new List<Keys>(Keyboard),
        Controller = new List<ControllerControl>(Controller)
    };
}

public sealed class AppSettings
{
    public const int CurrentSchemaVersion = 1;

    public int SchemaVersion { get; set; } = CurrentSchemaVersion;
    public bool OnboardingComplete { get; set; }
    public bool StartHidden { get; set; } = true;
    public MacroSettings Runtime { get; set; } = new();
    public Dictionary<MacroAction, ActionBinding> Bindings { get; set; } = CreateDefaultBindings();

    public void Normalize()
    {
        SchemaVersion = CurrentSchemaVersion;
        Runtime ??= new MacroSettings();
        Bindings ??= new Dictionary<MacroAction, ActionBinding>();
        foreach (MacroAction action in Enum.GetValues<MacroAction>())
        {
            if (!Bindings.TryGetValue(action, out ActionBinding? binding) || binding == null)
                Bindings[action] = DefaultBinding(action);
            else
            {
                binding.Keyboard = binding.Keyboard
                    .Select(BindingText.NormalizeKey)
                    .Distinct()
                    .OrderBy(BindingText.KeySortOrder)
                    .ToList();
                binding.Controller = binding.Controller.Distinct().Order().ToList();
            }
        }
    }

    public void Reset(MacroAction action) => Bindings[action] = DefaultBinding(action);

    public void ResetAll() => Bindings = CreateDefaultBindings();

    public bool HasKeyboardDuplicate(MacroAction action, IEnumerable<Keys> keys)
    {
        var candidate = keys.Select(BindingText.NormalizeKey).Distinct().OrderBy(BindingText.KeySortOrder).ToArray();
        return candidate.Length > 0 && Bindings.Any(pair =>
            pair.Key != action && pair.Value.Keyboard
                .Select(BindingText.NormalizeKey)
                .Distinct()
                .OrderBy(BindingText.KeySortOrder)
                .SequenceEqual(candidate));
    }

    public bool HasControllerDuplicate(MacroAction action, IEnumerable<ControllerControl> controls)
    {
        var candidate = controls.Distinct().Order().ToArray();
        return candidate.Length > 0 && Bindings.Any(pair =>
            pair.Key != action && pair.Value.Controller.Distinct().Order().SequenceEqual(candidate));
    }

    public static Dictionary<MacroAction, ActionBinding> CreateDefaultBindings() =>
        Enum.GetValues<MacroAction>().ToDictionary(action => action, DefaultBinding);

    public static ActionBinding DefaultBinding(MacroAction action)
    {
        Keys[] keyboard = action switch
        {
            MacroAction.Palette => new[] { Keys.ControlKey, Keys.ShiftKey, Keys.Menu, Keys.Z },
            MacroAction.SlashMacro => new[] { Keys.F1 },
            MacroAction.Autoclicker => new[] { Keys.F2 },
            MacroAction.TurboHold => new[] { Keys.F3 },
            MacroAction.PureHold => new[] { Keys.F4 },
            MacroAction.Recorder => new[] { Keys.F5 },
            MacroAction.Playback => new[] { Keys.F12 },
            MacroAction.Cancel => new[] { Keys.Escape },
            _ => Array.Empty<Keys>()
        };
        return new ActionBinding { Keyboard = keyboard.ToList() };
    }
}

public static class BindingText
{
    public static Keys NormalizeKey(Keys key) => key switch
    {
        Keys.LControlKey or Keys.RControlKey => Keys.ControlKey,
        Keys.LShiftKey or Keys.RShiftKey => Keys.ShiftKey,
        Keys.LMenu or Keys.RMenu => Keys.Menu,
        _ => key & Keys.KeyCode
    };

    public static int KeySortOrder(Keys key) => NormalizeKey(key) switch
    {
        Keys.ControlKey => 0,
        Keys.ShiftKey => 1,
        Keys.Menu => 2,
        _ => 1000 + (int)NormalizeKey(key)
    };

    public static string KeyName(Keys key) => NormalizeKey(key) switch
    {
        Keys.ControlKey => "Ctrl",
        Keys.ShiftKey => "Shift",
        Keys.Menu => "Alt",
        _ => NormalizeKey(key).ToString()
    };

    public static string ControllerName(ControllerControl control) => control switch
    {
        ControllerControl.LeftShoulder => "LB",
        ControllerControl.RightShoulder => "RB",
        ControllerControl.LeftTrigger => "LT",
        ControllerControl.RightTrigger => "RT",
        ControllerControl.LeftThumb => "L3",
        ControllerControl.RightThumb => "R3",
        _ => control.ToString()
    };

    public static string ActionName(MacroAction action) => action switch
    {
        MacroAction.Palette => "In-game palette",
        MacroAction.SlashMacro => "Slash macro",
        MacroAction.Autoclicker => "Autoclicker",
        MacroAction.TurboHold => "Turbo hold",
        MacroAction.PureHold => "Pure hold",
        MacroAction.Recorder => "Record / stop",
        MacroAction.Playback => "Playback",
        MacroAction.Cancel => "Cancel",
        _ => action.ToString()
    };
}
