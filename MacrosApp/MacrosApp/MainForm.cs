using MacrosApp.Controls;
using MacrosApp.Models;
using System.Threading;

namespace MacrosApp;

public partial class MainForm : Form
{
    private static readonly Color ControllerWaitingColor = Color.FromArgb(150, 150, 150);
    private static readonly Color ControllerConnectedColor = Color.FromArgb(100, 200, 100);
    private static readonly Color ControllerUnavailableColor = Color.FromArgb(200, 130, 50);

    private static readonly HashSet<Keys> ReservedHoldKeys = new()
    {
        Keys.F1,
        Keys.F2,
        Keys.F3,
        Keys.F4,
        Keys.F5,
        Keys.F12,
        Keys.Escape
    };

    private HotkeyManager _hotkeyManager = null!;
    private SlotManager _slotManager = null!;
    private ProfileManager _profileManager = null!;
    private MacroSettings _settings = new();
    private System.Threading.Timer? _autoclickTimer;
    private bool _autoclickerRunning;
    private System.Windows.Forms.Timer? _playbackStateTimer;
    private bool _slotPlaybackActive;
    private RecordingInputHook? _recordingInputHook;
    private DateTime _recordingIgnoreUntilUtc = DateTime.MinValue;
    private bool _hotkeysSuspended;
    private KeyboardToggleBinding? _holdKeyBinding;
    private System.Threading.Timer? _turboRepeatTimer;
    private ToolTip _hoverHelp = null!;
    private Keys _configuredHoldKey = Keys.None;
    private string _configuredHoldKeyLabel = string.Empty;
    private bool _holdMacroEngaged;
    private int _turboRepeatMs = 40;

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
        InitializeToolTips();
        InitializeManagers();
        WireEvents();
        InitializePlaybackMonitor();
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
        controllerState.ConnectionChanged += ControllerState_ConnectionChanged;

        // Slot list events
        slotList.PlayRequested += (_, slot) => PlaySlot(slot);
        slotList.DeleteRequested += (_, slot) => DeleteSlot(slot);
        slotList.RenameRequested += (_, slot) => RenameSlot(slot);
        slotList.ExportRequested += (_, slot) => ExportSlot(slot);

