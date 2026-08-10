using MacrosApp.Models;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MacrosApp;

public sealed class AppSettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public string SettingsPath { get; }

    public AppSettingsStore(string? path = null)
    {
        SettingsPath = path ?? Environment.GetEnvironmentVariable("MACROSAPP_SETTINGS_PATH") ??
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Macros-Script",
                "settings.json");
    }

    public AppSettings Load()
    {
        try
        {
            if (!File.Exists(SettingsPath))
                return new AppSettings();

            var settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(SettingsPath), JsonOptions)
                ?? new AppSettings();
            settings.Normalize();
            return settings;
        }
        catch (JsonException)
        {
            PreserveCorruptFile();
            return new AppSettings();
        }
        catch (IOException)
        {
            return new AppSettings();
        }
        catch (UnauthorizedAccessException)
        {
            return new AppSettings();
        }
    }

    public void Save(AppSettings settings)
    {
        settings.Normalize();
        string? directory = Path.GetDirectoryName(SettingsPath);
        if (string.IsNullOrWhiteSpace(directory))
            throw new InvalidOperationException("Settings path must have a parent directory.");

        Directory.CreateDirectory(directory);
        string temporaryPath = SettingsPath + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(settings, JsonOptions));
        File.Move(temporaryPath, SettingsPath, overwrite: true);
    }

    private void PreserveCorruptFile()
    {
        try
        {
            string backup = SettingsPath + ".corrupt-" + DateTime.Now.ToString("yyyyMMdd-HHmmss");
            File.Move(SettingsPath, backup, overwrite: false);
        }
        catch
        {
            // Loading defaults is more important than failing startup over backup creation.
        }
    }
}
