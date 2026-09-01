using MacrosApp.Models;

namespace MacrosApp;

static class Program
{
    private static Mutex? _mutex;

    [STAThread]
    static void Main()
    {
        string mutexName = "MacrosApp_SingleInstance_Mutex" +
            (Environment.GetEnvironmentVariable("MACROSAPP_INSTANCE_SUFFIX") is { Length: > 0 } suffix ? "_" + suffix : string.Empty);
        _mutex = new Mutex(true, mutexName, out bool isNewInstance);
        if (!isNewInstance)
        {
            MessageBox.Show("Macros is already running in the system tray.", "Macros", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            ApplicationConfiguration.Initialize();
            if (!LegacyRuntimeGuard.AllowNativeStartup())
                return;

            using var context = new MacrosApplicationContext();
            Application.Run(context);
        }
        finally
        {
            _mutex.ReleaseMutex();
            _mutex.Dispose();
        }
    }
}

public sealed class MacrosApplicationContext : ApplicationContext
{
    private readonly AppSettingsStore _settingsStore;
    private readonly AppSettings _settings;
    private readonly MainForm _mainForm;
    private readonly PaletteForm _palette;
    private readonly NotifyIcon _trayIcon;
    private readonly InputBindingRuntime _bindings;
    private readonly ControlPipeServer _controlPipe;
    private bool _exiting;

    public MacrosApplicationContext()
    {
        _settingsStore = new AppSettingsStore();
        _settings = _settingsStore.Load();
        _mainForm = new MainForm(_settings.Runtime);
        _mainForm.ExitRequested += (_, _) => ExitApplication();
        _mainForm.SettingsChanged += (_, _) => SaveSettings();
        _mainForm.StatusChanged += MainForm_StatusChanged;
        _palette = new PaletteForm(_settings);
        _trayIcon = CreateTrayIcon();
        _mainForm.SetTrayIcon(_trayIcon);
        _mainForm.StartRuntime();

        _bindings = new InputBindingRuntime(_settings);
        _bindings.ActionTriggered += action =>
        {
            if (_mainForm.IsDisposed)
                return;
            _mainForm.BeginInvoke((MethodInvoker)(() => DispatchAction(action)));
        };
        _mainForm.SetRecorderChord(_settings.Bindings[MacroAction.Recorder].Controller);
        _controlPipe = new ControlPipeServer(() =>
        {
            if (!_mainForm.IsDisposed)
                _mainForm.BeginInvoke((MethodInvoker)ExitApplication);
        });

        if (!_settings.OnboardingComplete)
            ShowOnboarding();

        _trayIcon.Visible = true;
        _mainForm.Hide();
    }

    private void DispatchAction(ActionTrigger trigger)
    {
        if (trigger.Action == MacroAction.Palette)
            _palette.TogglePalette();
        else
            _mainForm.ExecuteAction(trigger);
        if (trigger.Action == MacroAction.Cancel && !_palette.ShouldStayVisible && !_palette.ShouldToast)
        {
            _palette.HidePalette();
            return;
        }
        _palette.RegisterActivity();
    }

    private void MainForm_StatusChanged(object? sender, MacroStatusChangedEventArgs e)
    {
        _palette.UpdateStatus(e.State, e.Profile, e.Presentation);
        if (_palette.ShouldStayVisible)
            _palette.ShowPalette(keepVisible: true);
        else if (_palette.ShouldToast)
            _palette.ShowPalette(keepVisible: false);
        else if (_palette.IsPaletteVisible)
            _palette.ShowPalette(keepVisible: false);
    }

    private void ShowOnboarding()
    {
        using var onboarding = new OnboardingForm(_settings);
        _ = onboarding.ShowDialog();
        _settings.OnboardingComplete = true;
        _settings.StartHidden = true;
        SaveSettings();
        _bindings?.UpdateSettings(_settings);
        _palette.RefreshBindings(_settings);
        _mainForm.SetRecorderChord(_settings.Bindings[MacroAction.Recorder].Controller);
    }

