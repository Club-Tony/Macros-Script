using MacrosApp.Models;

namespace MacrosApp;

public sealed class BindingSettingsForm : Form
{
    private readonly AppSettings _settings;
    private readonly AppSettingsStore _store;
    private readonly TableLayoutPanel _rows;
    private readonly Dictionary<MacroAction, (Label Keyboard, Label Controller)> _labels = new();

    public event EventHandler? BindingsChanged;

    public BindingSettingsForm(AppSettings settings, AppSettingsStore store)
    {
        _settings = settings;
        _store = store;
        Text = "Macros bindings";
        StartPosition = FormStartPosition.CenterParent;
        MinimumSize = new Size(900, 620);
        ClientSize = new Size(980, 690);
        BackColor = Color.FromArgb(24, 24, 28);
        ForeColor = Color.White;

        var title = new Label
        {
            Text = "Keyboard and controller bindings",
            Dock = DockStyle.Top,
            Height = 48,
            Font = new Font("Segoe UI", 15f, FontStyle.Bold),
            Padding = new Padding(16, 12, 0, 0)
        };
        var note = new Label
        {
            Text = "Bindings pass through to the game. Multi-input chords are recommended to avoid accidental activation.",
            Dock = DockStyle.Top,
            Height = 36,
            Padding = new Padding(17, 4, 0, 0),
            ForeColor = Color.FromArgb(190, 190, 195)
        };

        _rows = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoScroll = true,
            Padding = new Padding(12),
            ColumnCount = 8,
            RowCount = Enum.GetValues<MacroAction>().Length + 1,
            BackColor = Color.FromArgb(24, 24, 28)
        };
        _rows.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 125));
        _rows.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        _rows.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 82));
        _rows.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        _rows.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 82));
        _rows.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 62));
        _rows.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 62));
        _rows.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 8));
        AddHeader();
        int row = 1;
        foreach (MacroAction action in Enum.GetValues<MacroAction>())
            AddBindingRow(action, row++);

        var bottom = new FlowLayoutPanel
        {
            Dock = DockStyle.Bottom,
            Height = 52,
            FlowDirection = FlowDirection.RightToLeft,
            Padding = new Padding(8),
            BackColor = Color.FromArgb(30, 30, 34)
        };
        var close = new Button { Text = "Close", Width = 90, Height = 32 };
        close.Click += (_, _) => Close();
        var resetAll = new Button { Text = "Reset All", Width = 100, Height = 32 };
        resetAll.Click += (_, _) => ResetAll();
        bottom.Controls.Add(close);
        bottom.Controls.Add(resetAll);

        Controls.Add(_rows);
        Controls.Add(bottom);
        Controls.Add(note);
        Controls.Add(title);
        RefreshLabels();
    }

    private void AddHeader()
    {
        string[] headers = { "Action", "Keyboard", "Set", "Controller", "Set", "Clear", "Reset" };
        for (int column = 0; column < headers.Length; column++)
        {
            _rows.Controls.Add(new Label
            {
                Text = headers[column],
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.MiddleLeft,
                Font = new Font("Segoe UI", 9f, FontStyle.Bold),
                ForeColor = Color.FromArgb(150, 190, 230)
            }, column, 0);
        }
    }

    private void AddBindingRow(MacroAction action, int row)
    {
        var actionLabel = CellLabel(BindingText.ActionName(action));
        var keyboard = CellLabel(string.Empty);
        var controller = CellLabel(string.Empty);
        _labels[action] = (keyboard, controller);

        var setKeyboard = CellButton("Set");
        setKeyboard.Click += (_, _) => SetKeyboard(action);
        var setController = CellButton("Set");
        setController.Click += (_, _) => SetController(action);
        var clear = CellButton("Clear");
        clear.Click += (_, _) =>
        {
            _settings.Bindings[action] = new ActionBinding();
            SaveAndRefresh();
        };
        var reset = CellButton("Reset");
        reset.Click += (_, _) =>
        {
            _settings.Reset(action);
            SaveAndRefresh();
        };

        _rows.Controls.Add(actionLabel, 0, row);
        _rows.Controls.Add(keyboard, 1, row);
        _rows.Controls.Add(setKeyboard, 2, row);
        _rows.Controls.Add(controller, 3, row);
        _rows.Controls.Add(setController, 4, row);
        _rows.Controls.Add(clear, 5, row);
        _rows.Controls.Add(reset, 6, row);
        _rows.RowStyles.Add(new RowStyle(SizeType.Absolute, 50));
    }

    private static Label CellLabel(string text) => new()
    {
        Text = text,
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleLeft,
        ForeColor = Color.White,
        AutoEllipsis = true,
        Padding = new Padding(3)
    };

    private static Button CellButton(string text) => new()
    {
        Text = text,
        Dock = DockStyle.Fill,
        Margin = new Padding(3, 8, 3, 8)
    };

    private void SetKeyboard(MacroAction action)
    {
        if (!ChordCaptureDialog.TryCaptureKeyboard(this, out IReadOnlyList<Keys> chord))
            return;
        if (_settings.HasKeyboardDuplicate(action, chord))
        {
            MessageBox.Show(this, "That keyboard chord is already assigned to another action.", "Binding conflict", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        _settings.Bindings[action].Keyboard = chord.ToList();
        SaveAndRefresh();
    }

    private void SetController(MacroAction action)
    {
        if (!ChordCaptureDialog.TryCaptureController(this, out IReadOnlyList<ControllerControl> chord))
            return;
        if (_settings.HasControllerDuplicate(action, chord))
        {
            MessageBox.Show(this, "That controller chord is already assigned to another action.", "Binding conflict", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        _settings.Bindings[action].Controller = chord.ToList();
        SaveAndRefresh();
    }

    private void ResetAll()
    {
        if (MessageBox.Show(this, "Reset every keyboard and controller binding to its safe default?", "Reset all bindings", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes)
            return;
        _settings.ResetAll();
        SaveAndRefresh();
    }

    private void SaveAndRefresh()
    {
        _store.Save(_settings);
        RefreshLabels();
        BindingsChanged?.Invoke(this, EventArgs.Empty);
    }

    private void RefreshLabels()
    {
        foreach (var (action, labels) in _labels)
        {
            labels.Keyboard.Text = _settings.Bindings[action].KeyboardText;
            labels.Controller.Text = _settings.Bindings[action].ControllerText;
        }
    }
}
