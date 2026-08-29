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
    private const int WsExLayered = 0x00080000;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpShowWindow = 0x0040;
    private const int SwHide = 0;
    private const int UlwAlpha = 0x00000002;
    private const byte AcSrcOver = 0x00;
    private const byte AcSrcAlpha = 0x01;
    private const int HudWidth = 400;
    private const int HudHeight = 214;

    private readonly System.Windows.Forms.Timer _hideTimer;
    private AppSettings _settings;
    private string _state = "Idle";
    private string _profile = "Default";

    public bool UsesNoActivateStyle => (CreateParams.ExStyle & WsExNoActivate) != 0;
    public bool IsPaletteVisible => IsHandleCreated && IsWindowVisible(Handle);

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams parameters = base.CreateParams;
            parameters.ExStyle |= WsExToolWindow | WsExNoActivate | WsExLayered;
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
        ClientSize = new Size(HudWidth, HudHeight);
        BackColor = Color.Black;
        ForeColor = Color.White;

        _hideTimer = new System.Windows.Forms.Timer { Interval = 15_000 };
        _hideTimer.Tick += (_, _) => HidePalette();
        // Create the hidden no-activate window before any gameplay-time show.
        CreateHandle();
    }

    public void RefreshBindings(AppSettings settings)
    {
        _settings = settings;
        if (IsPaletteVisible)
            PresentHud();
    }

    public void UpdateStatus(string state, string profile)
    {
        _state = state;
        _profile = profile;
        if (IsPaletteVisible)
            PresentHud();
    }

    public bool ShouldStayVisible => IsStickyState(_state);

    public bool ShouldToast => IsNotableState(_state);

    public Bitmap RenderToBitmap()
    {
        var bitmap = new Bitmap(HudWidth, HudHeight, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        graphics.Clear(Color.Transparent);

        using var border = new SolidBrush(Color.FromArgb(230, 70, 105, 145));
        using var body = new SolidBrush(Color.FromArgb(235, 24, 24, 29));
        graphics.FillRectangle(border, 0, 0, HudWidth, HudHeight);
        graphics.FillRectangle(body, 1, 1, HudWidth - 2, HudHeight - 2);

        using var titleFont = new Font("Segoe UI", 14f, FontStyle.Bold);
        using var bodyFont = new Font("Segoe UI", 10f, FontStyle.Regular);
        using var hintFont = new Font("Segoe UI", 9f, FontStyle.Regular);
        using var footerFont = new Font("Segoe UI", 8f, FontStyle.Regular);
        using var titleBrush = new SolidBrush(Color.FromArgb(115, 205, 255));
        using var stateBrush = new SolidBrush(StateColor(_state));
        using var mutedBrush = new SolidBrush(Color.FromArgb(180, 180, 185));
        using var hintBrush = new SolidBrush(Color.FromArgb(230, 230, 235));
        using var footerBrush = new SolidBrush(Color.FromArgb(130, 130, 138));

        graphics.DrawString("MACROS", titleFont, titleBrush, 14, 10);
        graphics.DrawString(_state, bodyFont, stateBrush, 14, 40);
        graphics.DrawString("Profile: " + _profile, hintFont, mutedBrush, 14, 64);

        float y = 92;
        foreach (string line in BuildHintLines())
        {
            graphics.DrawString(line, hintFont, hintBrush, 14, y);
            y += 22;
        }

        graphics.DrawString(
            "Bindings pass through to the game  |  Palette hides after 15 seconds",
            footerFont,
            footerBrush,
            14,
            HudHeight - 28);

        return bitmap;
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

    public void ShowPalette(bool keepVisible)
    {
        Rectangle workArea = ResolveTargetWorkArea();
        Location = new Point(workArea.Right - Width - 24, workArea.Bottom - Height - 24);
        SetWindowPos(Handle, new IntPtr(-1), Left, Top, Width, Height, SwpNoActivate | SwpShowWindow);
        PresentHud();
        _hideTimer.Stop();
        if (!keepVisible)
            _hideTimer.Start();
    }

    private void PresentHud()
    {
        if (!IsHandleCreated)
            return;

        try
        {
            PresentHudCore();
        }
        catch (Exception)
        {
        }
    }

    private void PresentHudCore()
    {
        using var bitmap = RenderToBitmap();
        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memoryDc = CreateCompatibleDC(screenDc);
        IntPtr bitmapHandle = bitmap.GetHbitmap(Color.FromArgb(0));
        IntPtr previous = SelectObject(memoryDc, bitmapHandle);
        try
        {
            var size = new Size(bitmap.Width, bitmap.Height);
            var source = Point.Empty;
            var destination = new Point(Left, Top);
            var blend = new BlendFunction
            {
                BlendOp = AcSrcOver,
                BlendFlags = 0,
                SourceConstantAlpha = 255,
                AlphaFormat = AcSrcAlpha
            };
            UpdateLayeredWindow(Handle, screenDc, ref destination, ref size, memoryDc, ref source, 0, ref blend, UlwAlpha);
        }
        finally
        {
            SelectObject(memoryDc, previous);
            DeleteObject(bitmapHandle);
            DeleteDC(memoryDc);
            ReleaseDC(IntPtr.Zero, screenDc);
        }
    }

    private IEnumerable<string> BuildHintLines()
    {
        yield return FormatHint(MacroAction.Recorder);
        yield return FormatHint(MacroAction.Playback);
        yield return FormatHint(MacroAction.Cancel);
    }

    private string FormatHint(MacroAction action)
    {
        ActionBinding binding = _settings.Bindings[action];
        string input = binding.KeyboardText;
        if (binding.Controller.Count > 0)
            input += "  /  " + binding.ControllerText;
        return $"{BindingText.ActionName(action),-16}  {input}";
    }

    private static bool IsStickyState(string state) =>
        state.StartsWith("Recording", StringComparison.OrdinalIgnoreCase) ||
        state.StartsWith("Playing:", StringComparison.OrdinalIgnoreCase) ||
        state.StartsWith("Autoclicker running", StringComparison.OrdinalIgnoreCase) ||
        state.Contains(" ON:", StringComparison.Ordinal);

    private static bool IsNotableState(string state) =>
        IsStickyState(state) ||
        state.Contains("Saved", StringComparison.OrdinalIgnoreCase) ||
        state.Contains("Error", StringComparison.OrdinalIgnoreCase) ||
        state.Contains("unavailable", StringComparison.OrdinalIgnoreCase) ||
        state.Contains("failed", StringComparison.OrdinalIgnoreCase) ||
        state.Contains("discarded", StringComparison.OrdinalIgnoreCase);

    private static Color StateColor(string state)
    {
        if (state.StartsWith("Recording", StringComparison.OrdinalIgnoreCase))
            return Color.FromArgb(255, 100, 100);
        if (state.StartsWith("Playing:", StringComparison.OrdinalIgnoreCase))
            return Color.FromArgb(100, 180, 255);
        if (state.Contains("unavailable", StringComparison.OrdinalIgnoreCase) ||
            state.Contains("failed", StringComparison.OrdinalIgnoreCase) ||
            state.Contains("Error", StringComparison.OrdinalIgnoreCase))
            return Color.FromArgb(255, 170, 80);
        return Color.FromArgb(110, 220, 130);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BlendFunction
    {
        public byte BlendOp;
        public byte BlendFlags;
        public byte SourceConstantAlpha;
        public byte AlphaFormat;
    }

    private static Rectangle ResolveTargetWorkArea()
    {
        IntPtr foreground = GetForegroundWindow();
        if (foreground != IntPtr.Zero)
        {
            Screen screen = Screen.FromHandle(foreground);
            if (screen != null)
                return screen.WorkingArea;
        }

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

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UpdateLayeredWindow(
        IntPtr hwnd,
        IntPtr hdcDst,
        ref Point pptDst,
        ref Size psize,
        IntPtr hdcSrc,
        ref Point pptSrc,
        int crKey,
        ref BlendFunction pblend,
        int dwFlags);

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDc);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateCompatibleDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    private static extern IntPtr SelectObject(IntPtr hdc, IntPtr hgdiobj);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr hObject);
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