    private void ShowBindings()
    {
        using var form = new BindingSettingsForm(_settings, _settingsStore);
        form.BindingsChanged += (_, _) =>
        {
            _bindings.UpdateSettings(_settings);
            _palette.RefreshBindings(_settings);
            _mainForm.SetRecorderChord(_settings.Bindings[MacroAction.Recorder].Controller);
        };
        form.ShowDialog(_mainForm.Visible ? _mainForm : null);
    }

    private void SaveSettings()
    {
        _settings.Runtime = _mainForm.RuntimeSettings;
        _settingsStore.Save(_settings);
    }

    private NotifyIcon CreateTrayIcon()
    {
        var menu = new ContextMenuStrip { Renderer = new DarkTrayMenuRenderer() };
        var show = new ToolStripMenuItem("Show Macros", null, (_, _) => _mainForm.RestoreFromTray())
        {
            Font = new Font(SystemFonts.MenuFont ?? Control.DefaultFont, FontStyle.Bold)
        };
        var palette = new ToolStripMenuItem("Show in-game palette", null, (_, _) => _palette.TogglePalette());
        var bindings = new ToolStripMenuItem("Bindings and setup...", null, (_, _) => ShowBindings());
        var hide = new ToolStripMenuItem("Hide", null, (_, _) => _mainForm.Hide());
        var exit = new ToolStripMenuItem("Exit", null, (_, _) => ExitApplication())
        {
            ForeColor = Color.FromArgb(255, 100, 100)
        };
        menu.Items.AddRange(new ToolStripItem[] { show, palette, bindings, hide, new ToolStripSeparator(), exit });

        var icon = new NotifyIcon
        {
            Text = "Macros - running in tray",
            ContextMenuStrip = menu,
            Icon = LoadIcon(),
            Visible = false
        };
        icon.DoubleClick += (_, _) => _mainForm.RestoreFromTray();
        return icon;
    }

    private static Icon LoadIcon()
    {
        string baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
        string[] candidates =
        {
            Path.Combine(baseDirectory, "..", "..", "..", "..", "icons", "idle.ico"),
            Path.Combine(baseDirectory, "icons", "idle.ico"),
            Path.Combine(Directory.GetCurrentDirectory(), "icons", "idle.ico")
        };
        foreach (string candidate in candidates)
        {
            string fullPath = Path.GetFullPath(candidate);
            if (File.Exists(fullPath))
            {
                try { return new Icon(fullPath); } catch { }
            }
        }
        return SystemIcons.Application;
    }

    private void ExitApplication()
    {
        if (_exiting)
            return;
        _exiting = true;
        SaveSettings();
        _palette.HidePalette();
        _mainForm.ShutdownRuntime();
        _trayIcon.Visible = false;
        ExitThread();
    }

    protected override void ExitThreadCore()
    {
        _controlPipe.Dispose();
        _bindings.Dispose();
        _palette.Dispose();
        _trayIcon.ContextMenuStrip?.Dispose();
        _trayIcon.Dispose();
        if (!_mainForm.IsDisposed)
            _mainForm.Dispose();
        base.ExitThreadCore();
    }

    private sealed class DarkTrayMenuRenderer : ToolStripProfessionalRenderer
    {
        public DarkTrayMenuRenderer() : base(new DarkTrayColorTable()) { }
        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            if (e.Item is ToolStripMenuItem item && item.ForeColor != Color.FromArgb(255, 100, 100))
                e.TextColor = Color.FromArgb(220, 220, 220);
            base.OnRenderItemText(e);
        }
    }

    private sealed class DarkTrayColorTable : ProfessionalColorTable
    {
        public override Color MenuItemSelected => Color.FromArgb(50, 80, 120);
        public override Color MenuItemBorder => Color.FromArgb(70, 70, 70);
        public override Color MenuBorder => Color.FromArgb(70, 70, 70);
        public override Color ToolStripDropDownBackground => Color.FromArgb(40, 40, 40);
        public override Color ImageMarginGradientBegin => Color.FromArgb(40, 40, 40);
        public override Color ImageMarginGradientMiddle => Color.FromArgb(40, 40, 40);
        public override Color ImageMarginGradientEnd => Color.FromArgb(40, 40, 40);
        public override Color SeparatorDark => Color.FromArgb(60, 60, 60);
        public override Color SeparatorLight => Color.FromArgb(60, 60, 60);
    }
}
