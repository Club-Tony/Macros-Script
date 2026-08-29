using MacrosApp.Models;

namespace MacrosApp;

public sealed class ChordCaptureDialog : Form
{
    private readonly Label _status;
    private readonly HashSet<Keys> _keyboardCurrent = new();
    private readonly HashSet<Keys> _keyboardCaptured = new();
    private readonly HashSet<ControllerControl> _controllerCaptured = new();
    private readonly System.Windows.Forms.Timer? _controllerTimer;
    private bool _controllerWasDown;

    public IReadOnlyList<Keys> KeyboardChord { get; private set; } = Array.Empty<Keys>();
    public IReadOnlyList<ControllerControl> ControllerChord { get; private set; } = Array.Empty<ControllerControl>();

    private ChordCaptureDialog(bool controller)
    {
        Text = controller ? "Set controller binding" : "Set keyboard binding";
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = false;
        ClientSize = new Size(480, 170);
        BackColor = Color.FromArgb(28, 28, 32);
        ForeColor = Color.White;
        KeyPreview = true;

        var heading = new Label
        {
            Text = controller ? "Press the controller button or chord, then release it." : "Press the keyboard key or chord, then release it.",
            Dock = DockStyle.Top,
            Height = 45,
            Padding = new Padding(18, 15, 18, 0),
            ForeColor = Color.White
        };
        _status = new Label
        {
            Text = controller ? "Waiting for controller input..." : "Waiting for keyboard input...",
            Dock = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleCenter,
            Font = new Font("Segoe UI", 12f, FontStyle.Bold),
            ForeColor = Color.FromArgb(100, 190, 255)
        };
        var cancel = new Button
        {
            Text = "Cancel",
            Dock = DockStyle.Bottom,
            Height = 38,
            DialogResult = DialogResult.Cancel
        };
        Controls.Add(_status);
        Controls.Add(heading);
        Controls.Add(cancel);
        CancelButton = cancel;

        if (controller)
        {
            _controllerTimer = new System.Windows.Forms.Timer { Interval = 30 };
            _controllerTimer.Tick += (_, _) => PollController();
            _controllerTimer.Start();
        }
        else
        {
            KeyDown += CaptureKeyDown;
            KeyUp += CaptureKeyUp;
        }
    }

    public static bool TryCaptureKeyboard(IWin32Window owner, out IReadOnlyList<Keys> chord)
    {
        using var dialog = new ChordCaptureDialog(controller: false);
        bool accepted = dialog.ShowDialog(owner) == DialogResult.OK;
        chord = dialog.KeyboardChord;
        return accepted;
    }

    public static bool TryCaptureController(IWin32Window owner, out IReadOnlyList<ControllerControl> chord)
    {
        using var dialog = new ChordCaptureDialog(controller: true);
        bool accepted = dialog.ShowDialog(owner) == DialogResult.OK;
        chord = dialog.ControllerChord;
        return accepted;
    }

    private void CaptureKeyDown(object? sender, KeyEventArgs e)
    {
        Keys key = BindingText.NormalizeKey(e.KeyCode);
        if (key == Keys.None)
            return;
        _keyboardCurrent.Add(key);
        _keyboardCaptured.Add(key);
        _status.Text = string.Join(" + ", _keyboardCaptured.OrderBy(BindingText.KeySortOrder).Select(BindingText.KeyName));
        e.SuppressKeyPress = true;
        e.Handled = true;
    }

    private void CaptureKeyUp(object? sender, KeyEventArgs e)
    {
        _keyboardCurrent.Remove(BindingText.NormalizeKey(e.KeyCode));
        e.SuppressKeyPress = true;
        e.Handled = true;
        if (_keyboardCaptured.Count > 0 && _keyboardCurrent.Count == 0)
        {
            KeyboardChord = _keyboardCaptured.OrderBy(BindingText.KeySortOrder).ToArray();
            DialogResult = DialogResult.OK;
            Close();
        }
    }

    private void PollController()
    {
        ControllerControl[] down = NativeEngine.TryGetControllerState(0, out ControllerState state) && state.Connected
            ? ControllerControls.FromState(state)
            : Array.Empty<ControllerControl>();
        if (down.Length > 0)
        {
            _controllerWasDown = true;
            _controllerCaptured.UnionWith(down);
            _status.Text = string.Join(" + ", _controllerCaptured.Order().Select(BindingText.ControllerName));
        }
        else if (_controllerWasDown && _controllerCaptured.Count > 0)
        {
            ControllerChord = _controllerCaptured.Order().ToArray();
            DialogResult = DialogResult.OK;
            Close();
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
            _controllerTimer?.Dispose();
        base.Dispose(disposing);
    }
}
