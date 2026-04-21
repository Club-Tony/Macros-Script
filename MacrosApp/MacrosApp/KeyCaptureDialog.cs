namespace MacrosApp;

public sealed class KeyCaptureDialog : Form
{
    private readonly Label _promptLabel;
    private readonly Label _hintLabel;

    public Keys SelectedKey { get; private set; } = Keys.None;

    public KeyCaptureDialog(string title, string prompt)
    {
        Text = title;
        Width = 360;
        Height = 150;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterParent;
        MaximizeBox = false;
        MinimizeBox = false;
        KeyPreview = true;
        BackColor = Color.FromArgb(32, 32, 32);
        ForeColor = Color.FromArgb(220, 220, 220);

        _promptLabel = new Label
        {
            Text = prompt,
            Left = 12,
            Top = 16,
            Width = 320,
            Height = 24,
            ForeColor = Color.FromArgb(220, 220, 220)
        };

        _hintLabel = new Label
        {
            Text = "Press a keyboard key now. Esc cancels.",
            Left = 12,
            Top = 52,
            Width = 320,
            Height = 24,
            ForeColor = Color.FromArgb(160, 160, 160)
        };

        Controls.Add(_promptLabel);
        Controls.Add(_hintLabel);
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        Keys key = NormalizeKey(keyData);
        if (key == Keys.Escape)
        {
            DialogResult = DialogResult.Cancel;
            Close();
            return true;
        }

        if (key == Keys.None)
            return base.ProcessCmdKey(ref msg, keyData);

        SelectedKey = key;
        DialogResult = DialogResult.OK;
        Close();
        return true;
    }

    public static bool TrySelectKey(IWin32Window owner, string title, string prompt, out Keys selectedKey)
    {
        using var dialog = new KeyCaptureDialog(title, prompt);
        if (dialog.ShowDialog(owner) == DialogResult.OK && dialog.SelectedKey != Keys.None)
        {
            selectedKey = dialog.SelectedKey;
            return true;
        }

        selectedKey = Keys.None;
        return false;
    }

    public static string FormatKey(Keys key)
    {
        key &= Keys.KeyCode;

        return key switch
        {
            Keys.ControlKey => "Ctrl",
            Keys.ShiftKey => "Shift",
            Keys.Menu => "Alt",
            Keys.Prior => "Page Up",
            Keys.Next => "Page Down",
            Keys.Capital => "Caps Lock",
            Keys.Back => "Backspace",
            Keys.Return => "Enter",
            _ => new KeysConverter().ConvertToString(key) ?? key.ToString()
        };
    }

    private static Keys NormalizeKey(Keys keyData)
    {
        return keyData & Keys.KeyCode;
    }
}
