using MacrosApp.Models;

namespace MacrosApp;

public partial class MainForm : Form
{
    private HotkeyManager _hotkeyManager = null!;
    private SlotManager _slotManager = null!;
    private ProfileManager _profileManager = null!;
    private MacroSettings _settings = new();

    // Current macro state
    private MacroState _currentState = MacroState.Idle;
    private MacroType? _activeMacroType;
    private bool _isExiting;

    // Tray icon (created and owned by Program.cs, passed in)
    private NotifyIcon? _trayIcon;

    public enum MacroState
    {
        Idle,
        Recording,
        Playing,
        Paused
    }

    public enum MacroType
    {
        SlashMacro,
        Autoclicker,
        TurboHold,
        PureHold,
        Recorder
    }

    public MainForm()
    {
        InitializeComponent();
        InitializeManagers();
        WireEvents();
        LoadData();
        UpdateEngineStatus();
    }

    public void SetTrayIcon(NotifyIcon icon)
    {
        _trayIcon = icon;
    }

    private void InitializeManagers()
    {
        // Base path is the Macros-Script repo root (parent of MacrosApp)
        string basePath = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", ".."));

        // Fallback: check if macros.ini exists relative to executable
        if (!File.Exists(Path.Combine(basePath, "macros.ini")))
        {
            // Try current directory
            basePath = Directory.GetCurrentDirectory();
            if (!File.Exists(Path.Combine(basePath, "macros.ini")))
            {
                // Use exe directory as last resort
                basePath = AppDomain.CurrentDomain.BaseDirectory;
            }
        }

        _slotManager = new SlotManager(basePath);
        _profileManager = new ProfileManager(basePath);
        _hotkeyManager = new HotkeyManager(this.Handle);
    }

    private void WireEvents()
    {
        // Form events
        this.Shown += MainForm_Shown;
        this.FormClosing += MainForm_FormClosing;
        this.Resize += MainForm_Resize;

        // Macro buttons
        btnSlashMacro.Click += (_, _) => ToggleMacro(MacroType.SlashMacro);
        btnAutoclicker.Click += (_, _) => ToggleMacro(MacroType.Autoclicker);
        btnTurboHold.Click += (_, _) => ToggleMacro(MacroType.TurboHold);
        btnPureHold.Click += (_, _) => ToggleMacro(MacroType.PureHold);
        btnRecorder.Click += (_, _) => ToggleMacro(MacroType.Recorder);

        // Hotkey manager
        _hotkeyManager.HotkeyPressed += OnHotkeyPressed;

        // Slot list events
        slotList.PlayRequested += (_, slot) => PlaySlot(slot);
        slotList.DeleteRequested += (_, slot) => DeleteSlot(slot);
        slotList.RenameRequested += (_, slot) => RenameSlot(slot);
        slotList.ExportRequested += (_, slot) => ExportSlot(slot);

        // Settings changes
        nudInterval.ValueChanged += (_, _) => _settings.AutoclickerInterval = (int)nudInterval.Value;
        cmbSendMode.SelectedIndexChanged += (_, _) =>
        {
            if (Enum.TryParse<SendModeType>(cmbSendMode.SelectedItem?.ToString(), out var mode))
                _settings.SendMode = mode;
        };
        nudLoopCount.ValueChanged += (_, _) => _settings.LoopCount = (int)nudLoopCount.Value;
    }

    private void LoadData()
    {
        // Load slots
        var slots = _slotManager.LoadSlots();
        slotList.LoadSlots(slots);

        // Load profiles and detect active
        var profiles = _profileManager.LoadProfiles();
        var active = _profileManager.DetectActiveProfile();
        string profileName = active?.Name ?? profiles.FirstOrDefault()?.Name ?? "Default";
        profileStatusLabel.Text = $"Profile: {profileName}";

        // Apply profile settings if detected
        if (active != null)
        {
            _settings.SendMode = active.SendMode;
            cmbSendMode.SelectedItem = active.SendMode.ToString();
        }
    }

    private void UpdateEngineStatus()
    {
        if (NativeEngine.IsAvailable)
        {
            engineStatusLabel.Text = "Engine: loaded";
            engineStatusLabel.ForeColor = Color.FromArgb(100, 200, 100);
            controllerState.StartRefresh();
        }
        else
        {
            engineStatusLabel.Text = "Engine: not loaded";
            engineStatusLabel.ForeColor = Color.FromArgb(200, 130, 50);
        }
    }

    // ================================================================
    // FORM EVENTS
    // ================================================================

    private void MainForm_Shown(object? sender, EventArgs e)
    {
        _hotkeyManager.RegisterAll();

        // Try to initialize the native engine
        if (NativeEngine.IsAvailable)
        {
            NativeEngine.TryInit();
        }
    }

