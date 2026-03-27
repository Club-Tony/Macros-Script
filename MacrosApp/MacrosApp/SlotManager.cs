using MacrosApp.Models;

namespace MacrosApp;

public class SlotManager
{
    private readonly string _basePath;
    private readonly string _iniPath;
    private readonly string _eventsDir;

    public SlotManager(string basePath)
    {
        _basePath = basePath;
        _iniPath = Path.Combine(_basePath, "macros.ini");
        _eventsDir = Path.Combine(_basePath, "macros_events");

        if (!Directory.Exists(_eventsDir))
            Directory.CreateDirectory(_eventsDir);
    }

    /// <summary>
    /// Load all slots from macros.ini.
    /// </summary>
    public List<MacroSlot> LoadSlots()
    {
        var slots = new List<MacroSlot>();

        if (!File.Exists(_iniPath))
            return slots;

        var lines = File.ReadAllLines(_iniPath);
        var slotNames = new List<string>();
        string? currentSection = null;
        var sectionData = new Dictionary<string, Dictionary<string, string>>();

        foreach (var rawLine in lines)
        {
            var line = rawLine.Trim().Replace("\0", ""); // Handle UTF-16 artifacts
            if (string.IsNullOrEmpty(line) || line.StartsWith(";"))
                continue;

            if (line.StartsWith("[") && line.EndsWith("]"))
            {
                currentSection = line[1..^1];
                if (!sectionData.ContainsKey(currentSection))
                    sectionData[currentSection] = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                continue;
            }

            if (currentSection != null && line.Contains('='))
            {
                var eqIdx = line.IndexOf('=');
                var key = line[..eqIdx].Trim();
                var val = line[(eqIdx + 1)..].Trim();
                sectionData[currentSection][key] = val;
            }
        }

        // Read slot list from [Slots] section
        if (sectionData.TryGetValue("Slots", out var slotsSection))
        {
            if (slotsSection.TryGetValue("count", out var countStr) && int.TryParse(countStr, out int count))
            {
                for (int i = 1; i <= count; i++)
                {
                    if (slotsSection.TryGetValue($"slot_{i}", out var name))
                        slotNames.Add(name);
                }
            }
        }

        // Build MacroSlot objects
        foreach (var name in slotNames)
        {
            var slot = new MacroSlot { Name = name };

            if (sectionData.TryGetValue(name, out var data))
            {
                if (data.TryGetValue("event_count", out var ec) && int.TryParse(ec, out int eventCount))
                    slot.EventCount = eventCount;
                if (data.TryGetValue("coord_mode", out var cm))
                    slot.CoordMode = cm;
                if (data.TryGetValue("recorded", out var rec))
                    slot.Recorded = rec;
            }

            // Calculate duration from event file
            slot.Duration = CalculateDuration(name);

            slots.Add(slot);
        }

        return slots;
    }

    /// <summary>
    /// Save or update a slot in macros.ini.
    /// </summary>
    public void SaveSlot(MacroSlot slot)
    {
        var slots = LoadSlots();
        var existing = slots.FindIndex(s => s.Name.Equals(slot.Name, StringComparison.OrdinalIgnoreCase));
        if (existing >= 0)
            slots[existing] = slot;
        else
            slots.Add(slot);

        WriteIni(slots);
    }

    /// <summary>
    /// Delete a slot and its event file.
    /// </summary>
    public void DeleteSlot(string name)
    {
        var slots = LoadSlots();
        slots.RemoveAll(s => s.Name.Equals(name, StringComparison.OrdinalIgnoreCase));
        WriteIni(slots);

        var eventFile = Path.Combine(_eventsDir, $"{name}.txt");
        if (File.Exists(eventFile))
            File.Delete(eventFile);
    }

    /// <summary>
    /// Rename a slot and its event file.
    /// </summary>
    public void RenameSlot(string oldName, string newName)
    {
        var slots = LoadSlots();
        var slot = slots.Find(s => s.Name.Equals(oldName, StringComparison.OrdinalIgnoreCase));
        if (slot == null) return;

        slot.Name = newName;
        WriteIni(slots);

        var oldFile = Path.Combine(_eventsDir, $"{oldName}.txt");
        var newFile = Path.Combine(_eventsDir, $"{newName}.txt");
        if (File.Exists(oldFile))
        {
            if (File.Exists(newFile))
                File.Delete(newFile);
            File.Move(oldFile, newFile);
        }
    }

    /// <summary>
    /// Sanitize a slot name for safe use as a file name.
    /// </summary>
    private static string SanitizeFileName(string name)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var sanitized = new System.Text.StringBuilder(name.Length);
        foreach (char c in name)
        {
            sanitized.Append(Array.IndexOf(invalid, c) >= 0 ? '_' : c);
        }
        return sanitized.ToString();
    }

    /// <summary>
    /// Get raw event lines for a slot.
    /// </summary>
    public string[] GetSlotEvents(string name)
    {
        var safeName = SanitizeFileName(name);
        var eventFile = Path.Combine(_eventsDir, $"{safeName}.txt");
        if (!File.Exists(eventFile))
            return Array.Empty<string>();

        return File.ReadAllLines(eventFile);
    }

    /// <summary>
    /// Save event data for a slot.
    /// </summary>
    public void SaveSlotEvents(string name, string[] events)
    {
        var eventFile = Path.Combine(_eventsDir, $"{name}.txt");
        File.WriteAllLines(eventFile, events);
    }

    /// <summary>
    /// Export a slot's event file to a user-chosen location.
    /// </summary>
    public bool ExportSlot(string name, string destinationPath)
    {
        var eventFile = Path.Combine(_eventsDir, $"{name}.txt");
        if (!File.Exists(eventFile))
            return false;

        File.Copy(eventFile, destinationPath, overwrite: true);
        return true;
    }

    private TimeSpan CalculateDuration(string name)
    {
        try
        {
            var events = GetSlotEvents(name);
            if (events.Length < 2) return TimeSpan.Zero;

            // Events are pipe-delimited: type|param1|param2|param3...
            // The last numeric field in mouse events is the delay in ms
            long totalMs = 0;
            foreach (var line in events)
            {
                if (string.IsNullOrWhiteSpace(line) || line.StartsWith(";"))
                    continue;
                var parts = line.Split('|');
                if (parts.Length >= 4)
                {
                    // Last field is typically the delay
                    var lastField = parts[^1].Trim();
                    if (long.TryParse(lastField, out long delay) && delay >= 0)
                        totalMs += delay;
                }
            }

            return TimeSpan.FromMilliseconds(totalMs);
        }
        catch
        {
            return TimeSpan.Zero;
        }
    }

    private void WriteIni(List<MacroSlot> slots)
    {
        using var writer = new StreamWriter(_iniPath, false, System.Text.Encoding.UTF8);

        // [Slots] section
        writer.WriteLine("[Slots]");
        writer.WriteLine($"count={slots.Count}");
        for (int i = 0; i < slots.Count; i++)
        {
            writer.WriteLine($"slot_{i + 1}={slots[i].Name}");
        }
        writer.WriteLine();

        // Individual slot sections
        foreach (var slot in slots)
        {
            writer.WriteLine($"[{slot.Name}]");
            writer.WriteLine($"event_count={slot.EventCount}");
            writer.WriteLine($"coord_mode={slot.CoordMode}");
            writer.WriteLine($"recorded={slot.Recorded}");
            writer.WriteLine();
        }
    }
}
