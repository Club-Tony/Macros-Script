using MacrosApp.Controls;
using MacrosApp.Models;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;

namespace MacrosApp;

public sealed class PaletteForm : Form
{
    private const int WsExToolWindow = 0x00000080;
    private const int WsExNoActivate = 0x08000000;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpShowWindow = 0x0040;
    private const int SwHide = 0;
    private static readonly Size CompactSize = new(460, 172);
    private static readonly Size ExpandedSize = new(640, 342);

    private readonly System.Windows.Forms.Timer _hideTimer;
    private readonly System.Windows.Forms.Timer _pulseTimer;
    private AppSettings _settings;
    private string _state = "Idle";
    private string _profile = "Default";
    private HudPresentation _presentation;
    private float _pulse;
    private bool _pulseForward = true;

    public bool UsesNoActivateStyle => (CreateParams.ExStyle & WsExNoActivate) != 0;
    public bool UsesLayeredStyle => (CreateParams.ExStyle & 0x00080000) != 0;
    public bool IsPaletteVisible => IsHandleCreated && IsWindowVisible(Handle);
    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams parameters = base.CreateParams;
            parameters.ExStyle |= WsExToolWindow | WsExNoActivate;
            parameters.ExStyle &= ~0x00080000;
            return parameters;
        }
    }

    public PaletteForm(AppSettings settings)
    {
        _settings = settings;
        Text = "Macros in-game HUD";
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = true;
        ClientSize = CompactSize;
        BackColor = Color.FromArgb(20, 21, 25);
        ForeColor = Color.White;
        SetStyle(
            ControlStyles.AllPaintingInWmPaint |
            ControlStyles.UserPaint |
            ControlStyles.OptimizedDoubleBuffer |
            ControlStyles.ResizeRedraw,
            true);

        _hideTimer = new System.Windows.Forms.Timer { Interval = 15_000 };
        _hideTimer.Tick += (_, _) => HandleHideTimer();
        _pulseTimer = new System.Windows.Forms.Timer { Interval = 45 };
        _pulseTimer.Tick += (_, _) => AdvancePulse();
        CreateHandle();
    }

    public void RefreshBindings(AppSettings settings)
    {
        _settings = settings;
        Invalidate();
    }

    public void UpdateStatus(
        string state,
        string profile,
        HudPresentation presentation = HudPresentation.Compact)
    {
        _state = state;
        _profile = profile;
        _presentation = presentation;
        ApplyAdaptiveSize();
        Invalidate();
    }

    public bool ShouldStayVisible =>
        IsStickyState(_state) || _presentation is HudPresentation.Warning or HudPresentation.Error;

    public bool ShouldToast => _presentation != HudPresentation.Compact || IsNotableState(_state);

    public Bitmap RenderToBitmap()
    {
        var bitmap = new Bitmap(ClientSize.Width, ClientSize.Height, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(bitmap);
        DrawHud(graphics, new Rectangle(Point.Empty, ClientSize));
        return bitmap;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        DrawHud(e.Graphics, ClientRectangle);
    }

    public void TogglePalette()
    {
        if (IsPaletteVisible)
            HidePalette();
        else
            ShowPalette(keepVisible: false);
    }

    public void ShowPalette() => ShowPalette(keepVisible: false);

    public void RegisterActivity()
    {
        if (!IsPaletteVisible || ShouldStayVisible)
            return;
        StartHideTimer();
    }

    public void HidePalette()
    {
        _hideTimer.Stop();
        _pulseTimer.Stop();
        if (IsHandleCreated)
            ShowWindow(Handle, SwHide);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _hideTimer.Dispose();
            _pulseTimer.Dispose();
        }
        base.Dispose(disposing);
    }

    public void ShowPalette(bool keepVisible)
    {
        Rectangle workArea = ResolveTargetWorkArea();
        ShowPaletteAt(
            new Point(workArea.Right - Width - 24, workArea.Bottom - Height - 24),
            keepVisible);
    }

    public void ShowPaletteAt(Point location, bool keepVisible)
    {
        Location = location;
        SetWindowPos(Handle, new IntPtr(-1), Left, Top, Width, Height, SwpNoActivate | SwpShowWindow);
        Invalidate();
        Update();
        _pulseTimer.Start();
        _hideTimer.Stop();
        if (!keepVisible && !ShouldStayVisible)
            StartHideTimer();
    }

    public void AdvanceAnimationForTest()
    {
        _pulse = 0.88f;
        Invalidate();
        Update();
    }

    private void ApplyAdaptiveSize()
    {
        Size next = _presentation == HudPresentation.Compact ? CompactSize : ExpandedSize;
        if (ClientSize != next)
            ClientSize = next;
    }

    private void HandleHideTimer()
    {
        if (_presentation == HudPresentation.SavedActions)
        {
            _presentation = HudPresentation.Compact;
            ApplyAdaptiveSize();
            Invalidate();
            _hideTimer.Interval = 5_000;
            _hideTimer.Start();
            return;
        }
        HidePalette();
    }

    private void StartHideTimer()
    {
        _hideTimer.Stop();
        _hideTimer.Interval = _presentation == HudPresentation.SavedActions ? 8_000 : 15_000;
        _hideTimer.Start();
    }

    private void AdvancePulse()
    {
        _pulse += _pulseForward ? 0.08f : -0.08f;
        if (_pulse >= 1f) { _pulse = 1f; _pulseForward = false; }
        if (_pulse <= 0f) { _pulse = 0f; _pulseForward = true; }
        if (IsPaletteVisible)
            Invalidate();
    }

    private void DrawHud(Graphics graphics, Rectangle bounds)
    {
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        graphics.Clear(Color.FromArgb(20, 21, 25));

        Color accent = PresentationColor();
        using var borderPen = new Pen(accent, 2f);
        using var accentBrush = new SolidBrush(accent);
        using var panelBrush = new SolidBrush(Color.FromArgb(28, 30, 36));
        graphics.FillRectangle(panelBrush, 1, 1, bounds.Width - 2, bounds.Height - 2);
        graphics.DrawRectangle(borderPen, 1, 1, bounds.Width - 3, bounds.Height - 3);
        graphics.FillRectangle(accentBrush, 0, 0, 6, bounds.Height);

        using var titleFont = new Font("Segoe UI", 13.5f, FontStyle.Bold);
        using var statusFont = new Font("Segoe UI", 10f, FontStyle.Bold);
        using var bodyFont = new Font("Segoe UI", 9f);
        using var tinyFont = new Font("Segoe UI", 7.8f);
        using var titleBrush = new SolidBrush(Color.FromArgb(220, 238, 250));
        using var bodyBrush = new SolidBrush(Color.FromArgb(224, 225, 230));
        using var mutedBrush = new SolidBrush(Color.FromArgb(145, 150, 160));
        using var statusBrush = new SolidBrush(accent);
        using var statusFormat = new StringFormat
        {
            FormatFlags = StringFormatFlags.NoWrap,
            Trimming = StringTrimming.EllipsisWord
        };

        graphics.DrawString("MACROS", titleFont, titleBrush, 18, 10);
        graphics.DrawString("Profile: " + _profile, tinyFont, mutedBrush, bounds.Width - 190, 15);
        var statusRect = new RectangleF(18, 42, bounds.Width - 36, _presentation == HudPresentation.Compact ? 48 : 62);
        graphics.DrawString(_state, statusFont, statusBrush, statusRect, statusFormat);

        if (_presentation == HudPresentation.Compact)
        {
            DrawCompactHints(graphics, bodyFont, bodyBrush, mutedBrush, bounds);
            return;
        }

        string guidance = _presentation switch
        {
            HudPresentation.SavedActions => "Recording saved. Choose entirely from the controller:",
            HudPresentation.Warning => "Partial save kept. Use a controller action or Cancel to dismiss:",
            HudPresentation.Error => "No mouse is required. Cancel dismisses this state; setup remains available from the tray.",
            _ => string.Empty
        };
        graphics.DrawString(guidance, bodyFont, bodyBrush, 18, 104);

        DrawActionCard(graphics, new Rectangle(16, 136, 194, 174), MacroAction.Playback, "PLAY SAVED", "Play the saved recording");
        DrawActionCard(graphics, new Rectangle(223, 136, 194, 174), MacroAction.Recorder, "RECORD AGAIN", "Begin another recording");
        DrawActionCard(graphics, new Rectangle(430, 136, 194, 174), MacroAction.Cancel, "CANCEL", "Dismiss or stop");
        graphics.DrawString("Physical controller input continues to pass through to the game.", tinyFont, mutedBrush, 18, bounds.Height - 25);
    }

    private void DrawCompactHints(Graphics graphics, Font font, Brush bodyBrush, Brush mutedBrush, Rectangle bounds)
    {
        graphics.DrawString($"Record  {FormatBinding(MacroAction.Recorder)}", font, bodyBrush, 18, 96);
        graphics.DrawString($"Play  {FormatBinding(MacroAction.Playback)}", font, bodyBrush, 230, 96);
        graphics.DrawString($"Cancel  {FormatBinding(MacroAction.Cancel)}", font, bodyBrush, 18, 121);
        graphics.DrawString("No focus change · input passes through", font, mutedBrush, 230, 121);
        using var footerFont = new Font("Segoe UI", 7.5f);
        graphics.DrawString("HUD auto-hides when idle", footerFont, mutedBrush, 18, bounds.Height - 24);
    }

    private void DrawActionCard(Graphics graphics, Rectangle rect, MacroAction action, string title, string detail)
    {
        ActionBinding binding = _settings.Bindings[action];
        using var background = new SolidBrush(Color.FromArgb(35, 38, 46));
        using var edge = new Pen(Color.FromArgb(65, 72, 86));
        using var titleFont = new Font("Segoe UI", 9f, FontStyle.Bold);
        using var detailFont = new Font("Segoe UI", 7.8f);
        using var titleBrush = new SolidBrush(Color.FromArgb(235, 238, 244));
        using var detailBrush = new SolidBrush(Color.FromArgb(160, 166, 178));
        graphics.FillRectangle(background, rect);
        graphics.DrawRectangle(edge, rect);
        graphics.DrawString(title, titleFont, titleBrush, rect.X + 10, rect.Y + 8);
        graphics.DrawString(detail, detailFont, detailBrush, rect.X + 10, rect.Y + 29);
        ControllerStatePanel.DrawChordRenderer(
            graphics,
            new Rectangle(rect.X + 10, rect.Y + 54, rect.Width - 20, 78),
            binding.Controller,
            _pulse);
        graphics.DrawString(FormatBinding(action), detailFont, titleBrush, rect.X + 10, rect.Bottom - 28);
    }

    private string FormatBinding(MacroAction action)
    {
        ActionBinding binding = _settings.Bindings[action];
        return binding.Controller.Count > 0 ? binding.ControllerText : binding.KeyboardText;
    }

    private Color PresentationColor()
    {
        if (_presentation == HudPresentation.Error)
            return Color.FromArgb(255, 105, 92);
        if (_presentation == HudPresentation.Warning)
            return Color.FromArgb(255, 184, 76);
        if (_state.StartsWith("Recording", StringComparison.OrdinalIgnoreCase))
            return Color.FromArgb(255, 92, 96);
        if (_state.StartsWith("Playing", StringComparison.OrdinalIgnoreCase))
            return Color.FromArgb(82, 168, 255);
        return Color.FromArgb(90, 215, 135);
    }

    private static bool IsStickyState(string state) =>
        state.StartsWith("Recording", StringComparison.OrdinalIgnoreCase) ||
        state.StartsWith("Playing", StringComparison.OrdinalIgnoreCase) ||
        state.StartsWith("Autoclicker running", StringComparison.OrdinalIgnoreCase) ||
        state.Contains(" ON:", StringComparison.Ordinal);

    private static bool IsNotableState(string state) =>
        IsStickyState(state) ||
        state.Contains("Saved", StringComparison.OrdinalIgnoreCase) ||
        state.Contains("unavailable", StringComparison.OrdinalIgnoreCase) ||
        state.Contains("failed", StringComparison.OrdinalIgnoreCase) ||
        state.Contains("discarded", StringComparison.OrdinalIgnoreCase);

    private static Rectangle ResolveTargetWorkArea()
    {
        IntPtr foreground = GetForegroundWindow();
        if (foreground != IntPtr.Zero)
            return Screen.FromHandle(foreground).WorkingArea;
        return Screen.FromPoint(Cursor.Position).WorkingArea;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();
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
    public HudPresentation Presentation { get; }

    public MacroStatusChangedEventArgs(string state, string profile, HudPresentation presentation = HudPresentation.Compact)
    {
        State = state;
        Profile = profile;
        Presentation = presentation;
    }
}
