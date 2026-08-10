using MacrosApp;
using MacrosApp.Models;
using System.Drawing.Imaging;

bool updateBaselines = args.Contains("--update-baselines", StringComparer.OrdinalIgnoreCase);
string repoRoot = FindRepoRoot(AppContext.BaseDirectory) ?? throw new InvalidOperationException("Macros-Script repository root was not found.");
string baselineDirectory = Path.Combine(repoRoot, "tests", "visual", "baselines");
string artifactDirectory = Path.Combine(repoRoot, "tests", "visual", "artifacts", "latest");
Directory.CreateDirectory(baselineDirectory);
Directory.CreateDirectory(artifactDirectory);

var settings = new AppSettings { OnboardingComplete = false };
var store = new AppSettingsStore(Path.Combine(Path.GetTempPath(), "MacrosAppVisualSmoke", "settings.json"));
var scenarios = new List<(string Name, Func<Form> Create)>
{
    ("onboarding", () => new OnboardingForm(settings)),
    ("bindings", () => new BindingSettingsForm(settings, store)),
    ("palette-idle", () => Palette("Idle", settings)),
    ("palette-recording", () => Palette("Recording...", settings)),
    ("palette-playback", () => Palette("Playing: sample-slot", settings)),
    ("palette-error", () => Palette("Error: input backend unavailable", settings))
};

int failures = 0;
foreach (var scenario in scenarios)
{
    using Form form = scenario.Create();
    form.StartPosition = FormStartPosition.Manual;
    form.Location = new Point(-32_000, -32_000);
    form.ShowInTaskbar = false;
    form.Show();
    form.PerformLayout();
    Application.DoEvents();
    // Draw the entire window, including non-client chrome. Using ClientSize as
    // the bitmap bounds clips bottom-docked controls on bordered forms.
    using var image = new Bitmap(form.Width, form.Height, PixelFormat.Format32bppArgb);
    form.DrawToBitmap(image, new Rectangle(Point.Empty, form.Size));
    form.Hide();
    string actualPath = Path.Combine(artifactDirectory, scenario.Name + ".png");
    image.Save(actualPath, ImageFormat.Png);
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

static PaletteForm Palette(string status, AppSettings settings)
{
    var palette = new PaletteForm(settings);
    palette.UpdateStatus(status, "Default");
    return palette;
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
