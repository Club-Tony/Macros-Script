using MacrosApp.Models;

namespace MacrosApp.Controls;

public class SlotListControl : UserControl
{
    private readonly ListBox _listBox;
    private readonly ContextMenuStrip _contextMenu;
    private List<MacroSlot> _slots = new();
    private ToolTip? _toolTip;
    private string _baseToolTipText = string.Empty;
    private string _activeToolTipText = string.Empty;
    private int _hoveredIndex = -1;

    public event EventHandler<MacroSlot>? SlotSelected;
    public event EventHandler<MacroSlot>? PlayRequested;
    public event EventHandler<MacroSlot>? DeleteRequested;
    public event EventHandler<MacroSlot>? RenameRequested;
    public event EventHandler<MacroSlot>? ExportRequested;

    public MacroSlot? SelectedSlot =>
        _listBox.SelectedIndex >= 0 && _listBox.SelectedIndex < _slots.Count
            ? _slots[_listBox.SelectedIndex]
            : null;

    public SlotListControl()
    {
        _listBox = new ListBox
        {
            Dock = DockStyle.Fill,
            BackColor = Color.FromArgb(35, 35, 35),
            ForeColor = Color.FromArgb(220, 220, 220),
            Font = new Font("Segoe UI", 9.5f),
            BorderStyle = BorderStyle.FixedSingle,
            IntegralHeight = false,
            DrawMode = DrawMode.OwnerDrawFixed,
            ItemHeight = 36
        };

        _listBox.DrawItem += ListBox_DrawItem;
        _listBox.SelectedIndexChanged += (_, _) =>
        {
            if (SelectedSlot != null)
                SlotSelected?.Invoke(this, SelectedSlot);
        };
        _listBox.MouseMove += ListBox_MouseMove;
        _listBox.MouseLeave += (_, _) => RestoreBaseToolTip();
        _listBox.DoubleClick += (_, _) =>
        {
            if (SelectedSlot != null)
                PlayRequested?.Invoke(this, SelectedSlot);
        };

        // Context menu
        _contextMenu = new ContextMenuStrip();
        _contextMenu.Renderer = new DarkMenuRenderer();

        var playItem = new ToolStripMenuItem("Play (F12)", null, (_, _) =>
        {
            if (SelectedSlot != null) PlayRequested?.Invoke(this, SelectedSlot);
        });
        var renameItem = new ToolStripMenuItem("Rename...", null, (_, _) =>
        {
            if (SelectedSlot != null) RenameRequested?.Invoke(this, SelectedSlot);
        });
        var exportItem = new ToolStripMenuItem("Export...", null, (_, _) =>
        {
            if (SelectedSlot != null) ExportRequested?.Invoke(this, SelectedSlot);
        });
        var deleteItem = new ToolStripMenuItem("Delete", null, (_, _) =>
        {
            if (SelectedSlot != null) DeleteRequested?.Invoke(this, SelectedSlot);
        });
        deleteItem.ForeColor = Color.FromArgb(255, 100, 100);

        _contextMenu.Items.AddRange(new ToolStripItem[] { playItem, new ToolStripSeparator(), renameItem, exportItem, new ToolStripSeparator(), deleteItem });
        _listBox.ContextMenuStrip = _contextMenu;

        Controls.Add(_listBox);
    }

    public void LoadSlots(List<MacroSlot> slots, string? selectedSlotName = null)
    {
        string? selectionToRestore = string.IsNullOrWhiteSpace(selectedSlotName)
            ? SelectedSlot?.Name
            : selectedSlotName;

        _slots = slots;
        _listBox.Items.Clear();
        foreach (var slot in slots)
        {
            _listBox.Items.Add(slot.ToString());
        }

        if (!SelectSlot(selectionToRestore))
            _listBox.ClearSelected();
    }

    public void RefreshDisplay()
    {
        int selected = _listBox.SelectedIndex;
        _listBox.Items.Clear();
        foreach (var slot in _slots)
        {
            _listBox.Items.Add(slot.ToString());
        }
        if (selected >= 0 && selected < _listBox.Items.Count)
            _listBox.SelectedIndex = selected;
    }

    public bool SelectSlot(string? slotName)
    {
        if (string.IsNullOrWhiteSpace(slotName))
            return false;

        int index = _slots.FindIndex(slot => slot.Name.Equals(slotName, StringComparison.OrdinalIgnoreCase));
        if (index < 0)
            return false;

        _listBox.SelectedIndex = index;
        return true;
    }

