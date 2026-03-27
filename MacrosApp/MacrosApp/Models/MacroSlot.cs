namespace MacrosApp.Models;

public class MacroSlot
{
    public string Name { get; set; } = string.Empty;
    public int EventCount { get; set; }
    public string CoordMode { get; set; } = "screen";
    public string Recorded { get; set; } = string.Empty;
    public TimeSpan Duration { get; set; }

    public override string ToString()
    {
        string durationStr = Duration.TotalSeconds > 0
            ? $"{Duration.TotalSeconds:F1}s"
            : "—";
        return $"{Name}  ({EventCount} events, {durationStr})";
    }
}
