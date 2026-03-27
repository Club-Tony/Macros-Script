using System.Drawing;

namespace MacrosApp;

static class Program
{
    private static Mutex? _mutex;
    private static NotifyIcon? _trayIcon;
    private static MainForm? _mainForm;

    [STAThread]
    static void Main()
    {
        // Single instance check
        const string mutexName = "MacrosApp_SingleInstance_Mutex";
        _mutex = new Mutex(true, mutexName, out bool isNewInstance);

        if (!isNewInstance)
        {
            // Another instance is already running
            MessageBox.Show("Macros is already running.", "Macros",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            ApplicationConfiguration.Initialize();

            _mainForm = new MainForm();

            // Create tray icon
            _trayIcon = CreateTrayIcon();
            _mainForm.SetTrayIcon(_trayIcon);

            Application.Run(_mainForm);
        }
        finally
        {
            if (_trayIcon != null)
            {
                _trayIcon.ContextMenuStrip?.Dispose();
                _trayIcon.Dispose();
            }
            _mutex?.ReleaseMutex();
            _mutex?.Dispose();
        }
    }

    private static NotifyIcon CreateTrayIcon()
    {
        var trayMenu = new ContextMenuStrip();
        trayMenu.Renderer = new DarkTrayMenuRenderer();

        var showItem = new ToolStripMenuItem("Show", null, (_, _) =>
        {
            _mainForm?.RestoreFromTray();
        });
        showItem.Font = new Font(showItem.Font, FontStyle.Bold);

        var hideItem = new ToolStripMenuItem("Hide", null, (_, _) =>
        {
            _mainForm?.Hide();
        });

        var separator = new ToolStripSeparator();

        var exitItem = new ToolStripMenuItem("Exit", null, (_, _) =>
        {
            _mainForm?.ExitApplication();
        });
        exitItem.ForeColor = Color.FromArgb(255, 100, 100);

        trayMenu.Items.AddRange(new ToolStripItem[] { showItem, hideItem, separator, exitItem });

        var icon = new NotifyIcon
        {
            Text = "Macros",
            ContextMenuStrip = trayMenu,
            Visible = false
        };

        // Try to load icon from the icons folder, fall back to default app icon
        string iconPath = FindIconPath();
        if (File.Exists(iconPath))
        {
            try
            {
                icon.Icon = new Icon(iconPath);
            }
            catch
            {
                icon.Icon = SystemIcons.Application;
            }
        }
        else
        {
            icon.Icon = SystemIcons.Application;
        }

        icon.DoubleClick += (_, _) => _mainForm?.RestoreFromTray();

        return icon;
    }

    private static string FindIconPath()
    {
        // Look for icon relative to the Macros-Script repo
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;

        // Try navigating up to find the icons folder
        string[] candidates = new[]
        {
            Path.Combine(baseDir, "..", "..", "..", "..", "icons", "idle.ico"),
            Path.Combine(baseDir, "icons", "idle.ico"),
            Path.Combine(Directory.GetCurrentDirectory(), "icons", "idle.ico")
        };

        foreach (var path in candidates)
        {
            var full = Path.GetFullPath(path);
            if (File.Exists(full))
                return full;
        }

        return string.Empty;
    }

    private class DarkTrayMenuRenderer : ToolStripProfessionalRenderer
    {
        public DarkTrayMenuRenderer() : base(new DarkTrayColorTable()) { }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            if (e.Item is ToolStripMenuItem item && item.ForeColor != Color.FromArgb(255, 100, 100))
                e.TextColor = Color.FromArgb(220, 220, 220);
            base.OnRenderItemText(e);
        }
    }

    private class DarkTrayColorTable : ProfessionalColorTable
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