    public void ApplyToolTip(ToolTip toolTip, string text)
    {
        _toolTip = toolTip;
        _baseToolTipText = text;
        _activeToolTipText = text;
        toolTip.SetToolTip(this, text);
        toolTip.SetToolTip(_listBox, text);
    }

    private void ListBox_MouseMove(object? sender, MouseEventArgs e)
    {
        if (_toolTip == null)
            return;

        int index = _listBox.IndexFromPoint(e.Location);
        if (index < 0 || index >= _slots.Count)
        {
            RestoreBaseToolTip();
            return;
        }

        if (_hoveredIndex == index)
            return;

        _hoveredIndex = index;
        string text = BuildSlotToolTip(_slots[index]);
        if (text == _activeToolTipText)
            return;

        _activeToolTipText = text;
        _toolTip.SetToolTip(_listBox, text);
    }

    private void RestoreBaseToolTip()
    {
        if (_toolTip == null)
            return;

        _hoveredIndex = -1;
        if (_activeToolTipText == _baseToolTipText)
            return;

        _activeToolTipText = _baseToolTipText;
        _toolTip.SetToolTip(_listBox, _baseToolTipText);
    }

    private static string BuildSlotToolTip(MacroSlot slot)
    {
        string durationText = slot.Duration > TimeSpan.Zero
            ? $"{slot.Duration.TotalSeconds:F1}s"
            : "unknown duration";
        string recordedText = string.IsNullOrWhiteSpace(slot.Recorded)
            ? "Recorded date unknown."
            : $"Recorded: {slot.Recorded}.";

        return $"{slot.Name}\n{slot.EventCount} events, {durationText}.\n{recordedText}\nDouble-click to play. Right-click for rename, export, or delete.";
    }

    private void ListBox_DrawItem(object? sender, DrawItemEventArgs e)
    {
        if (e.Index < 0 || e.Index >= _slots.Count) return;

        e.DrawBackground();

        var slot = _slots[e.Index];
        var isSelected = (e.State & DrawItemState.Selected) == DrawItemState.Selected;
        var bg = isSelected ? Color.FromArgb(50, 80, 120) : Color.FromArgb(35, 35, 35);
        var fg = Color.FromArgb(220, 220, 220);
        var subFg = Color.FromArgb(140, 140, 140);

        using (var bgBrush = new SolidBrush(bg))
            e.Graphics.FillRectangle(bgBrush, e.Bounds);

        // Name line
        using var nameFont = new Font("Segoe UI", 9.5f, FontStyle.Bold);
        using var nameBrush = new SolidBrush(fg);
        e.Graphics.DrawString(slot.Name, nameFont, nameBrush, e.Bounds.X + 8, e.Bounds.Y + 2);

        // Details line
        string durationStr = slot.Duration.TotalSeconds > 0
            ? $"{slot.Duration.TotalSeconds:F1}s"
            : "---";
        string details = $"{slot.EventCount} events  |  {durationStr}";
        if (!string.IsNullOrEmpty(slot.Recorded))
            details += $"  |  {slot.Recorded}";

        using var detailFont = new Font("Segoe UI", 8f);
        using var detailBrush = new SolidBrush(subFg);
        e.Graphics.DrawString(details, detailFont, detailBrush, e.Bounds.X + 8, e.Bounds.Y + 18);

        // Bottom separator
        using var sepPen = new Pen(Color.FromArgb(55, 55, 55));
        e.Graphics.DrawLine(sepPen, e.Bounds.X, e.Bounds.Bottom - 1, e.Bounds.Right, e.Bounds.Bottom - 1);
    }

    /// <summary>
    /// Dark theme renderer for context menus.
    /// </summary>
    private class DarkMenuRenderer : ToolStripProfessionalRenderer
    {
        public DarkMenuRenderer() : base(new DarkMenuColorTable()) { }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            if (e.Item is ToolStripMenuItem item && item.ForeColor != Color.FromArgb(255, 100, 100))
                e.TextColor = Color.FromArgb(220, 220, 220);
            base.OnRenderItemText(e);
        }
    }

    private class DarkMenuColorTable : ProfessionalColorTable
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
