using MacrosApp.Models;
using System.Runtime.InteropServices;

namespace MacrosApp;

public sealed class PaletteForm : Form
{
    private const int WsExToolWindow = 0x00000080;
    private const int WsExNoActivate = 0x08000000;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpShowWindow = 0x0040;
    private const int SwHide = 0;
    private readonly Label _stateLabel;
    private readonly Label _profileLabel;
    private readonly FlowLayoutPanel _actionRows;
    private readonly System.Windows.Forms.Timer _hideTimer;
    private AppSettings _settings;

    public bool UsesNoActivateStyle => (CreateParams.ExStyle & WsExNoActivate) != 0;
    public bool IsPaletteVisible => IsHandleCreated && IsWindowVisible(Handle);

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams parameters = base.CreateParams;
            parameters.ExStyle |= WsExToolWindow | WsExNoActivate;
            return parameters;
        }
    }

    public PaletteForm(AppSettings settings)
    {
        _settings = settings;
        Text = "Macros palette";
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = true;
        ClientSize = new Size(430, 470);
        BackColor = Color.FromArgb(18, 18, 22);
        ForeColor = Color.White;
        Padding = new Padding(2);

        var border = new Panel { Dock = DockStyle.Fill, BackColor = Color.FromArgb(70, 105, 145), Padding = new Padding(1) };
        var body = new Panel { Dock = DockStyle.Fill, BackColor = Color.FromArgb(24, 24, 29), Padding = new Padding(14) };
        var title = new Label
        {
            Text = "MACROS",
            Dock = DockStyle.Top,
            Height = 38,
            Font = new Font("Segoe UI", 14f, FontStyle.Bold),
            ForeColor = Color.FromArgb(115, 205, 255)
        };
        _stateLabel = new Label { Text = "Idle", Dock = DockStyle.Top, Height = 30, ForeColor = Color.FromArgb(110, 220, 130) };
        _profileLabel = new Label { Text = "Profile: Default", Dock = DockStyle.Top, Height = 28, ForeColor = Color.FromArgb(180, 180, 185) };
        _actionRows = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoScroll = true,
            BackColor = Color.FromArgb(24, 24, 29)
        };
        var footer = new Label
        {
            Text = "Bindings pass through to the game  |  Palette hides after 15 seconds",
            Dock = DockStyle.Bottom,
            Height = 30,
            ForeColor = Color.FromArgb(130, 130, 138),
            Font = new Font("Segoe UI", 8f)
        };

        body.Controls.Add(_actionRows);
        body.Controls.Add(_profileLabel);
        body.Controls.Add(_stateLabel);
        body.Controls.Add(title);
        body.Controls.Add(footer);
        border.Controls.Add(body);
        Controls.Add(border);

        _hideTimer = new System.Windows.Forms.Timer { Interval = 15_000 };
        _hideTimer.Tick += (_, _) => HidePalette();
        RefreshBindings(settings);
        // Create the hidden no-activate window before any gameplay-time show.
        // First handle creation during ShowPalette can briefly win foreground
        // focus on some runs even when SetWindowPos uses SWP_NOACTIVATE.
        CreateHandle();
    }

    public void RefreshBindings(AppSettings settings)
    {
        _settings = settings;
        _actionRows.SuspendLayout();
        _actionRows.Controls.Clear();
        foreach (MacroAction action in Enum.GetValues<MacroAction>().Where(action => action != MacroAction.Palette))
        {
            ActionBinding binding = _settings.Bindings[action];
            string input = binding.KeyboardText;
            if (binding.Controller.Count > 0)
                input += "  /  " + binding.ControllerText;
            _actionRows.Controls.Add(new Label
            {
                Text = $"{BindingText.ActionName(action),-18}  {input}",
                Width = 360,
                Height = 34,
                Padding = new Padding(5, 7, 0, 0),
                ForeColor = Color.White,
                BackColor = Color.FromArgb(32, 32, 38),
                Margin = new Padding(0, 0, 0, 5),
                AutoEllipsis = true
            });
        }
        _actionRows.ResumeLayout();
    }

    public void UpdateStatus(string state, string profile)
    {
        _stateLabel.Text = state;
        _stateLabel.ForeColor = state.Contains("Recording", StringComparison.OrdinalIgnoreCase)
            ? Color.FromArgb(255, 100, 100)
            : state.Contains("Playing", StringComparison.OrdinalIgnoreCase)
                ? Color.FromArgb(100, 180, 255)
                : Color.FromArgb(110, 220, 130);
        _profileLabel.Text = "Profile: " + profile;
    }

    public void TogglePalette()
    {
        if (IsPaletteVisible)
            HidePalette();
        else
            ShowPalette();
    }

    public void ShowPalette()
    {
        Rectangle workArea = Screen.PrimaryScreen?.WorkingArea ?? Screen.GetWorkingArea(Cursor.Position);
        Location = new Point(workArea.Right - Width - 24, workArea.Bottom - Height - 24);
        SetWindowPos(Handle, new IntPtr(-1), Left, Top, Width, Height, SwpNoActivate | SwpShowWindow);
        _hideTimer.Stop();
        _hideTimer.Start();
    }

    public void RegisterActivity()
    {
        if (!IsPaletteVisible)
            return;
        _hideTimer.Stop();
        _hideTimer.Start();
    }

    public void HidePalette()
    {
        _hideTimer.Stop();
        if (IsHandleCreated)
            ShowWindow(Handle, SwHide);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
            _hideTimer.Dispose();
        base.Dispose(disposing);
    }

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int command);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);
}

public sealed class MacroStatusChangedEventArgs : EventArgs
{
    public string State { get; }
    public string Profile { get; }

    public MacroStatusChangedEventArgs(string state, string profile)
    {
        State = state;
        Profile = profile;
    }
}
