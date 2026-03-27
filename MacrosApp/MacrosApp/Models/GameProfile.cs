namespace MacrosApp.Models;

public class GameProfile
{
    public string Name { get; set; } = "Default";
    public string ProcessName { get; set; } = string.Empty;
    public SendModeType SendMode { get; set; } = SendModeType.Input;
    public int VJoyDeviceId { get; set; } = 1;
    public string VJoyPovMode { get; set; } = string.Empty;

    public override string ToString() => string.IsNullOrEmpty(ProcessName)
        ? Name
        : $"{Name} ({ProcessName})";
}
