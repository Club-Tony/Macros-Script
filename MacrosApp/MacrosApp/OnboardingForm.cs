using MacrosApp.Models;

namespace MacrosApp;

public sealed class OnboardingForm : Form
{
    private readonly AppSettings _settings;
    private readonly Label _keyboardValue;
    private readonly Label _controllerValue;

    public OnboardingForm(AppSettings settings)
    {
        _settings = settings;
        Text = "Set up Macros";
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(640, 470);
        BackColor = Color.FromArgb(24, 24, 28);
        ForeColor = Color.White;

        var title = new Label
        {
            Text = "Choose your in-game launch bindings",
            Dock = DockStyle.Top,
            Height = 62,
            Font = new Font("Segoe UI", 17f, FontStyle.Bold),
            Padding = new Padding(20, 18, 0, 0)
        };
        var description = new Label
        {
            Text = "The launch binding opens a compact palette without taking focus from your game. Single inputs are allowed; multi-input chords are recommended to prevent accidental activation.",
            Dock = DockStyle.Top,
            Height = 72,
            Padding = new Padding(22, 8, 22, 8),
            ForeColor = Color.FromArgb(195, 195, 200)
        };

        var bindings = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 180,
            Padding = new Padding(20),
            ColumnCount = 4,
            RowCount = 2
        };
        bindings.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
        bindings.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        bindings.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 78));
        bindings.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 78));
        bindings.RowStyles.Add(new RowStyle(SizeType.Percent, 50));
        bindings.RowStyles.Add(new RowStyle(SizeType.Percent, 50));

        _keyboardValue = ValueLabel();
        _controllerValue = ValueLabel();
        bindings.Controls.Add(RowLabel("Keyboard"), 0, 0);
        bindings.Controls.Add(_keyboardValue, 1, 0);
        bindings.Controls.Add(ActionButton("Set", (_, _) => SetKeyboard()), 2, 0);
        bindings.Controls.Add(ActionButton("Reset", (_, _) => ResetKeyboard()), 3, 0);
        bindings.Controls.Add(RowLabel("Controller"), 0, 1);
        bindings.Controls.Add(_controllerValue, 1, 1);
        bindings.Controls.Add(ActionButton("Set", (_, _) => SetController()), 2, 1);
        bindings.Controls.Add(ActionButton("Clear", (_, _) => ClearController()), 3, 1);

        var bottom = new FlowLayoutPanel
        {
            Dock = DockStyle.Bottom,
            Height = 64,
            Padding = new Padding(12),
            FlowDirection = FlowDirection.RightToLeft,
            BackColor = Color.FromArgb(30, 30, 34)
        };
        var continueButton = new Button { Text = "Continue", Width = 110, Height = 36, DialogResult = DialogResult.OK };
        var laterButton = new Button { Text = "Later", Width = 90, Height = 36, DialogResult = DialogResult.Ignore };
        bottom.Controls.Add(continueButton);
        bottom.Controls.Add(laterButton);
        AcceptButton = continueButton;

        Controls.Add(bottom);
        Controls.Add(bindings);
        Controls.Add(description);
        Controls.Add(title);
        RefreshValues();
    }

    private static Label RowLabel(string text) => new()
    {
        Text = text,
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleLeft,
        Font = new Font("Segoe UI", 10f, FontStyle.Bold)
    };

    private static Label ValueLabel() => new()
    {
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleLeft,
        ForeColor = Color.FromArgb(110, 200, 255),
        AutoEllipsis = true
    };

    private static Button ActionButton(string text, EventHandler click)
    {
        var button = new Button { Text = text, Dock = DockStyle.Fill, Margin = new Padding(4, 13, 4, 13) };
        button.Click += click;
        return button;
    }

    private void SetKeyboard()
    {
        if (!ChordCaptureDialog.TryCaptureKeyboard(this, out IReadOnlyList<Keys> chord))
            return;
        if (_settings.HasKeyboardDuplicate(MacroAction.Palette, chord))
        {
            MessageBox.Show(this, "That chord is already assigned to another action.", "Binding conflict", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        _settings.Bindings[MacroAction.Palette].Keyboard = chord.ToList();
        RefreshValues();
    }

    private void SetController()
    {
        if (!ChordCaptureDialog.TryCaptureController(this, out IReadOnlyList<ControllerControl> chord))
            return;
        if (_settings.HasControllerDuplicate(MacroAction.Palette, chord))
        {
            MessageBox.Show(this, "That chord is already assigned to another action.", "Binding conflict", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        _settings.Bindings[MacroAction.Palette].Controller = chord.ToList();
        RefreshValues();
    }

    private void ResetKeyboard()
    {
        _settings.Bindings[MacroAction.Palette].Keyboard = AppSettings.DefaultBinding(MacroAction.Palette).Keyboard;
        RefreshValues();
    }

    private void ClearController()
    {
        _settings.Bindings[MacroAction.Palette].Controller.Clear();
        RefreshValues();
    }

    private void RefreshValues()
    {
        _keyboardValue.Text = _settings.Bindings[MacroAction.Palette].KeyboardText;
        _controllerValue.Text = _settings.Bindings[MacroAction.Palette].ControllerText;
    }
}