        // Settings changes
        nudInterval.ValueChanged += (_, _) =>
        {
            _settings.AutoclickerInterval = (int)nudInterval.Value;
            RefreshAutoclickerInterval();
        };
        cmbSendMode.SelectedIndexChanged += (_, _) =>
        {
            if (Enum.TryParse<SendModeType>(cmbSendMode.SelectedItem?.ToString(), out var mode))
                _settings.SendMode = mode;
            ClearComboSelectionHighlight(cmbSendMode);
        };
        cmbControllerOutput.SelectedIndexChanged += (_, _) =>
        {
            if (Enum.TryParse<ControllerOutputType>(cmbControllerOutput.SelectedItem?.ToString(), out var output))
                _settings.ControllerOutput = output;
            ClearComboSelectionHighlight(cmbControllerOutput);
        };
        cmbSendMode.DropDownClosed += (_, _) => ClearComboSelectionHighlight(cmbSendMode);
        cmbControllerOutput.DropDownClosed += (_, _) => ClearComboSelectionHighlight(cmbControllerOutput);
        nudLoopCount.ValueChanged += (_, _) => _settings.LoopCount = (int)nudLoopCount.Value;
    }

    private void ClearComboSelectionHighlight(ComboBox combo)
    {
        if (!IsHandleCreated || combo.IsDisposed)
            return;

        BeginInvoke((MethodInvoker)(() =>
        {
            if (combo.IsDisposed)
                return;

            combo.SelectionStart = 0;
            combo.SelectionLength = 0;
        }));
    }

    private void InitializePlaybackMonitor()
    {
        _playbackStateTimer = new System.Windows.Forms.Timer(components)
        {
            Interval = 150
        };
        _playbackStateTimer.Tick += (_, _) => PollPlaybackState();
        _playbackStateTimer.Start();
    }

    private void InitializeToolTips()
    {
        _hoverHelp = new ToolTip(components)
        {
            AutomaticDelay = 2000,
            InitialDelay = 2000,
            ReshowDelay = 500,
            AutoPopDelay = 12000,
            ShowAlways = true
        };

        _hoverHelp.SetToolTip(statusLabel,
            "Shows the app's current state, such as idle, recording, playback, or hold-mode status.");

        _hoverHelp.SetToolTip(btnSlashMacro,
            "Stages Slash Macro. Press F12 while active to send a left mouse click.");
        _hoverHelp.SetToolTip(btnAutoclicker,
            "Stages the autoclicker. Press F12 while active to start or stop repeated left clicks.");
        _hoverHelp.SetToolTip(btnTurboHold,
            "Configures Turbo Hold. You choose a key and repeat speed, then that key toggles rapid repeated presses.");
        _hoverHelp.SetToolTip(btnPureHold,
            "Configures Pure Hold. You choose a key, then that key toggles a held-down state until pressed again.");
        _hoverHelp.SetToolTip(btnRecorder,
            "Starts keyboard and mouse recording. Press F5 again to stop, then save the recording into a slot.");

        _hoverHelp.SetToolTip(slotHeaderLabel,
            "Saved recordings loaded from macros.ini and macros_events. Select one to replay, rename, export, or delete it.");
        slotList.ApplyToolTip(
            _hoverHelp,
            "Saved recording slots. Double-click a slot to play it, or right-click for rename, export, and delete actions.");

        _hoverHelp.SetToolTip(settingsHeaderLabel,
            "Playback and macro settings for the current app session.");
        _hoverHelp.SetToolTip(lblInterval,
            "Autoclicker repeat interval in milliseconds.");
        _hoverHelp.SetToolTip(nudInterval,
            "Sets how quickly the autoclicker repeats left clicks while it is running.");
        _hoverHelp.SetToolTip(lblSendMode,
            "Selected send mode for direct macro output like slash, autoclick, and hold/turbo. Play falls back to Input on modern Windows, and recorded slot playback still uses the native engine.");
        _hoverHelp.SetToolTip(cmbSendMode,
            "Choose how direct key and mouse output is emitted. Profiles can also set this automatically; Input and Event are honored, while Play currently uses Input.");
        _hoverHelp.SetToolTip(lblControllerOutput,
            "Output backend for recorded controller events during slot playback.");
        _hoverHelp.SetToolTip(cmbControllerOutput,
            "Use vJoy for tools that read vJoy devices, or VirtualXbox for games that only listen to XInput controllers.");
        _hoverHelp.SetToolTip(lblLoopCount,
            "How many times a selected recording should replay. 0 means loop until you stop it.");
        _hoverHelp.SetToolTip(nudLoopCount,
            "Sets the playback loop count for selected recording slots. Use 0 for infinite playback.");

        _hoverHelp.SetToolTip(controllerHeaderLabel,
            "Live controller viewer fed by the native engine's XInput polling. If no controller is turned on, this panel waits quietly until one appears.");
        controllerState.ApplyToolTip(
            _hoverHelp,
            "Shows live controller connection state, sticks, triggers, and buttons. This is read-only right now.");

        statusStrip.ShowItemToolTips = true;
        engineStatusLabel.ToolTipText =
            "Reports whether the native MacrosEngine DLL loaded successfully for recording, playback, and controller polling.";
        profileStatusLabel.ToolTipText =
            "Shows the currently detected profile name based on the foreground app's process.";
    }

    private void LoadData()
    {
        RefreshSlotList();

        // Load profiles and detect active
        var profiles = _profileManager.LoadProfiles();
        var active = _profileManager.DetectActiveProfile();
        string profileName = active?.Name ?? profiles.FirstOrDefault()?.Name ?? "Default";
        profileStatusLabel.Text = $"Profile: {profileName}";

        var effectiveProfile = active ?? profiles.FirstOrDefault();
        if (effectiveProfile != null)
        {
            _settings.VJoyDeviceId = Math.Clamp(effectiveProfile.VJoyDeviceId, 1, 16);
            _settings.ControllerOutput = effectiveProfile.ControllerOutput;
            cmbControllerOutput.SelectedItem = effectiveProfile.ControllerOutput.ToString();
        }

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
            SetControllerViewerWaiting();
        }
        else
        {
            engineStatusLabel.Text = "Engine: not loaded";
            engineStatusLabel.ForeColor = Color.FromArgb(200, 130, 50);
            controllerState.SetUnavailable("The native engine DLL is not available, so controller preview cannot start.");
            SetControllerViewerUnavailable();
        }
    }

    // ================================================================
    // FORM EVENTS
    // ================================================================

    private void MainForm_Shown(object? sender, EventArgs e)
    {
        _hotkeyManager.RegisterAll();

        if (NativeEngine.IsAvailable && NativeEngine.TryInit())
        {
            NativeEngine.TrySetVJoyDeviceId((uint)_settings.VJoyDeviceId);

            if (NativeEngine.TryStartPolling(16))
            {
                controllerState.StartRefresh();
                SetControllerViewerWaiting();
            }
            else
            {
                engineStatusLabel.Text = "Engine: polling failed";
                engineStatusLabel.ForeColor = ControllerUnavailableColor;
                controllerState.SetUnavailable("The native engine initialized, but controller polling could not start.");
                SetControllerViewerUnavailable();
            }
        }
        else if (NativeEngine.IsAvailable)
        {
            engineStatusLabel.Text = "Engine: init failed";
            engineStatusLabel.ForeColor = ControllerUnavailableColor;
            controllerState.SetUnavailable("The native engine loaded, but initialization failed before controller preview could start.");
            SetControllerViewerUnavailable();
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
        DeactivateHoldMode(silent: true);
        DisposeRecordingHook();
        DisposeAutoclickerTimer();
        NativeEngine.TryStopPlayback();
        DisposePlaybackMonitor();
        _hotkeyManager.Dispose();
        controllerState.StopRefresh();
        NativeEngine.TryStopPolling();
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

        DeactivateHoldMode(silent: true);
        DisposeRecordingHook();
        DisposeAutoclickerTimer();
        NativeEngine.TryStopPlayback();
        DisposePlaybackMonitor();
        _hotkeyManager.Dispose();
        controllerState.StopRefresh();
        NativeEngine.TryStopPolling();
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

    private void ControllerState_ConnectionChanged(object? sender, ControllerConnectionChangedEventArgs e)
    {
        if (e.IsConnected)
            SetControllerViewerConnected();
        else
            SetControllerViewerWaiting();
    }

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
        if (_hotkeysSuspended)
            return;

        if (_activeMacroType == MacroType.Recorder)
        {
            if (hotkeyId == HotkeyManager.HOTKEY_RECORDER || hotkeyId == HotkeyManager.HOTKEY_CANCEL)
                DeactivateCurrentMacro();
            return;
        }

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
                HandlePlaybackHotkey();
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
        else if (NativeEngine.TryIsPlaying())
        {
            NativeEngine.TryStopPlayback();
            StopSlotPlaybackTracking();
        }

        // Activate new
        switch (type)
        {
            case MacroType.SlashMacro:
                _activeMacroType = type;
                SetState(MacroState.Idle, "Slash Macro ready: F12 => left click");
                HighlightButton(btnSlashMacro, true);
                break;
            case MacroType.Autoclicker:
                _activeMacroType = type;
                SetState(MacroState.Idle, GetAutoclickerReadyText());
                HighlightButton(btnAutoclicker, true);
                break;
            case MacroType.TurboHold:
                ActivateTurboHold();
                break;
            case MacroType.PureHold:
                ActivatePureHold();
                break;
            case MacroType.Recorder:
                _activeMacroType = type;
                if (StartRecordingSession())
                {
                    SetState(MacroState.Recording, "Recording...");
                    HighlightButton(btnRecorder, true);
                }
                else
                {
                    _activeMacroType = null;
                    SetState(MacroState.Idle, "Recorder unavailable");
                }
                break;
        }
    }

    private void DeactivateCurrentMacro()
    {
        if (_activeMacroType == MacroType.TurboHold || _activeMacroType == MacroType.PureHold)
        {
            DeactivateHoldMode();
            return;
        }

        if (_activeMacroType == MacroType.Recorder)
        {
            FinalizeRecording();
            return;
        }

        StopAutoclicker(keepReady: false);
        _activeMacroType = null;
        ResetAllButtons();
        SetState(MacroState.Idle, "Idle");
    }

    private void HandlePlaybackHotkey()
    {
        switch (_activeMacroType)
        {
            case MacroType.SlashMacro:
                if (WindowsInput.SendLeftClick(_settings.SendMode))
                    SetState(MacroState.Idle, "Slash Macro ready: F12 => left click");
                else
                    SetState(MacroState.Idle, "Slash Macro click failed");
                return;
            case MacroType.Autoclicker:
                ToggleAutoclicker();
                return;
            case MacroType.TurboHold:
            case MacroType.PureHold:
                return;
        }

        TogglePlayback();
    }

    private void TogglePlayback()
    {
        if (_currentState == MacroState.Playing && NativeEngine.TryIsPlaying())
        {
            NativeEngine.TryStopPlayback();
            StopSlotPlaybackTracking();
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
        if (_activeMacroType == MacroType.Recorder)
        {
            SetState(MacroState.Recording, "Finish recording before playback");
            return;
        }

        if (_activeMacroType != null)
        {
            StopAutoclicker(keepReady: false);
            _activeMacroType = null;
            ResetAllButtons();
        }

        if (!NativeEngine.TryInit())
        {
            SetState(MacroState.Idle, "Engine unavailable");
            return;
        }
        NativeEngine.TrySetVJoyDeviceId((uint)_settings.VJoyDeviceId);

        string eventPath = _slotManager.GetEventFilePath(slot.Name);
        if (!File.Exists(eventPath))
        {
            SetState(MacroState.Idle, $"Missing events: {slot.Name}");
            return;
        }

        if (!NativeEngine.TryLoadPlaybackBuffer(eventPath, out var buffer, out uint count))
        {
            SetState(MacroState.Idle, $"Unable to load: {slot.Name}");
            return;
        }

        bool hasControllerEvents = SlotHasControllerEvents(eventPath);
        string controllerOutputStatus = string.Empty;
        bool controllerOutputReady = true;

        try
        {
            if (NativeEngine.TryIsPlaying())
            {
                NativeEngine.TryStopPlayback();
                StopSlotPlaybackTracking();
            }

            if (!TryPrepareControllerOutputForPlayback(hasControllerEvents, out controllerOutputReady, out controllerOutputStatus))
            {
                SetState(MacroState.Idle, controllerOutputStatus);
                return;
            }

            if (!NativeEngine.TryStartPlayback(buffer, count, (uint)Math.Max(0, _settings.LoopCount)))
            {
                NativeEngine.TryResetControllerOutput();
                SetState(MacroState.Idle, $"Playback failed: {slot.Name}");
                return;
            }

            _slotPlaybackActive = true;
            string status = hasControllerEvents && !string.IsNullOrWhiteSpace(controllerOutputStatus)
                ? $"Playing: {slot.Name} ({controllerOutputStatus})"
                : $"Playing: {slot.Name}";
            if (hasControllerEvents && !controllerOutputReady)
                status = $"Playing: {slot.Name} ({controllerOutputStatus})";
            SetState(MacroState.Playing, status);
        }
        finally
        {
            NativeEngine.FreePlaybackBuffer(buffer);
        }
    }

    private static bool SlotHasControllerEvents(string eventPath)
    {
        try
        {
            foreach (var rawLine in File.ReadLines(eventPath))
            {
                var line = rawLine.TrimStart();
                if (line.StartsWith("C|", StringComparison.Ordinal))
                    return true;
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }

        return false;
    }

    private bool TryPrepareControllerOutputForPlayback(
        bool hasControllerEvents,
        out bool outputReady,
        out string status)
    {
        outputReady = true;
        status = string.Empty;

        if (!hasControllerEvents)
        {
            NativeEngine.TryUseVJoyControllerOutput();
            return true;
        }

        if (_settings.ControllerOutput == ControllerOutputType.VirtualXbox)
        {
            if (NativeEngine.TryUseVirtualXboxControllerOutput(out var error))
            {
                status = "VirtualXbox";
                return true;
            }

            outputReady = false;
            status = string.IsNullOrWhiteSpace(error)
                ? "VirtualXbox unavailable"
                : $"VirtualXbox unavailable: {error}";
            return false;
        }

        NativeEngine.TryUseVJoyControllerOutput();
        outputReady = NativeEngine.TryGetVJoyState(out var vJoyState) && vJoyState.Ready;
        status = outputReady ? "vJoy" : "vJoy unavailable";
        return true;
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
            StopSlotPlaybackTracking();
            SetState(MacroState.Idle, "Idle");
        }
    }

    private void ToggleAutoclicker()
    {
        if (_activeMacroType != MacroType.Autoclicker)
            return;

        if (_autoclickerRunning)
        {
            StopAutoclicker(keepReady: true);
            return;
        }

        EnsureAutoclickerTimer();
        _autoclickerRunning = true;
        _autoclickTimer!.Change(_settings.AutoclickerInterval, _settings.AutoclickerInterval);
        SetState(MacroState.Playing, $"Autoclicker running ({_settings.AutoclickerInterval} ms)");
    }

    private void RefreshAutoclickerInterval()
    {
        if (_autoclickerRunning)
        {
            _autoclickTimer?.Change(_settings.AutoclickerInterval, _settings.AutoclickerInterval);
            SetState(MacroState.Playing, $"Autoclicker running ({_settings.AutoclickerInterval} ms)");
            return;
        }

        if (_activeMacroType == MacroType.Autoclicker)
            SetState(MacroState.Idle, GetAutoclickerReadyText());
    }

    private void EnsureAutoclickerTimer()
    {
        _autoclickTimer ??= new System.Threading.Timer(
            _ => WindowsInput.SendLeftClick(_settings.SendMode),
            null,
            Timeout.Infinite,
            Timeout.Infinite);
    }

    private void StopAutoclicker(bool keepReady)
    {
        _autoclickerRunning = false;
        _autoclickTimer?.Change(Timeout.Infinite, Timeout.Infinite);

        if (keepReady && _activeMacroType == MacroType.Autoclicker)
            SetState(MacroState.Idle, GetAutoclickerReadyText());
    }

    private void DisposeAutoclickerTimer()
    {
        StopAutoclicker(keepReady: false);
        _autoclickTimer?.Dispose();
        _autoclickTimer = null;
    }

    private string GetAutoclickerReadyText()
    {
        return $"Autoclicker ready: F12 toggles ({_settings.AutoclickerInterval} ms)";
    }

    private void ActivateTurboHold()
    {
        if (!TryPromptTurboRepeatInterval(out int repeatMs))
        {
            _activeMacroType = null;
            ResetAllButtons();
            SetState(MacroState.Idle, "Turbo hold canceled");
            return;
        }

        if (!TryConfigureHoldKey(
                "Turbo Hold",
                "Input key to turbo.",
                out var key,
                out var label))
        {
            _activeMacroType = null;
            ResetAllButtons();
            SetState(MacroState.Idle, "Turbo hold canceled");
            return;
        }

        _turboRepeatMs = repeatMs;
        ActivateHoldMode(MacroType.TurboHold, key, label);
        ToggleConfiguredHoldMode();
    }

    private void ActivatePureHold()
    {
        if (!TryConfigureHoldKey(
                "Pure Hold",
                "Input key to hold down.",
                out var key,
                out var label))
        {
            _activeMacroType = null;
            ResetAllButtons();
            SetState(MacroState.Idle, "Pure hold canceled");
            return;
        }

        ActivateHoldMode(MacroType.PureHold, key, label);
        ToggleConfiguredHoldMode();
    }

    private void ActivateHoldMode(MacroType type, Keys key, string label)
    {
        DeactivateHoldMode(silent: true);

        _activeMacroType = type;
        _configuredHoldKey = key;
        _configuredHoldKeyLabel = label;
        _holdMacroEngaged = false;

        _holdKeyBinding = new KeyboardToggleBinding(
            key,
            () =>
            {
                if (!IsHandleCreated || IsDisposed)
                    return;

                BeginInvoke(new Action(ToggleConfiguredHoldMode));
            });

        if (!_holdKeyBinding.Start())
        {
            _holdKeyBinding.Dispose();
            _holdKeyBinding = null;
            _activeMacroType = null;
            _configuredHoldKey = Keys.None;
            _configuredHoldKeyLabel = string.Empty;
            SetState(MacroState.Idle, $"{GetModeDisplayName(type)} unavailable");
            return;
        }

        HighlightButton(type == MacroType.TurboHold ? btnTurboHold : btnPureHold, true);
        SetState(MacroState.Idle, $"{GetModeDisplayName(type)} ready: {label} (press again to toggle)");
    }

    private void ToggleConfiguredHoldMode()
    {
        if ((_activeMacroType != MacroType.TurboHold && _activeMacroType != MacroType.PureHold) ||
            _configuredHoldKey == Keys.None)
        {
            return;
        }

        if (_holdMacroEngaged)
        {
            StopConfiguredHoldOutput();
            SetState(
                MacroState.Idle,
                $"{GetModeDisplayName(_activeMacroType.Value)} OFF: {_configuredHoldKeyLabel}");
            return;
        }

        StartConfiguredHoldOutput();
        SetState(
            MacroState.Playing,
            $"{GetModeDisplayName(_activeMacroType.Value)} ON: {_configuredHoldKeyLabel}");
    }

    private void StartConfiguredHoldOutput()
    {
        if (_configuredHoldKey == Keys.None)
            return;

        _holdMacroEngaged = true;
        WindowsInput.SendKeyDown(_configuredHoldKey, _settings.SendMode);

        if (_activeMacroType == MacroType.TurboHold)
        {
            _turboRepeatTimer ??= new System.Threading.Timer(
                _ => WindowsInput.SendKeyPress(_configuredHoldKey, _settings.SendMode),
                null,
                Timeout.Infinite,
                Timeout.Infinite);

            _turboRepeatTimer.Change(_turboRepeatMs, _turboRepeatMs);
        }
    }

    private void StopConfiguredHoldOutput()
    {
        _turboRepeatTimer?.Change(Timeout.Infinite, Timeout.Infinite);

        if (_configuredHoldKey != Keys.None)
            WindowsInput.SendKeyUp(_configuredHoldKey, _settings.SendMode);

        _holdMacroEngaged = false;
    }

    private void DeactivateHoldMode(bool silent = false)
    {
        if (_activeMacroType != MacroType.TurboHold &&
            _activeMacroType != MacroType.PureHold &&
            _holdKeyBinding == null &&
            _configuredHoldKey == Keys.None)
        {
            return;
        }

        StopConfiguredHoldOutput();

        _holdKeyBinding?.Dispose();
        _holdKeyBinding = null;
        _turboRepeatTimer?.Dispose();
        _turboRepeatTimer = null;
        _configuredHoldKey = Keys.None;
        _configuredHoldKeyLabel = string.Empty;
        _activeMacroType = null;

        ResetAllButtons();

        if (!silent)
            SetState(MacroState.Idle, "Idle");
    }

    private bool TryPromptTurboRepeatInterval(out int repeatMs)
    {
        repeatMs = _turboRepeatMs;

        while (true)
        {
            _hotkeysSuspended = true;
            string? input;
            try
            {
                input = ShowInputDialog(
                    "Turbo Hold",
                    $"Enter repeat interval in ms (10-10000, default {_turboRepeatMs}):",
                    _turboRepeatMs.ToString());
            }
            finally
            {
                _hotkeysSuspended = false;
            }

            if (input == null)
                return false;

            if (string.IsNullOrWhiteSpace(input))
            {
                repeatMs = _turboRepeatMs;
                return true;
            }

            if (int.TryParse(input.Trim(), out int parsed))
            {
                repeatMs = Math.Clamp(parsed, 10, 10000);
                return true;
            }

            MessageBox.Show(
                this,
                "Enter a whole number between 10 and 10000.",
                "Turbo Hold",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
    }

    private bool TryConfigureHoldKey(string title, string prompt, out Keys key, out string label)
    {
        key = Keys.None;
        label = string.Empty;

        while (true)
        {
            _hotkeysSuspended = true;
            bool selected;
            try
            {
                selected = KeyCaptureDialog.TrySelectKey(this, title, prompt, out key);
            }
            finally
            {
                _hotkeysSuspended = false;
            }

            if (!selected)
                return false;

            key &= Keys.KeyCode;
            if (key == Keys.None)
                return false;

            if (ReservedHoldKeys.Contains(key))
            {
                MessageBox.Show(
                    this,
                    $"{KeyCaptureDialog.FormatKey(key)} is reserved by the app. Choose a different key.",
                    title,
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
                continue;
            }

            label = KeyCaptureDialog.FormatKey(key);
            return true;
        }
    }

    private static string GetModeDisplayName(MacroType type)
    {
        return type switch
        {
            MacroType.TurboHold => "Turbo Hold",
            MacroType.PureHold => "Pure Hold",
            _ => type.ToString()
        };
    }

    private bool StartRecordingSession()
    {
        if (!NativeEngine.TryInit() || !NativeEngine.TryStartRecording())
            return false;
        NativeEngine.TryStartControllerRecording();

        DisposeRecordingHook();

        var hook = new RecordingInputHook();
        hook.KeyCaptured += OnRecordedKeyCaptured;
        hook.MouseMoveCaptured += OnRecordedMouseMoveCaptured;
        hook.MouseButtonCaptured += OnRecordedMouseButtonCaptured;
        hook.MouseWheelCaptured += OnRecordedMouseWheelCaptured;

        if (!hook.Start())
        {
            hook.Dispose();
            NativeEngine.TryStopControllerRecording();
            NativeEngine.TryStopRecording();
            return false;
        }

        _recordingInputHook = hook;
        _recordingIgnoreUntilUtc = DateTime.UtcNow.AddMilliseconds(200);
        return true;
    }

    private void FinalizeRecording()
    {
        DisposeRecordingHook();
        NativeEngine.TryStopControllerRecording();
        NativeEngine.TryStopRecording();

        _activeMacroType = null;
        ResetAllButtons();

        uint recordedCount = NativeEngine.TryGetRecordedEventCount();
        if (recordedCount == 0)
        {
            SetState(MacroState.Idle, "Recording discarded");
            return;
        }

        string defaultName = slotList.SelectedSlot?.Name ?? $"recording-{DateTime.Now:yyyyMMdd-HHmmss}";
        _hotkeysSuspended = true;
        string? slotName;
        try
        {
            slotName = ShowInputDialog("Save Recording", "Name this recording:", defaultName);
        }
        finally
        {
            _hotkeysSuspended = false;
        }

        if (slotName == null)
        {
            SetState(MacroState.Idle, "Recording discarded");
            return;
        }

        slotName = string.IsNullOrWhiteSpace(slotName) ? defaultName : slotName.Trim();
        string normalizedSlotName = _slotManager.NormalizeSlotName(slotName);
        if (!PersistRecordedEvents(normalizedSlotName, out uint savedCount))
        {
            SetState(MacroState.Idle, $"Save failed: {normalizedSlotName}");
            return;
        }

        RefreshSlotList(normalizedSlotName);
        SetState(MacroState.Idle, $"Saved: {normalizedSlotName} ({savedCount} events)");
    }

    private bool PersistRecordedEvents(string slotName, out uint savedCount)
    {
        savedCount = 0;

        if (!NativeEngine.TryGetRecordedEventsBuffer(out var buffer, out uint count))
            return false;

        try
        {
            string eventPath = _slotManager.GetEventFilePath(slotName);
            if (!NativeEngine.TrySaveEventsToFile(eventPath, buffer, count))
                return false;

            _slotManager.SaveSlot(new MacroSlot
            {
                Name = slotName,
                EventCount = (int)count,
                CoordMode = "screen",
                Recorded = DateTime.Now.ToString("yyyy-MM-dd")
            });

            savedCount = count;
            return true;
        }
        finally
        {
            NativeEngine.FreeRecordedEventsBuffer(buffer);
        }
    }

    private void DisposeRecordingHook()
    {
        if (_recordingInputHook == null)
            return;

        _recordingInputHook.Dispose();
        _recordingInputHook = null;
    }

    private void OnRecordedKeyCaptured(ushort vkCode, ushort scanCode, bool down)
    {
        if (ShouldIgnoreRecordedInput() || IsRecorderControlKey(vkCode))
            return;

        NativeEngine.TryRecordKeyEvent(down, vkCode, scanCode);
    }

    private void OnRecordedMouseMoveCaptured(int x, int y)
    {
        if (ShouldIgnoreRecordedInput())
            return;

        NativeEngine.TryRecordMouseMove(x, y);
    }

    private void OnRecordedMouseButtonCaptured(ushort button, bool down)
    {
        if (ShouldIgnoreRecordedInput())
            return;

        NativeEngine.TryRecordMouseButton(down, button);
    }

    private void OnRecordedMouseWheelCaptured(int delta)
    {
        if (ShouldIgnoreRecordedInput())
            return;

        NativeEngine.TryRecordMouseWheel(delta);
    }

    private bool ShouldIgnoreRecordedInput()
    {
        return DateTime.UtcNow < _recordingIgnoreUntilUtc;
    }

    private static bool IsRecorderControlKey(ushort vkCode)
    {
        return vkCode == (ushort)Keys.F5 || vkCode == (ushort)Keys.Escape;
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
        string normalizedName = _slotManager.NormalizeSlotName(newName ?? string.Empty);
        if (!string.IsNullOrWhiteSpace(normalizedName) &&
            !normalizedName.Equals(slot.Name, StringComparison.OrdinalIgnoreCase))
        {
            _slotManager.RenameSlot(slot.Name, normalizedName);
            RefreshSlotList(normalizedName);
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

    private void RefreshSlotList(string? preferredSlotName = null)
    {
        var slots = _slotManager.LoadSlots();
        string? selectedSlotName = preferredSlotName ?? slotList.SelectedSlot?.Name;
        slotList.LoadSlots(slots, selectedSlotName);
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

    private void SetControllerViewerWaiting()
    {
        controllerHeaderLabel.Text = "Controller (waiting)";
        controllerHeaderLabel.ForeColor = ControllerWaitingColor;
    }

    private void SetControllerViewerConnected()
    {
        controllerHeaderLabel.Text = "Controller (connected)";
        controllerHeaderLabel.ForeColor = ControllerConnectedColor;
    }

    private void SetControllerViewerUnavailable()
    {
        controllerHeaderLabel.Text = "Controller (unavailable)";
        controllerHeaderLabel.ForeColor = ControllerUnavailableColor;
    }

    private void PollPlaybackState()
    {
        if (!_slotPlaybackActive)
            return;

        if (NativeEngine.TryIsPlaying())
            return;

        StopSlotPlaybackTracking();

        if (_activeMacroType == null && _currentState == MacroState.Playing)
            SetState(MacroState.Idle, "Idle");
    }

    private void StopSlotPlaybackTracking()
    {
        _slotPlaybackActive = false;
        NativeEngine.TryResetControllerOutput();
    }

    private void DisposePlaybackMonitor()
    {
        StopSlotPlaybackTracking();

        if (_playbackStateTimer == null)
            return;

        _playbackStateTimer.Stop();
        _playbackStateTimer.Dispose();
        _playbackStateTimer = null;
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