    private void MainForm_FormClosing(object? sender, FormClosingEventArgs e)
    {
        // X button minimizes to tray instead of closing (unless we're actually exiting)
        if (e.CloseReason == CloseReason.UserClosing && !_isExiting)
        {
            e.Cancel = true;
            MinimizeToTray();
            return;
        }

        // Actual shutdown
        _hotkeyManager.Dispose();
        controllerState.StopRefresh();
        NativeEngine.TryShutdown();
    }

    private void MainForm_Resize(object? sender, EventArgs e)
    {
        if (WindowState == FormWindowState.Minimized)
        {
            MinimizeToTray();
        }
    }

    // ================================================================
    // TRAY BEHAVIOR
    // ================================================================

    private void MinimizeToTray()
    {
        this.Hide();
        this.WindowState = FormWindowState.Normal; // Reset so it restores properly
        if (_trayIcon != null)
            _trayIcon.Visible = true;
    }

    public void RestoreFromTray()
    {
        this.Show();
        this.WindowState = FormWindowState.Normal;
        this.BringToFront();
        this.Activate();
        if (_trayIcon != null)
            _trayIcon.Visible = true; // Keep tray icon visible
    }

    /// <summary>
    /// Actually exit the application (from tray menu).
    /// </summary>
    public void ExitApplication()
    {
        _isExiting = true;

        _hotkeyManager.Dispose();
        controllerState.StopRefresh();
        NativeEngine.TryShutdown();

        if (_trayIcon != null)
        {
            _trayIcon.Visible = false;
            _trayIcon.Dispose();
        }

        Application.Exit();
    }

