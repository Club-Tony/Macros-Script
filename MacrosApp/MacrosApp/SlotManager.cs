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
        var ini = LoadIniDocument();
        var slotNames = GetRegisteredSlotNames(ini);

        // Read slot list from [Slots] section
        // Build MacroSlot objects
        foreach (var name in slotNames)
        {
            var slot = new MacroSlot { Name = name };

            if (ini.Sections.TryGetValue(name, out var data))
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
        slot.Name = SanitizeSlotName(slot.Name);
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
        name = SanitizeSlotName(name);
        var slots = LoadSlots();
        slots.RemoveAll(s => s.Name.Equals(name, StringComparison.OrdinalIgnoreCase));
        WriteIni(slots);

        var eventFile = GetEventFilePath(name);
        if (File.Exists(eventFile))
            File.Delete(eventFile);
    }

    /// <summary>
    /// Rename a slot and its event file.
    /// </summary>
    public void RenameSlot(string oldName, string newName)
    {
        oldName = SanitizeSlotName(oldName);
        newName = SanitizeSlotName(newName);
        var slots = LoadSlots();
        var slot = slots.Find(s => s.Name.Equals(oldName, StringComparison.OrdinalIgnoreCase));
        if (slot == null) return;

        slot.Name = newName;
        WriteIni(slots);

        var oldFile = GetEventFilePath(oldName);
        var newFile = GetEventFilePath(newName);
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
    private static string SanitizeSlotName(string name)
    {
        var trimmed = name.Trim();
        if (trimmed.Length == 0)
            return "untitled";

        var invalid = Path.GetInvalidFileNameChars();
        var sanitized = new System.Text.StringBuilder(trimmed.Length);
        foreach (char c in trimmed)
        {
            sanitized.Append(Array.IndexOf(invalid, c) >= 0 ? '_' : c);
        }
        return sanitized.Length == 0 ? "untitled" : sanitized.ToString();
    }

    /// <summary>
    /// Get raw event lines for a slot.
    /// </summary>
    public string[] GetSlotEvents(string name)
    {
        var eventFile = GetEventFilePath(name);
        if (!File.Exists(eventFile))
            return Array.Empty<string>();

        return File.ReadAllLines(eventFile);
    }

    public string GetEventFilePath(string name)
    {
        var safeName = SanitizeSlotName(name);
        return Path.Combine(_eventsDir, $"{safeName}.txt");
    }

    /// <summary>
    /// Save event data for a slot.
    /// </summary>
    public void SaveSlotEvents(string name, string[] events)
    {
        var eventFile = GetEventFilePath(name);
        File.WriteAllLines(eventFile, events);
    }

    /// <summary>
    /// Export a slot's event file to a user-chosen location.
    /// </summary>
    public bool ExportSlot(string name, string destinationPath)
    {
        var eventFile = GetEventFilePath(name);
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
        var ini = LoadIniDocument();
        var existingSlotNames = GetRegisteredSlotNames(ini);

        RemoveSection(ini, "Slots");
        foreach (var existingSlotName in existingSlotNames)
        {
            RemoveSection(ini, existingSlotName);
        }

        var slotsSection = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["count"] = slots.Count.ToString()
        };

        for (int i = 0; i < slots.Count; i++)
        {
            slotsSection[$"slot_{i + 1}"] = SanitizeSlotName(slots[i].Name);
        }

        InsertSection(ini, 0, "Slots", slotsSection);

        int insertIndex = 1;
        foreach (var slot in slots)
        {
            string slotName = SanitizeSlotName(slot.Name);
            InsertSection(
                ini,
                insertIndex++,
                slotName,
                new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
                {
                    ["event_count"] = slot.EventCount.ToString(),
                    ["coord_mode"] = slot.CoordMode,
                    ["recorded"] = slot.Recorded
                });
        }

        using var writer = new StreamWriter(_iniPath, false, System.Text.Encoding.UTF8);
        for (int i = 0; i < ini.SectionOrder.Count; i++)
        {
            string sectionName = ini.SectionOrder[i];
            if (!ini.Sections.TryGetValue(sectionName, out var section))
                continue;

            writer.WriteLine($"[{sectionName}]");
            foreach (var pair in section)
            {
                writer.WriteLine($"{pair.Key}={pair.Value}");
            }

            if (i < ini.SectionOrder.Count - 1)
                writer.WriteLine();
        }
    }

    private IniDocument LoadIniDocument()
    {
        var document = new IniDocument();
        if (!File.Exists(_iniPath))
            return document;

        string? currentSection = null;
        foreach (var rawLine in File.ReadAllLines(_iniPath))
        {
            var line = rawLine.Trim().Replace("\0", "");
            if (string.IsNullOrEmpty(line) || line.StartsWith(";"))
                continue;

            if (line.StartsWith("[") && line.EndsWith("]"))
            {
                currentSection = line[1..^1];
                if (!document.Sections.ContainsKey(currentSection))
                {
                    document.SectionOrder.Add(currentSection);
                    document.Sections[currentSection] = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                }
                continue;
            }

            if (currentSection == null || !line.Contains('='))
                continue;

            int eqIdx = line.IndexOf('=');
            string key = line[..eqIdx].Trim();
            string val = line[(eqIdx + 1)..].Trim();
            document.Sections[currentSection][key] = val;
        }

        return document;
    }

    private static List<string> GetRegisteredSlotNames(IniDocument ini)
    {
        var slotNames = new List<string>();
        if (!ini.Sections.TryGetValue("Slots", out var slotsSection))
            return slotNames;

        if (!slotsSection.TryGetValue("count", out var countStr) || !int.TryParse(countStr, out int count))
            return slotNames;

        for (int i = 1; i <= count; i++)
        {
            if (slotsSection.TryGetValue($"slot_{i}", out var name) && !string.IsNullOrWhiteSpace(name))
                slotNames.Add(name);
        }

        return slotNames;
    }

    private static void RemoveSection(IniDocument ini, string sectionName)
    {
        ini.SectionOrder.RemoveAll(name => name.Equals(sectionName, StringComparison.OrdinalIgnoreCase));
        ini.Sections.Remove(sectionName);
    }

    private static void InsertSection(IniDocument ini, int index, string sectionName, Dictionary<string, string> values)
    {
        RemoveSection(ini, sectionName);

        int boundedIndex = Math.Max(0, Math.Min(index, ini.SectionOrder.Count));
        ini.SectionOrder.Insert(boundedIndex, sectionName);
        ini.Sections[sectionName] = values;
    }

    private sealed class IniDocument
    {
        public List<string> SectionOrder { get; } = new();
        public Dictionary<string, Dictionary<string, string>> Sections { get; } =
            new(StringComparer.OrdinalIgnoreCase);
    }
}
