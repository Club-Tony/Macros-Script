namespace MacrosApp.Models;

public enum SendModeType
{
    Input,
    Play,
    Event
}

public class MacroSettings
{
    public int AutoclickerInterval { get; set; } = 100;
    public SendModeType SendMode { get; set; } = SendModeType.Input;
    public int LoopCount { get; set; } = 0; // 0 = infinite
    public int ThumbDeadzone { get; set; } = 7849;
    public int TriggerDeadzone { get; set; } = 30;
}
