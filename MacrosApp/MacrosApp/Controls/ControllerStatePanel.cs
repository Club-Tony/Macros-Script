namespace MacrosApp.Controls;

public class ControllerStatePanel : UserControl
{
    private System.Windows.Forms.Timer? _refreshTimer;
    private ControllerState _state;
    private bool _connected;
    private int _deadzone = 7849;
    private int _triggerDeadzone = 30;

    // Colors
    private static readonly Color BgColor = Color.FromArgb(30, 30, 30);
    private static readonly Color StickBg = Color.FromArgb(50, 50, 50);
    private static readonly Color StickDot = Color.FromArgb(0, 180, 255);
    private static readonly Color DeadzoneColor = Color.FromArgb(60, 60, 60);
    private static readonly Color TriggerBg = Color.FromArgb(50, 50, 50);
    private static readonly Color TriggerFill = Color.FromArgb(255, 140, 0);
    private static readonly Color ButtonOff = Color.FromArgb(70, 70, 70);
    private static readonly Color ButtonOn = Color.FromArgb(0, 200, 80);
    private static readonly Color TextColor = Color.FromArgb(200, 200, 200);
    private static readonly Color DisconnectedColor = Color.FromArgb(120, 120, 120);

    // Xbox button masks
    private const ushort XINPUT_GAMEPAD_DPAD_UP = 0x0001;
    private const ushort XINPUT_GAMEPAD_DPAD_DOWN = 0x0002;
    private const ushort XINPUT_GAMEPAD_DPAD_LEFT = 0x0004;
    private const ushort XINPUT_GAMEPAD_DPAD_RIGHT = 0x0008;
    private const ushort XINPUT_GAMEPAD_START = 0x0010;
    private const ushort XINPUT_GAMEPAD_BACK = 0x0020;
    private const ushort XINPUT_GAMEPAD_LEFT_THUMB = 0x0040;
    private const ushort XINPUT_GAMEPAD_RIGHT_THUMB = 0x0080;
    private const ushort XINPUT_GAMEPAD_LEFT_SHOULDER = 0x0100;
    private const ushort XINPUT_GAMEPAD_RIGHT_SHOULDER = 0x0200;
    private const ushort XINPUT_GAMEPAD_A = 0x1000;
    private const ushort XINPUT_GAMEPAD_B = 0x2000;
    private const ushort XINPUT_GAMEPAD_X = 0x4000;
    private const ushort XINPUT_GAMEPAD_Y = 0x8000;

    public int ThumbDeadzone
    {
        get => _deadzone;
        set { _deadzone = value; Invalidate(); }
    }

    public int TriggerDeadzone
    {
        get => _triggerDeadzone;
        set { _triggerDeadzone = value; Invalidate(); }
    }

