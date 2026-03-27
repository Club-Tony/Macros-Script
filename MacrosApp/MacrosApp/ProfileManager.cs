using System.Diagnostics;
using System.Runtime.InteropServices;
using MacrosApp.Models;

namespace MacrosApp;

public class ProfileManager
{
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    private readonly string _iniPath;

    public ProfileManager(string basePath)
    {
        _iniPath = Path.Combine(basePath, "profiles.ini");
    }

    /// <summary>
    /// Load all profiles from profiles.ini.
    /// </summary>
    public List<GameProfile> LoadProfiles()
    {
        var profiles = new List<GameProfile>();

        if (!File.Exists(_iniPath))
        {
            // Create default profile
            profiles.Add(new GameProfile { Name = "Default" });
            return profiles;
        }

        var lines = File.ReadAllLines(_iniPath);
        string? currentSection = null;
        GameProfile? current = null;

        foreach (var rawLine in lines)
        {
            var line = rawLine.Trim();
            if (string.IsNullOrEmpty(line) || line.StartsWith(";"))
                continue;

            if (line.StartsWith("[") && line.EndsWith("]"))
            {
                if (current != null)
                    profiles.Add(current);

                currentSection = line[1..^1];
                current = new GameProfile { Name = currentSection };
                continue;
            }

            if (current != null && line.Contains('='))
            {
                var eqIdx = line.IndexOf('=');
                var key = line[..eqIdx].Trim();
                var val = line[(eqIdx + 1)..].Trim();

                switch (key.ToLowerInvariant())
                {
                    case "process":
                        current.ProcessName = val;
                        break;
                    case "sendmode":
                        if (Enum.TryParse<SendModeType>(val, true, out var mode))
                            current.SendMode = mode;
                        break;
                    case "vjoydeviceid":
                        if (int.TryParse(val, out int deviceId))
                            current.VJoyDeviceId = deviceId;
                        break;
                    case "vjoypovmode":
                        current.VJoyPovMode = val;
                        break;
                }
            }
        }

        if (current != null)
            profiles.Add(current);

        if (profiles.Count == 0)
            profiles.Add(new GameProfile { Name = "Default" });

        return profiles;
    }

    /// <summary>
    /// Detect active profile based on foreground window process.
    /// </summary>
    public GameProfile? DetectActiveProfile()
    {
        try
        {
            var hwnd = GetForegroundWindow();
            if (hwnd == IntPtr.Zero) return null;

            GetWindowThreadProcessId(hwnd, out uint pid);
            if (pid == 0) return null;

            string? processName = null;
            try
            {
                using var proc = Process.GetProcessById((int)pid);
                processName = proc.ProcessName;
            }
            catch (ArgumentException)
            {
                // Process exited between GetWindowThreadProcessId and GetProcessById
                return null;
            }
            catch (System.ComponentModel.Win32Exception)
            {
                // Access denied -- e.g., elevated process
                return null;
            }

            if (string.IsNullOrEmpty(processName))
                return null;

            var profiles = LoadProfiles();
            return profiles.Find(p =>
                !string.IsNullOrEmpty(p.ProcessName) &&
                p.ProcessName.Replace(".exe", "").Equals(processName, StringComparison.OrdinalIgnoreCase));
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Save a profile to profiles.ini.
    /// </summary>
    public void SaveProfile(GameProfile profile)
    {
        var profiles = LoadProfiles();
        var existing = profiles.FindIndex(p => p.Name.Equals(profile.Name, StringComparison.OrdinalIgnoreCase));
        if (existing >= 0)
            profiles[existing] = profile;
        else
            profiles.Add(profile);

        WriteIni(profiles);
    }

    private void WriteIni(List<GameProfile> profiles)
    {
        using var writer = new StreamWriter(_iniPath, false, System.Text.Encoding.UTF8);

        foreach (var profile in profiles)
        {
            writer.WriteLine($"[{profile.Name}]");
            writer.WriteLine($"SendMode={profile.SendMode}");
            writer.WriteLine($"vJoyDeviceId={profile.VJoyDeviceId}");
            writer.WriteLine($"vJoyPovMode={profile.VJoyPovMode}");

            if (!string.IsNullOrEmpty(profile.ProcessName))
                writer.WriteLine($"Process={profile.ProcessName}");

            writer.WriteLine();
        }
    }
}
