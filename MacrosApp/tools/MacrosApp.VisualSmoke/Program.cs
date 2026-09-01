using MacrosApp;
using MacrosApp.Models;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

ApplicationConfiguration.Initialize();
bool updateBaselines = args.Contains("--update-baselines", StringComparer.OrdinalIgnoreCase);
string repoRoot = FindRepoRoot(AppContext.BaseDirectory) ?? throw new InvalidOperationException("Macros-Script repository root was not found.");
string baselineDirectory = Path.Combine(repoRoot, "tests", "visual", "baselines");
string artifactDirectory = Path.Combine(repoRoot, "tests", "visual", "artifacts", "latest");
Directory.CreateDirectory(baselineDirectory);
Directory.CreateDirectory(artifactDirectory);

var settings = new AppSettings { OnboardingComplete = false };
settings.Bindings[MacroAction.Recorder].Controller = Chord(ControllerControl.X);
settings.Bindings[MacroAction.Playback].Controller = Chord(ControllerControl.A);
settings.Bindings[MacroAction.Cancel].Controller = Chord(ControllerControl.Y);
var store = new AppSettingsStore(Path.Combine(Path.GetTempPath(), "MacrosAppVisualSmoke", "settings.json"));
var scenarios = new List<(string Name, Func<Form> Create, bool Animate)>
{
    ("onboarding", () => new OnboardingForm(settings), false),
    ("bindings", () => new BindingSettingsForm(settings, store), false),
    ("palette-idle", () => Palette("Idle", settings), false),
    ("palette-recording", () => Palette("Recording keyboard, mouse, and controller...", settings), false),
    ("palette-saved-actions", () => Palette("Saved: recording-1 (42 events, 18 controller)", settings, HudPresentation.SavedActions), false),
    ("palette-playback", () => Palette("Playing: recording-1 (vJoy 1)", settings), false),
    ("palette-missing-controller", () => Palette("Saved partial: recording-1 (42 events, 0 controller). Playback may not control the game.", settings, HudPresentation.Warning), false),
    ("palette-backend-error", () => Palette("vJoy backend unavailable: device 1 is not ready", settings, HudPresentation.Error), false),
    ("palette-chord-animation", () => Palette("Saved: choose a controller action", settings, HudPresentation.SavedActions), true)
};

int failures = 0;
foreach (var scenario in scenarios)
{
    using Form form = scenario.Create();
    form.StartPosition = FormStartPosition.Manual;
    form.ShowInTaskbar = false;
    if (form is PaletteForm palette)
    {
        palette.ShowPaletteAt(new Point(40, 40), keepVisible: true);
        if (scenario.Animate)
            palette.AdvanceAnimationForTest();
    }
    else
    {
        form.Location = new Point(40, 40);
        form.Show();
    }
    form.PerformLayout();
    Application.DoEvents();
    Thread.Sleep(75);
    Application.DoEvents();

    using Bitmap image = CaptureShownWindow(form);
    form.Hide();
    string actualPath = Path.Combine(artifactDirectory, scenario.Name + ".png");
    image.Save(actualPath, ImageFormat.Png);

    if (IsBlankOrUniform(image, out string blankReason))
    {
        Console.WriteLine($"[fail] {scenario.Name}: live window capture is blank/uniform ({blankReason})");
        failures++;
        continue;
    }

    string baselinePath = Path.Combine(baselineDirectory, scenario.Name + ".png");
    if (updateBaselines)
    {
        image.Save(baselinePath, ImageFormat.Png);
        Console.WriteLine($"[baseline] {scenario.Name}: {baselinePath}");
        continue;
    }

    if (!File.Exists(baselinePath))
    {
        Console.WriteLine($"[fail] {scenario.Name}: missing baseline {baselinePath}");
        failures++;
        continue;
    }

    using var baseline = new Bitmap(baselinePath);
    bool equal = ImagesMatch(baseline, image, out double difference);
    Console.WriteLine($"[{(equal ? "pass" : "fail")}] {scenario.Name}: difference={difference:P4}");
    if (!equal)
        failures++;
}

Environment.ExitCode = failures == 0 ? 0 : 1;

static List<ControllerControl> Chord(ControllerControl face) => new()
{
    ControllerControl.LeftShoulder,
    ControllerControl.RightShoulder,
    ControllerControl.LeftTrigger,
    ControllerControl.RightTrigger,
    face
};

static Bitmap CaptureShownWindow(Form form)
{
    if (!NativeMethods.IsWindowVisible(form.Handle))
        throw new InvalidOperationException($"Window was not actually visible: {form.Text}");

    var image = new Bitmap(form.Width, form.Height, PixelFormat.Format32bppArgb);
    using Graphics graphics = Graphics.FromImage(image);
    IntPtr hdc = graphics.GetHdc();
    try
    {
        if (!NativeMethods.PrintWindow(form.Handle, hdc, 2))
            throw new InvalidOperationException($"PrintWindow failed for shown window: {form.Text}");
    }
    finally
    {
        graphics.ReleaseHdc(hdc);
    }
    return image;
}

static PaletteForm Palette(string status, AppSettings settings, HudPresentation presentation = HudPresentation.Compact)
{
    var palette = new PaletteForm(settings);
    palette.UpdateStatus(status, "RAC1", presentation);
    return palette;
}

static bool IsBlankOrUniform(Bitmap image, out string reason)
{
    var counts = new Dictionary<int, int>();
    int total = image.Width * image.Height;
    for (int y = 0; y < image.Height; y += 2)
    {
        for (int x = 0; x < image.Width; x += 2)
        {
            Color color = image.GetPixel(x, y);
            int key = (color.R << 16) | (color.G << 8) | color.B;
            counts[key] = counts.GetValueOrDefault(key) + 1;
        }
    }

    int sampled = Math.Max(1, ((image.Width + 1) / 2) * ((image.Height + 1) / 2));
    double dominantRatio = counts.Count == 0 ? 1 : counts.Values.Max() / (double)sampled;
    if (counts.Count < 12)
    {
        reason = $"only {counts.Count} sampled colors";
        return true;
    }
    if (dominantRatio > 0.965)
    {
        reason = $"dominant color covers {dominantRatio:P1}";
        return true;
    }

    reason = string.Empty;
    return false;
}

static bool ImagesMatch(Bitmap expected, Bitmap actual, out double difference)
{
    if (expected.Size != actual.Size)
    {
        difference = 1;
        return false;
    }

    long changed = 0;
    long pixels = (long)expected.Width * expected.Height;
    for (int y = 0; y < expected.Height; y++)
    {
        for (int x = 0; x < expected.Width; x++)
        {
            Color left = expected.GetPixel(x, y);
            Color right = actual.GetPixel(x, y);
            if (Math.Abs(left.R - right.R) > 4 || Math.Abs(left.G - right.G) > 4 || Math.Abs(left.B - right.B) > 4)
                changed++;
        }
    }
    difference = changed / (double)pixels;
    return difference <= 0.0025;
}

static string? FindRepoRoot(string start)
{
    DirectoryInfo? directory = new(Path.GetFullPath(start));
    while (directory != null)
    {
        if (File.Exists(Path.Combine(directory.FullName, "Macros.ahk")) && Directory.Exists(Path.Combine(directory.FullName, "MacrosApp")))
            return directory.FullName;
        directory = directory.Parent;
    }
    return null;
}

internal static class NativeMethods
{
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint flags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool IsWindowVisible(IntPtr hWnd);
}