    // ================================================================
    // HOTKEYS
    // ================================================================

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == HotkeyManager.WM_HOTKEY)
        {
            int id = m.WParam.ToInt32();
            _hotkeyManager.ProcessHotkeyMessage(id);
        }
        base.WndProc(ref m);
    }

    private void OnHotkeyPressed(int hotkeyId)
    {
        switch (hotkeyId)
        {
            case HotkeyManager.HOTKEY_SLASH_MACRO:
                ToggleMacro(MacroType.SlashMacro);
                break;
            case HotkeyManager.HOTKEY_AUTOCLICKER:
                ToggleMacro(MacroType.Autoclicker);
                break;
            case HotkeyManager.HOTKEY_TURBO_HOLD:
                ToggleMacro(MacroType.TurboHold);
                break;
            case HotkeyManager.HOTKEY_PURE_HOLD:
                ToggleMacro(MacroType.PureHold);
                break;
            case HotkeyManager.HOTKEY_RECORDER:
                ToggleMacro(MacroType.Recorder);
                break;
            case HotkeyManager.HOTKEY_PLAYBACK:
                TogglePlayback();
                break;
            case HotkeyManager.HOTKEY_SHOW_HIDE:
                if (this.Visible)
                    MinimizeToTray();
                else
                    RestoreFromTray();
                break;
            case HotkeyManager.HOTKEY_CANCEL:
                CancelCurrentOperation();
                break;
        }
    }

    // ================================================================
    // MACRO CONTROL
    // ================================================================

    private void ToggleMacro(MacroType type)
    {
        if (_activeMacroType == type)
        {
            // Deactivate current
            DeactivateCurrentMacro();
            return;
        }

        // Deactivate previous if different
        if (_activeMacroType != null)
            DeactivateCurrentMacro();

        // Activate new
        _activeMacroType = type;

        switch (type)
        {
            case MacroType.SlashMacro:
                SetState(MacroState.Playing, "Slash Macro active");
                HighlightButton(btnSlashMacro, true);
                break;
            case MacroType.Autoclicker:
                SetState(MacroState.Playing, "Autoclicker active");
                HighlightButton(btnAutoclicker, true);
                break;
            case MacroType.TurboHold:
                SetState(MacroState.Playing, "Turbo Hold active");
                HighlightButton(btnTurboHold, true);
                break;
            case MacroType.PureHold:
                SetState(MacroState.Playing, "Pure Hold active");
                HighlightButton(btnPureHold, true);
                break;
            case MacroType.Recorder:
                if (NativeEngine.TryStartRecording())
                {
                    SetState(MacroState.Recording, "Recording...");
                }
                else
                {
                    SetState(MacroState.Recording, "Recording (managed)...");
                }
                HighlightButton(btnRecorder, true);
                break;
        }
    }

    private void DeactivateCurrentMacro()
    {
        if (_activeMacroType == MacroType.Recorder)
        {
            NativeEngine.TryStopRecording();
        }

        _activeMacroType = null;
        ResetAllButtons();
        SetState(MacroState.Idle, "Idle");
    }

    private void TogglePlayback()
    {
        if (_currentState == MacroState.Playing && NativeEngine.TryIsPlaying())
        {
            NativeEngine.TryStopPlayback();
            SetState(MacroState.Idle, "Idle");
            return;
        }

        var slot = slotList.SelectedSlot;
        if (slot != null)
        {
            PlaySlot(slot);
        }
    }

    private void PlaySlot(MacroSlot slot)
    {
        SetState(MacroState.Playing, $"Playing: {slot.Name}");
        // Actual playback would go through NativeEngine here
    }

    private void CancelCurrentOperation()
    {
        if (_activeMacroType != null)
        {
            DeactivateCurrentMacro();
        }
        else if (_currentState == MacroState.Playing)
        {
            NativeEngine.TryStopPlayback();
            SetState(MacroState.Idle, "Idle");
        }
    }

    // ================================================================
    // SLOT OPERATIONS
    // ================================================================

    private void DeleteSlot(MacroSlot slot)
    {
        var result = MessageBox.Show(
            $"Delete slot \"{slot.Name}\" and its recorded events?",
            "Delete Slot",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning);

        if (result == DialogResult.Yes)
        {
            _slotManager.DeleteSlot(slot.Name);
            RefreshSlotList();
        }
    }

    private void RenameSlot(MacroSlot slot)
    {
        string? newName = ShowInputDialog("Rename Slot", "New name:", slot.Name);
        if (!string.IsNullOrWhiteSpace(newName) && newName != slot.Name)
        {
            _slotManager.RenameSlot(slot.Name, newName);
            RefreshSlotList();
        }
    }

    private void ExportSlot(MacroSlot slot)
    {
        using var sfd = new SaveFileDialog
        {
            FileName = $"{slot.Name}.txt",
            Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*",
            Title = "Export Slot Events"
        };

        if (sfd.ShowDialog() == DialogResult.OK)
        {
            if (_slotManager.ExportSlot(slot.Name, sfd.FileName))
                SetState(_currentState, $"Exported: {slot.Name}");
        }
    }

    private void RefreshSlotList()
    {
        var slots = _slotManager.LoadSlots();
        slotList.LoadSlots(slots);
    }

    // ================================================================
    // UI HELPERS
    // ================================================================

    private void SetState(MacroState state, string displayText)
    {
        _currentState = state;
        statusLabel.Text = displayText;
        statusLabel.ForeColor = state switch
        {
            MacroState.Idle => Color.FromArgb(100, 200, 100),
            MacroState.Recording => Color.FromArgb(255, 80, 80),
            MacroState.Playing => Color.FromArgb(80, 160, 255),
            MacroState.Paused => Color.FromArgb(255, 200, 50),
            _ => Color.FromArgb(200, 200, 200)
        };
    }

    private void HighlightButton(Button btn, bool active)
    {
        ResetAllButtons();
        if (active)
        {
            btn.BackColor = Color.FromArgb(30, 80, 140);
            btn.FlatAppearance.BorderColor = Color.FromArgb(0, 120, 215);
            btn.FlatAppearance.BorderSize = 2;
        }
    }

    private void ResetAllButtons()
    {
        var defaultBg = Color.FromArgb(50, 50, 50);
        var defaultBorder = Color.FromArgb(70, 70, 70);
        foreach (var btn in new[] { btnSlashMacro, btnAutoclicker, btnTurboHold, btnPureHold, btnRecorder })
        {
            btn.BackColor = defaultBg;
            btn.FlatAppearance.BorderColor = defaultBorder;
            btn.FlatAppearance.BorderSize = 1;
        }
    }

    private static string? ShowInputDialog(string title, string prompt, string defaultValue = "")
    {
        using var form = new Form
        {
            Text = title,
            Width = 350,
            Height = 150,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            StartPosition = FormStartPosition.CenterParent,
            MaximizeBox = false,
            MinimizeBox = false,
            BackColor = Color.FromArgb(32, 32, 32),
            ForeColor = Color.FromArgb(220, 220, 220)
        };

        var label = new Label
        {
            Text = prompt,
            Left = 12,
            Top = 12,
            Width = 310,
            ForeColor = Color.FromArgb(220, 220, 220)
        };

        var textBox = new TextBox
        {
            Text = defaultValue,
            Left = 12,
            Top = 36,
            Width = 310,
            BackColor = Color.FromArgb(50, 50, 50),
            ForeColor = Color.FromArgb(220, 220, 220)
        };

        var okButton = new Button
        {
            Text = "OK",
            DialogResult = DialogResult.OK,
            Left = 170,
            Top = 70,
            Width = 75,
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(0, 100, 180),
            ForeColor = Color.White
        };

        var cancelButton = new Button
        {
            Text = "Cancel",
            DialogResult = DialogResult.Cancel,
            Left = 250,
            Top = 70,
            Width = 75,
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(60, 60, 60),
            ForeColor = Color.FromArgb(200, 200, 200)
        };

        form.Controls.AddRange(new Control[] { label, textBox, okButton, cancelButton });
        form.AcceptButton = okButton;
        form.CancelButton = cancelButton;

        return form.ShowDialog() == DialogResult.OK ? textBox.Text : null;
    }
}