    public ControllerStatePanel()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                 ControlStyles.OptimizedDoubleBuffer, true);
        BackColor = BgColor;
        MinimumSize = new Size(320, 180);
    }

    public void StartRefresh()
    {
        if (_refreshTimer != null) return;
        _refreshTimer = new System.Windows.Forms.Timer { Interval = 16 }; // ~60fps
        _refreshTimer.Tick += (_, _) => PollAndRefresh();
        _refreshTimer.Start();
    }

    public void StopRefresh()
    {
        _refreshTimer?.Stop();
        _refreshTimer?.Dispose();
        _refreshTimer = null;
    }

    private void PollAndRefresh()
    {
        if (!Visible) return;
        _connected = NativeEngine.TryGetControllerState(0, out _state);
        Invalidate();
    }

    /// <summary>
    /// Manually set the state (for testing without DLL).
    /// </summary>
    public void SetState(ControllerState state, bool connected)
    {
        _state = state;
        _connected = connected;
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;

        if (!_connected)
        {
            DrawDisconnected(g);
            return;
        }

        int w = ClientSize.Width;
        int h = ClientSize.Height;

        // Layout regions
        int stickRadius = Math.Min(w / 6, h / 3);
        int padding = 10;

        // Left stick
        int lx = padding + stickRadius;
        int ly = h / 2;
        DrawStick(g, lx, ly, stickRadius, _state.LeftThumbX, _state.LeftThumbY, "L");

        // Right stick
        int rx = w - padding - stickRadius;
        int ry = h / 2;
        DrawStick(g, rx, ry, stickRadius, _state.RightThumbX, _state.RightThumbY, "R");

        // Triggers (between sticks, top)
        int triggerW = 30;
        int triggerH = h - 40;
        int triggerY = 20;
        int centerX = w / 2;
        DrawTrigger(g, centerX - 50, triggerY, triggerW, triggerH, _state.LeftTrigger, "LT");
        DrawTrigger(g, centerX + 20, triggerY, triggerW, triggerH, _state.RightTrigger, "RT");

        // Buttons (center area)
        int btnSize = 14;
        int btnCenterX = centerX;
        int btnCenterY = h / 2 + 15;

        // Face buttons (A/B/X/Y) - diamond layout
        DrawButton(g, btnCenterX, btnCenterY + btnSize + 4, btnSize, "A",
            (_state.Buttons & XINPUT_GAMEPAD_A) != 0, Color.FromArgb(0, 200, 80));
        DrawButton(g, btnCenterX + btnSize + 4, btnCenterY, btnSize, "B",
            (_state.Buttons & XINPUT_GAMEPAD_B) != 0, Color.FromArgb(220, 50, 50));
        DrawButton(g, btnCenterX - btnSize - 4, btnCenterY, btnSize, "X",
            (_state.Buttons & XINPUT_GAMEPAD_X) != 0, Color.FromArgb(50, 100, 220));
        DrawButton(g, btnCenterX, btnCenterY - btnSize - 4, btnSize, "Y",
            (_state.Buttons & XINPUT_GAMEPAD_Y) != 0, Color.FromArgb(220, 200, 0));

        // Bumpers
        int bumperY = 8;
        DrawPill(g, centerX - 90, bumperY, 50, 14, "LB",
            (_state.Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER) != 0);
        DrawPill(g, centerX + 40, bumperY, 50, 14, "RB",
            (_state.Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER) != 0);

        // Start / Back
        DrawPill(g, centerX - 40, h - 24, 30, 12, "Bk",
            (_state.Buttons & XINPUT_GAMEPAD_BACK) != 0);
        DrawPill(g, centerX + 10, h - 24, 30, 12, "St",
            (_state.Buttons & XINPUT_GAMEPAD_START) != 0);
    }

    private void DrawDisconnected(Graphics g)
    {
        using var font = new Font("Segoe UI", 10f);
        using var brush = new SolidBrush(DisconnectedColor);
        var text = "Controller not connected";
        var size = g.MeasureString(text, font);
        g.DrawString(text, font, brush,
            (ClientSize.Width - size.Width) / 2,
            (ClientSize.Height - size.Height) / 2);
    }

    private void DrawStick(Graphics g, int cx, int cy, int radius, short rawX, short rawY, string label)
    {
        // Background circle
        using (var bg = new SolidBrush(StickBg))
            g.FillEllipse(bg, cx - radius, cy - radius, radius * 2, radius * 2);

        // Deadzone ring
        float dzRatio = _deadzone / 32767f;
        int dzRadius = (int)(radius * dzRatio);
        using (var dzPen = new Pen(DeadzoneColor, 1.5f))
            g.DrawEllipse(dzPen, cx - dzRadius, cy - dzRadius, dzRadius * 2, dzRadius * 2);

        // Border
        using (var border = new Pen(Color.FromArgb(80, 80, 80), 1f))
            g.DrawEllipse(border, cx - radius, cy - radius, radius * 2, radius * 2);

        // Stick position dot
        float nx = rawX / 32767f;
        float ny = -rawY / 32767f; // Y is inverted
        int dotX = cx + (int)(nx * radius * 0.9f);
        int dotY = cy + (int)(ny * radius * 0.9f);
        int dotSize = 8;

        using (var dot = new SolidBrush(StickDot))
            g.FillEllipse(dot, dotX - dotSize / 2, dotY - dotSize / 2, dotSize, dotSize);

        // Label
        using var font = new Font("Segoe UI", 7f);
        using var textBrush = new SolidBrush(TextColor);
        g.DrawString(label, font, textBrush, cx - 4, cy + radius + 2);
    }

    private void DrawTrigger(Graphics g, int x, int y, int w, int h, byte value, string label)
    {
        // Background
        using (var bg = new SolidBrush(TriggerBg))
            g.FillRectangle(bg, x, y, w, h);

        // Deadzone line
        float dzRatio = _triggerDeadzone / 255f;
        int dzY = y + h - (int)(h * dzRatio);
        using (var dzPen = new Pen(DeadzoneColor, 1f))
            g.DrawLine(dzPen, x, dzY, x + w, dzY);

        // Fill from bottom
        float ratio = value / 255f;
        int fillH = (int)(h * ratio);
        using (var fill = new SolidBrush(TriggerFill))
            g.FillRectangle(fill, x, y + h - fillH, w, fillH);

        // Border
        using (var border = new Pen(Color.FromArgb(80, 80, 80), 1f))
            g.DrawRectangle(border, x, y, w, h);

        // Label
        using var font = new Font("Segoe UI", 7f);
        using var textBrush = new SolidBrush(TextColor);
        var size = g.MeasureString(label, font);
        g.DrawString(label, font, textBrush, x + (w - size.Width) / 2, y + h + 2);
    }

    private void DrawButton(Graphics g, int cx, int cy, int size, string label, bool pressed, Color activeColor)
    {
        var color = pressed ? activeColor : ButtonOff;
        using (var brush = new SolidBrush(color))
            g.FillEllipse(brush, cx - size / 2, cy - size / 2, size, size);

        using var font = new Font("Segoe UI", 7f, FontStyle.Bold);
        using var textBrush = new SolidBrush(pressed ? Color.White : TextColor);
        var textSize = g.MeasureString(label, font);
        g.DrawString(label, font, textBrush, cx - textSize.Width / 2, cy - textSize.Height / 2);
    }

    private void DrawPill(Graphics g, int x, int y, int w, int h, string label, bool pressed)
    {
        var color = pressed ? ButtonOn : ButtonOff;
        using (var brush = new SolidBrush(color))
        using (var path = new System.Drawing.Drawing2D.GraphicsPath())
        {
            path.AddArc(x, y, h, h, 90, 180);
            path.AddArc(x + w - h, y, h, h, 270, 180);
            path.CloseFigure();
            g.FillPath(brush, path);
        }

        using var font = new Font("Segoe UI", 7f);
        using var textBrush = new SolidBrush(pressed ? Color.White : TextColor);
        var textSize = g.MeasureString(label, font);
        g.DrawString(label, font, textBrush, x + (w - textSize.Width) / 2, y + (h - textSize.Height) / 2);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
            StopRefresh();
        base.Dispose(disposing);
    }
}
