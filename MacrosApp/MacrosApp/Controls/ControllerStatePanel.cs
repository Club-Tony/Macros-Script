namespace MacrosApp.Controls;

public sealed class ControllerConnectionChangedEventArgs : EventArgs
{
    public ControllerConnectionChangedEventArgs(bool isConnected)
    {
        IsConnected = isConnected;
    }

    public bool IsConnected { get; }
}

public class ControllerStatePanel : UserControl
{
    private const int ConnectedRefreshIntervalMs = 16;
    private const int DisconnectedRefreshIntervalMs = 250;

    private enum HoverRegion
    {
        None,
        Disconnected,
        LeftStick,
        RightStick,
        LeftTrigger,
        RightTrigger,
        AButton,
        BButton,
        XButton,
        YButton,
        DPadUp,
        DPadDown,
        DPadLeft,
        DPadRight,
        LeftBumper,
        RightBumper,
        BackButton,
        StartButton,
        LeftThumbButton,
        RightThumbButton
    }

    private System.Windows.Forms.Timer? _refreshTimer;
    private ControllerState _state;
    private bool _connected;
    private int _deadzone = 7849;
    private int _triggerDeadzone = 30;
    private ToolTip? _toolTip;
    private string _baseToolTipText = string.Empty;
    private string _activeToolTipText = string.Empty;
    private HoverRegion _hoverRegion = HoverRegion.None;
    private bool _pollingAvailable = true;
    private string _statusTitle = "Waiting for controller";
    private string _statusDetail = "Turn on a controller to preview live input.";

    // Colors
    private static readonly Color BgColor = Color.FromArgb(30, 30, 30);
    private static readonly Color BodyFill = Color.FromArgb(42, 42, 42);
    private static readonly Color BodyEdge = Color.FromArgb(82, 82, 82);
    private static readonly Color StickBg = Color.FromArgb(50, 50, 50);
    private static readonly Color StickDot = Color.FromArgb(0, 180, 255);
    private static readonly Color DeadzoneColor = Color.FromArgb(60, 60, 60);
    private static readonly Color TriggerBg = Color.FromArgb(50, 50, 50);
    private static readonly Color TriggerFill = Color.FromArgb(255, 140, 0);
    private static readonly Color ButtonOff = Color.FromArgb(70, 70, 70);
    private static readonly Color ButtonOn = Color.FromArgb(0, 200, 80);
    private static readonly Color TextColor = Color.FromArgb(200, 200, 200);
    private static readonly Color DisconnectedColor = Color.FromArgb(120, 120, 120);
    private static readonly Color DetailTextColor = Color.FromArgb(105, 105, 105);
    private static readonly Color UnavailableColor = Color.FromArgb(200, 130, 50);

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

    public event EventHandler<ControllerConnectionChangedEventArgs>? ConnectionChanged;

    public ControllerStatePanel()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                 ControlStyles.OptimizedDoubleBuffer, true);
        BackColor = BgColor;
        MinimumSize = new Size(320, 180);
        MouseMove += ControllerStatePanel_MouseMove;
        MouseLeave += (_, _) => RestoreBaseToolTip();
    }

    public void StartRefresh()
    {
        if (_refreshTimer != null) return;
        _pollingAvailable = true;
        SetDisconnectedStatus(
            "Waiting for controller",
            "Turn on a controller to preview live input.");

        _refreshTimer = new System.Windows.Forms.Timer { Interval = DisconnectedRefreshIntervalMs };
        _refreshTimer.Tick += (_, _) => PollAndRefresh();
        PollAndRefresh();
        _refreshTimer.Start();
    }

    public void StopRefresh()
    {
        _refreshTimer?.Stop();
        _refreshTimer?.Dispose();
        _refreshTimer = null;
    }

    public void SetUnavailable(string detailText)
    {
        _pollingAvailable = false;
        SetDisconnectedStatus("Controller preview unavailable", detailText);

        bool connectionChanged = _connected;
        _connected = false;
        _state = default;
        UpdateRefreshCadence(false);

        if (connectionChanged)
            ConnectionChanged?.Invoke(this, new ControllerConnectionChangedEventArgs(false));

        Invalidate();
    }

    private void PollAndRefresh()
    {
        if (!Visible || !_pollingAvailable)
            return;

        bool pollOk = NativeEngine.TryGetControllerState(0, out var state);
        bool connected = pollOk && state.Connected;
        ApplyPolledState(connected ? state : default, connected);
    }

    /// <summary>
    /// Manually set the state (for testing without DLL).
    /// </summary>
    public void SetState(ControllerState state, bool connected)
    {
        _pollingAvailable = true;
        ApplyPolledState(connected ? state : default, connected);
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

        const float designW = 620f;
        const float designH = 220f;

        float scale = Math.Min(ClientSize.Width / designW, ClientSize.Height / designH);
        float ox = (ClientSize.Width - designW * scale) / 2f;
        float oy = (ClientSize.Height - designH * scale) / 2f;
        int X(float value) => (int)Math.Round(ox + value * scale);
        int Y(float value) => (int)Math.Round(oy + value * scale);
        int S(float value) => Math.Max(1, (int)Math.Round(value * scale));
        RectangleF Rect(float x, float y, float width, float height) =>
            new(ox + x * scale, oy + y * scale, width * scale, height * scale);

        DrawControllerShell(
            g,
            Rect(82, 36, 456, 132),
            Rect(18, 52, 190, 138),
            Rect(412, 52, 190, 138),
            Rect(92, 118, 118, 82),
            Rect(410, 118, 118, 82),
            S(38));

        DrawTriggerBar(g, X(168), Y(18), S(104), S(12), _state.LeftTrigger, "LT");
        DrawTriggerBar(g, X(348), Y(18), S(104), S(12), _state.RightTrigger, "RT");
        DrawPill(g, X(168), Y(34), S(104), S(20), "LB",
            (_state.Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER) != 0);
        DrawPill(g, X(348), Y(34), S(104), S(20), "RB",
            (_state.Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER) != 0);

        DrawStick(
            g,
            X(145),
            Y(96),
            S(42),
            _state.LeftThumbX,
            _state.LeftThumbY,
            "L",
            (_state.Buttons & XINPUT_GAMEPAD_LEFT_THUMB) != 0);

        DrawDPad(g, X(242), Y(142), S(18), _state.Buttons);

        DrawPill(g, X(282), Y(108), S(36), S(16), "Bk",
            (_state.Buttons & XINPUT_GAMEPAD_BACK) != 0);
        DrawPill(g, X(322), Y(108), S(36), S(16), "St",
            (_state.Buttons & XINPUT_GAMEPAD_START) != 0);

        int btnSize = S(22);
        int btnGap = S(25);
        int faceX = X(405);
        int faceY = Y(96);
        DrawButton(g, faceX, faceY + btnGap, btnSize, "A",
            (_state.Buttons & XINPUT_GAMEPAD_A) != 0, Color.FromArgb(0, 200, 80));
        DrawButton(g, faceX + btnGap, faceY, btnSize, "B",
            (_state.Buttons & XINPUT_GAMEPAD_B) != 0, Color.FromArgb(220, 50, 50));
        DrawButton(g, faceX - btnGap, faceY, btnSize, "X",
            (_state.Buttons & XINPUT_GAMEPAD_X) != 0, Color.FromArgb(50, 110, 220));
        DrawButton(g, faceX, faceY - btnGap, btnSize, "Y",
            (_state.Buttons & XINPUT_GAMEPAD_Y) != 0, Color.FromArgb(220, 200, 0));

        DrawStick(
            g,
            X(475),
            Y(142),
            S(36),
            _state.RightThumbX,
            _state.RightThumbY,
            "R",
            (_state.Buttons & XINPUT_GAMEPAD_RIGHT_THUMB) != 0);
    }

    private void DrawDisconnected(Graphics g)
    {
        using var titleFont = new Font("Segoe UI", 10f, FontStyle.Bold);
        using var detailFont = new Font("Segoe UI", 8.5f);
        using var titleBrush = new SolidBrush(_pollingAvailable ? DisconnectedColor : UnavailableColor);
        using var detailBrush = new SolidBrush(DetailTextColor);

        var titleSize = g.MeasureString(_statusTitle, titleFont);
        var detailSize = g.MeasureString(_statusDetail, detailFont, Math.Max(ClientSize.Width - 36, 120));
        float totalHeight = titleSize.Height + 8 + detailSize.Height;
        float titleX = (ClientSize.Width - titleSize.Width) / 2f;
        float startY = (ClientSize.Height - totalHeight) / 2f;
        var detailRect = new RectangleF(
            18,
            startY + titleSize.Height + 8,
            Math.Max(ClientSize.Width - 36, 120),
            detailSize.Height + 4);

        g.DrawString(_statusTitle, titleFont, titleBrush, titleX, startY);
        using var format = new StringFormat { Alignment = StringAlignment.Center };
        g.DrawString(_statusDetail, detailFont, detailBrush, detailRect, format);
    }

    private static void DrawControllerShell(
        Graphics g,
        RectangleF center,
        RectangleF leftGrip,
        RectangleF rightGrip,
        RectangleF leftHandle,
        RectangleF rightHandle,
        int cornerRadius)
    {
        using var bodyBrush = new SolidBrush(BodyFill);
        using var edgePen = new Pen(BodyEdge, 1.2f);

        using (var centerPath = CreateRoundedRectangle(center, cornerRadius))
        using (var leftHandlePath = CreateRoundedRectangle(leftHandle, cornerRadius))
        using (var rightHandlePath = CreateRoundedRectangle(rightHandle, cornerRadius))
        {
            g.FillEllipse(bodyBrush, leftGrip);
            g.FillEllipse(bodyBrush, rightGrip);
            g.FillPath(bodyBrush, centerPath);
            g.FillPath(bodyBrush, leftHandlePath);
            g.FillPath(bodyBrush, rightHandlePath);

            g.DrawEllipse(edgePen, leftGrip);
            g.DrawEllipse(edgePen, rightGrip);
            g.DrawPath(edgePen, centerPath);
        }
    }

    private void DrawStick(
        Graphics g,
        int cx,
        int cy,
        int radius,
        short rawX,
        short rawY,
        string label,
        bool pressed)
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
        using (var border = new Pen(pressed ? ButtonOn : Color.FromArgb(90, 90, 90), pressed ? 2.5f : 1.2f))
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

    private void DrawTriggerBar(Graphics g, int x, int y, int w, int h, byte value, string label)
    {
        using var bgPath = CreateRoundedRectangle(new RectangleF(x, y, w, h), h);
        using (var bg = new SolidBrush(TriggerBg))
            g.FillPath(bg, bgPath);

        float ratio = value / 255f;
        int fillW = Math.Max(0, (int)(w * ratio));
        if (fillW > 0)
        {
            using var fillPath = CreateRoundedRectangle(new RectangleF(x, y, fillW, h), h);
            using var fill = new SolidBrush(TriggerFill);
            g.FillPath(fill, fillPath);
        }

        float dzRatio = _triggerDeadzone / 255f;
        int dzX = x + (int)(w * dzRatio);
        using (var dzPen = new Pen(DeadzoneColor, 1f))
            g.DrawLine(dzPen, dzX, y, dzX, y + h);

        using (var border = new Pen(Color.FromArgb(80, 80, 80), 1f))
            g.DrawPath(border, bgPath);

        using var font = new Font("Segoe UI", 7f);
        using var textBrush = new SolidBrush(TextColor);
        var size = g.MeasureString(label, font);
        g.DrawString(label, font, textBrush, x + (w - size.Width) / 2, y - size.Height - 1);
    }

    private void DrawDPad(Graphics g, int cx, int cy, int unit, ushort buttons)
    {
        int arm = unit;
        int length = unit * 2;
        DrawDPadPart(g, new Rectangle(cx - arm / 2, cy - length - arm / 2, arm, length), "U",
            (buttons & XINPUT_GAMEPAD_DPAD_UP) != 0);
        DrawDPadPart(g, new Rectangle(cx - arm / 2, cy + arm / 2, arm, length), "D",
            (buttons & XINPUT_GAMEPAD_DPAD_DOWN) != 0);
        DrawDPadPart(g, new Rectangle(cx - length - arm / 2, cy - arm / 2, length, arm), "L",
            (buttons & XINPUT_GAMEPAD_DPAD_LEFT) != 0);
        DrawDPadPart(g, new Rectangle(cx + arm / 2, cy - arm / 2, length, arm), "R",
            (buttons & XINPUT_GAMEPAD_DPAD_RIGHT) != 0);

        using var centerPath = CreateRoundedRectangle(new RectangleF(cx - arm / 2f, cy - arm / 2f, arm, arm), arm / 4f);
        using var centerBrush = new SolidBrush(Color.FromArgb(58, 58, 58));
        g.FillPath(centerBrush, centerPath);
    }

    private void DrawDPadPart(Graphics g, Rectangle rect, string label, bool pressed)
    {
        using var path = CreateRoundedRectangle(rect, Math.Max(3f, rect.Height / 4f));
        using var brush = new SolidBrush(pressed ? ButtonOn : ButtonOff);
        using var border = new Pen(Color.FromArgb(92, 92, 92), 1f);
        g.FillPath(brush, path);
        g.DrawPath(border, path);

        using var font = new Font("Segoe UI", 6.5f, FontStyle.Bold);
        using var textBrush = new SolidBrush(pressed ? Color.White : TextColor);
        var textSize = g.MeasureString(label, font);
        g.DrawString(label, font, textBrush, rect.Left + (rect.Width - textSize.Width) / 2f, rect.Top + (rect.Height - textSize.Height) / 2f);
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

    public void ApplyToolTip(ToolTip toolTip, string text)
    {
        _toolTip = toolTip;
        _baseToolTipText = text;
        _activeToolTipText = text;
        toolTip.SetToolTip(this, text);
    }

    private void ControllerStatePanel_MouseMove(object? sender, MouseEventArgs e)
    {
        if (_toolTip == null)
            return;

        HoverRegion region = HitTestRegion(e.Location);
        if (region == _hoverRegion)
            return;

        _hoverRegion = region;
        string text = region == HoverRegion.None ? _baseToolTipText : GetToolTipText(region);
        if (text == _activeToolTipText)
            return;

        _activeToolTipText = text;
        _toolTip.SetToolTip(this, text);
    }

    private void RestoreBaseToolTip()
    {
        if (_toolTip == null)
            return;

        _hoverRegion = HoverRegion.None;
        if (_activeToolTipText == _baseToolTipText)
            return;

        _activeToolTipText = _baseToolTipText;
        _toolTip.SetToolTip(this, _baseToolTipText);
    }

    private HoverRegion HitTestRegion(Point point)
    {
        if (!_connected)
            return HoverRegion.Disconnected;

        if (ClientSize.Width <= 0 || ClientSize.Height <= 0)
            return HoverRegion.None;

        const float designW = 620f;
        const float designH = 220f;

        float scale = Math.Min(ClientSize.Width / designW, ClientSize.Height / designH);
        float ox = (ClientSize.Width - designW * scale) / 2f;
        float oy = (ClientSize.Height - designH * scale) / 2f;
        int X(float value) => (int)Math.Round(ox + value * scale);
        int Y(float value) => (int)Math.Round(oy + value * scale);
        int S(float value) => Math.Max(1, (int)Math.Round(value * scale));

        int leftStickX = X(145);
        int leftStickY = Y(96);
        int leftStickRadius = S(42);
        int rightStickX = X(475);
        int rightStickY = Y(142);
        int rightStickRadius = S(36);
        int dpadX = X(242);
        int dpadY = Y(142);
        int dpadUnit = S(18);
        int faceX = X(405);
        int faceY = Y(96);
        int faceGap = S(25);
        int faceRadius = S(22) / 2;

        if (PointInCircle(point, leftStickX, leftStickY, S(15)))
            return HoverRegion.LeftThumbButton;
        if (PointInCircle(point, rightStickX, rightStickY, S(14)))
            return HoverRegion.RightThumbButton;
        if (PointInCircle(point, leftStickX, leftStickY, leftStickRadius))
            return HoverRegion.LeftStick;
        if (PointInCircle(point, rightStickX, rightStickY, rightStickRadius))
            return HoverRegion.RightStick;

        if (new Rectangle(X(168), Y(18), S(104), S(12)).Contains(point))
            return HoverRegion.LeftTrigger;
        if (new Rectangle(X(348), Y(18), S(104), S(12)).Contains(point))
            return HoverRegion.RightTrigger;

        if (new Rectangle(dpadX - dpadUnit / 2, dpadY - dpadUnit * 2 - dpadUnit / 2, dpadUnit, dpadUnit * 2).Contains(point))
            return HoverRegion.DPadUp;
        if (new Rectangle(dpadX - dpadUnit / 2, dpadY + dpadUnit / 2, dpadUnit, dpadUnit * 2).Contains(point))
            return HoverRegion.DPadDown;
        if (new Rectangle(dpadX - dpadUnit * 2 - dpadUnit / 2, dpadY - dpadUnit / 2, dpadUnit * 2, dpadUnit).Contains(point))
            return HoverRegion.DPadLeft;
        if (new Rectangle(dpadX + dpadUnit / 2, dpadY - dpadUnit / 2, dpadUnit * 2, dpadUnit).Contains(point))
            return HoverRegion.DPadRight;

        if (PointInCircle(point, faceX, faceY + faceGap, faceRadius))
            return HoverRegion.AButton;
        if (PointInCircle(point, faceX + faceGap, faceY, faceRadius))
            return HoverRegion.BButton;
        if (PointInCircle(point, faceX - faceGap, faceY, faceRadius))
            return HoverRegion.XButton;
        if (PointInCircle(point, faceX, faceY - faceGap, faceRadius))
            return HoverRegion.YButton;

        if (new Rectangle(X(168), Y(34), S(104), S(20)).Contains(point))
            return HoverRegion.LeftBumper;
        if (new Rectangle(X(348), Y(34), S(104), S(20)).Contains(point))
            return HoverRegion.RightBumper;
        if (new Rectangle(X(282), Y(108), S(36), S(16)).Contains(point))
            return HoverRegion.BackButton;
        if (new Rectangle(X(322), Y(108), S(36), S(16)).Contains(point))
            return HoverRegion.StartButton;

        return HoverRegion.None;
    }

    private string GetToolTipText(HoverRegion region)
    {
        return region switch
        {
            HoverRegion.Disconnected => _pollingAvailable
                ? "No XInput controller is connected right now. Turn one on and the live view will update automatically."
                : "Controller preview is unavailable because the native engine is not ready for controller polling.",
            HoverRegion.LeftStick => $"Left stick input. The dot shows live X/Y position and the ring shows the thumb deadzone. Current raw: X={_state.LeftThumbX}, Y={_state.LeftThumbY}.",
            HoverRegion.RightStick => $"Right stick input. The dot shows live X/Y position and the ring shows the thumb deadzone. Current raw: X={_state.RightThumbX}, Y={_state.RightThumbY}.",
            HoverRegion.LeftTrigger => $"Left trigger input from 0 to 255. Current value: {_state.LeftTrigger}.",
            HoverRegion.RightTrigger => $"Right trigger input from 0 to 255. Current value: {_state.RightTrigger}.",
            HoverRegion.AButton => GetButtonText("A", "bottom face button", (_state.Buttons & XINPUT_GAMEPAD_A) != 0),
            HoverRegion.BButton => GetButtonText("B", "right face button", (_state.Buttons & XINPUT_GAMEPAD_B) != 0),
            HoverRegion.XButton => GetButtonText("X", "left face button", (_state.Buttons & XINPUT_GAMEPAD_X) != 0),
            HoverRegion.YButton => GetButtonText("Y", "top face button", (_state.Buttons & XINPUT_GAMEPAD_Y) != 0),
            HoverRegion.DPadUp => GetButtonText("D-pad up", "menu/navigation button", (_state.Buttons & XINPUT_GAMEPAD_DPAD_UP) != 0),
            HoverRegion.DPadDown => GetButtonText("D-pad down", "menu/navigation button", (_state.Buttons & XINPUT_GAMEPAD_DPAD_DOWN) != 0),
            HoverRegion.DPadLeft => GetButtonText("D-pad left", "menu/navigation button", (_state.Buttons & XINPUT_GAMEPAD_DPAD_LEFT) != 0),
            HoverRegion.DPadRight => GetButtonText("D-pad right", "menu/navigation button", (_state.Buttons & XINPUT_GAMEPAD_DPAD_RIGHT) != 0),
            HoverRegion.LeftBumper => GetButtonText("LB", "left bumper", (_state.Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER) != 0),
            HoverRegion.RightBumper => GetButtonText("RB", "right bumper", (_state.Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER) != 0),
            HoverRegion.BackButton => GetButtonText("Back", "back/share button", (_state.Buttons & XINPUT_GAMEPAD_BACK) != 0),
            HoverRegion.StartButton => GetButtonText("Start", "start/options button", (_state.Buttons & XINPUT_GAMEPAD_START) != 0),
            HoverRegion.LeftThumbButton => GetButtonText("Left stick click", "left thumb button", (_state.Buttons & XINPUT_GAMEPAD_LEFT_THUMB) != 0),
            HoverRegion.RightThumbButton => GetButtonText("Right stick click", "right thumb button", (_state.Buttons & XINPUT_GAMEPAD_RIGHT_THUMB) != 0),
            _ => _baseToolTipText
        };
    }

    private static string GetButtonText(string label, string role, bool pressed)
    {
        return $"{label} button ({role}). Current state: {(pressed ? "pressed" : "released")}.";
    }

    private static bool PointInCircle(Point point, int centerX, int centerY, int radius)
    {
        int dx = point.X - centerX;
        int dy = point.Y - centerY;
        return (dx * dx) + (dy * dy) <= radius * radius;
    }

    private static System.Drawing.Drawing2D.GraphicsPath CreateRoundedRectangle(RectangleF rect, float radius)
    {
        float diameter = Math.Min(radius * 2f, Math.Min(rect.Width, rect.Height));
        var path = new System.Drawing.Drawing2D.GraphicsPath();

        if (diameter <= 0)
        {
            path.AddRectangle(rect);
            return path;
        }

        path.AddArc(rect.Left, rect.Top, diameter, diameter, 180, 90);
        path.AddArc(rect.Right - diameter, rect.Top, diameter, diameter, 270, 90);
        path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(rect.Left, rect.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    private void ApplyPolledState(ControllerState state, bool connected)
    {
        bool connectionChanged = connected != _connected;
        bool stateChanged = connected && !StatesEqual(_state, state);

        if (!connected)
        {
            SetDisconnectedStatus(
                "Waiting for controller",
                "Turn on a controller to preview live input.");
        }

        _connected = connected;
        _state = connected ? state : default;
        UpdateRefreshCadence(connected);

        if (connectionChanged)
            ConnectionChanged?.Invoke(this, new ControllerConnectionChangedEventArgs(connected));

        if (connectionChanged || stateChanged)
            Invalidate();
    }

    private void UpdateRefreshCadence(bool connected)
    {
        if (_refreshTimer == null)
            return;

        int targetInterval = connected ? ConnectedRefreshIntervalMs : DisconnectedRefreshIntervalMs;
        if (_refreshTimer.Interval != targetInterval)
            _refreshTimer.Interval = targetInterval;
    }

    private void SetDisconnectedStatus(string title, string detail)
    {
        _statusTitle = title;
        _statusDetail = detail;
    }

    private static bool StatesEqual(ControllerState left, ControllerState right)
    {
        return left.Connected == right.Connected &&
               left.Buttons == right.Buttons &&
               left.LeftThumbX == right.LeftThumbX &&
               left.LeftThumbY == right.LeftThumbY &&
               left.RightThumbX == right.RightThumbX &&
               left.RightThumbY == right.RightThumbY &&
               left.LeftTrigger == right.LeftTrigger &&
               left.RightTrigger == right.RightTrigger;
    }
}
