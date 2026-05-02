using System.Diagnostics;
using System.Reflection;
using System.Windows.Forms;
using MacrosApp;
using MacrosApp.Models;

SmokeResult? result = null;
Exception? failure = null;
string workspaceRoot = Path.Combine(
    Path.GetTempPath(),
    "MacrosAppSmoke-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N")[..8]);

Directory.CreateDirectory(workspaceRoot);
Directory.CreateDirectory(Path.Combine(workspaceRoot, "macros_events"));
File.WriteAllText(Path.Combine(workspaceRoot, "macros.ini"), string.Empty);

var uiThread = new Thread(() =>
{
    try
    {
        Directory.SetCurrentDirectory(workspaceRoot);
        ApplicationConfiguration.Initialize();

        using var form = new MainForm();
        form.Shown += (_, _) =>
        {
            try
            {
                result = RunSmoke(form, workspaceRoot);
            }
            catch (Exception ex)
            {
                failure = ex;
            }
            finally
            {
                typeof(MainForm).GetField(
                    "_isExiting",
                    BindingFlags.Instance | BindingFlags.NonPublic)?.SetValue(form, true);
                form.Close();
            }
        };

        Application.Run(form);
    }
    catch (Exception ex)
    {
        failure = ex;
    }
});

uiThread.SetApartmentState(ApartmentState.STA);
uiThread.Start();
uiThread.Join();

if (failure != null)
{
    Console.Error.WriteLine("Smoke test failed with an exception.");
    Console.Error.WriteLine(failure);
    Console.Error.WriteLine("Workspace preserved at: " + workspaceRoot);
    Environment.Exit(1);
}

if (result == null)
{
    Console.Error.WriteLine("Smoke test did not produce a result.");
    Console.Error.WriteLine("Workspace preserved at: " + workspaceRoot);
    Environment.Exit(1);
}

Console.WriteLine("workspace=" + workspaceRoot);
Console.WriteLine("saved_count=" + result.SavedCount);
Console.WriteLine("saved_slot=" + result.SlotName);
Console.WriteLine("start_status=" + result.StartStatus);
Console.WriteLine("final_status=" + result.FinalStatus);
Console.WriteLine("final_state=" + result.FinalState);
Console.WriteLine("slot_playback_active=" + result.SlotPlaybackActive);
Console.WriteLine("engine_playing=" + result.EnginePlaying);
Console.WriteLine("ini_present=" + result.IniContainsSlot);
Console.WriteLine("events_present=" + result.EventFileExists);

if (!result.Success)
{
    Console.Error.WriteLine("Smoke test failed.");
    Console.Error.WriteLine(result.FailureReason);
    Console.Error.WriteLine("Workspace preserved at: " + workspaceRoot);
    Environment.Exit(1);
}

Directory.SetCurrentDirectory(AppContext.BaseDirectory);
try
{
    Directory.Delete(workspaceRoot, recursive: true);
}
catch (IOException)
{
    Console.WriteLine("cleanup_warning=Workspace could not be deleted immediately.");
    Console.WriteLine("workspace_preserved=" + workspaceRoot);
}
catch (UnauthorizedAccessException)
{
    Console.WriteLine("cleanup_warning=Workspace could not be deleted immediately.");
    Console.WriteLine("workspace_preserved=" + workspaceRoot);
}
Console.WriteLine("Smoke test passed.");

static SmokeResult RunSmoke(MainForm form, string workspaceRoot)
{
    const string slotName = "smoke-slot";

    if (!NativeEngine.IsAvailable || !NativeEngine.TryInit())
    {
        return SmokeResult.Fail(slotName, "Native engine was not available.", workspaceRoot);
    }

    // B. vJoy state surface check: confirms the SetVJoyDeviceId / GetVJoyState
    // P/Invoke wrappers round-trip without throwing. Catches marshalling
    // regressions before the manual gate. We do not assert state.Available
    // because that depends on whether vJoy is installed on the host.
    if (!NativeEngine.TrySetVJoyDeviceId(1))
    {
        return SmokeResult.Fail(slotName, "TrySetVJoyDeviceId(1) returned false.", workspaceRoot);
    }
    if (!NativeEngine.TryGetVJoyState(out VJoyState vjoyState))
    {
        return SmokeResult.Fail(slotName, "TryGetVJoyState returned false.", workspaceRoot);
    }
    if (vjoyState.DeviceId != 1)
    {
        return SmokeResult.Fail(slotName, $"VJoyState.DeviceId expected 1, got {vjoyState.DeviceId}.", workspaceRoot);
    }
    Console.WriteLine($"vjoy_available={vjoyState.Available} vjoy_ready={vjoyState.Ready} vjoy_status={vjoyState.Status}");

    if (!NativeEngine.TryStartRecording())
    {
        return SmokeResult.Fail(slotName, "Native engine recording could not start.", workspaceRoot);
    }

    try
    {
        NativeEngine.TryRecordKeyEvent(down: true, (ushort)Keys.A, 0);
        Thread.Sleep(25);
        NativeEngine.TryRecordKeyEvent(down: false, (ushort)Keys.A, 0);
        Thread.Sleep(25);
        NativeEngine.TryRecordMouseMove(320, 240);
        Thread.Sleep(25);
        NativeEngine.TryRecordMouseButton(down: true, button: 1);
        Thread.Sleep(25);
        NativeEngine.TryRecordMouseButton(down: false, button: 1);
        Thread.Sleep(25);
        NativeEngine.TryRecordControllerEvent(new ControllerState
        {
            Connected = true,
            Buttons = 0x1000,
            LeftTrigger = 16,
            RightTrigger = 20,
            LeftThumbX = 512,
            LeftThumbY = -512
        });
    }
    finally
    {
        NativeEngine.TryStopRecording();
    }

    uint recordedCount = NativeEngine.TryGetRecordedEventCount();
    if (recordedCount == 0)
    {
        return SmokeResult.Fail(slotName, "No events were recorded.", workspaceRoot);
    }

    var persistMethod = typeof(MainForm).GetMethod(
        "PersistRecordedEvents",
        BindingFlags.Instance | BindingFlags.NonPublic);
    if (persistMethod == null)
    {
        return SmokeResult.Fail(slotName, "PersistRecordedEvents was not found.", workspaceRoot);
    }

    object?[] persistArgs = { slotName, 0u };
    bool persisted = (bool)(persistMethod.Invoke(form, persistArgs) ?? false);
    uint savedCount = (uint)(persistArgs[1] ?? 0u);
    if (!persisted || savedCount == 0)
    {
        return SmokeResult.Fail(slotName, "Recorded events could not be persisted.", workspaceRoot);
    }

    string iniPath = Path.Combine(workspaceRoot, "macros.ini");
    string eventPath = Path.Combine(workspaceRoot, "macros_events", slotName + ".txt");
    bool iniContainsSlot = File.Exists(iniPath) &&
                           File.ReadAllText(iniPath).Contains("[smoke-slot]", StringComparison.OrdinalIgnoreCase);
    bool eventFileExists = File.Exists(eventPath);
    if (!iniContainsSlot || !eventFileExists)
    {
        return SmokeResult.Fail(slotName, "Saved slot data was not written to disk.", workspaceRoot);
    }

    // A. Assert the persisted file actually contains the controller event we
    // recorded. event_format.c writes them as: C|buttons|lt|rt|lx|ly|rx|ry|delay
    // (9 pipe-separated tokens). A regression that silently dropped controller
    // writes wouldn't fail any other assertion in this harness.
    string[] eventLines = File.ReadAllLines(eventPath);
    string? controllerLine = eventLines.FirstOrDefault(
        l => l.StartsWith("C|", StringComparison.Ordinal));
    if (controllerLine == null)
    {
        return SmokeResult.Fail(slotName,
            "Persisted event file has no C| controller row. Lines: " +
            string.Join(" / ", eventLines),
            workspaceRoot);
    }
    string[] controllerTokens = controllerLine.Split('|');
    if (controllerTokens.Length != 9)
    {
        return SmokeResult.Fail(slotName,
            $"Controller row had {controllerTokens.Length} tokens, expected 9: {controllerLine}",
            workspaceRoot);
    }
    if (controllerTokens[1] != "4096" /* 0x1000 = A button */)
    {
        return SmokeResult.Fail(slotName,
            $"Controller row buttons expected 4096, got {controllerTokens[1]}: {controllerLine}",
            workspaceRoot);
    }
    Console.WriteLine("controller_row=" + controllerLine);

    var settingsField = typeof(MainForm).GetField(
        "_settings",
        BindingFlags.Instance | BindingFlags.NonPublic);
    if (settingsField?.GetValue(form) is not MacroSettings settings)
    {
        return SmokeResult.Fail(slotName, "_settings was not found.", workspaceRoot);
    }

    settings.LoopCount = 1;

    var playSlotMethod = typeof(MainForm).GetMethod(
        "PlaySlot",
        BindingFlags.Instance | BindingFlags.NonPublic);
    if (playSlotMethod == null)
    {
        return SmokeResult.Fail(slotName, "PlaySlot was not found.", workspaceRoot);
    }

    var statusLabelField = typeof(MainForm).GetField(
        "statusLabel",
        BindingFlags.Instance | BindingFlags.NonPublic);
    if (statusLabelField?.GetValue(form) is not Label statusLabel)
    {
        return SmokeResult.Fail(slotName, "statusLabel was not found.", workspaceRoot);
    }

    playSlotMethod.Invoke(form, new object[] { new MacroSlot { Name = slotName } });

    string startStatus = statusLabel.Text;
    if (!startStatus.StartsWith("Playing:", StringComparison.Ordinal))
    {
        return SmokeResult.Fail(slotName, "Playback did not enter the expected playing state.", workspaceRoot) with
        {
            SavedCount = savedCount,
            StartStatus = startStatus,
            IniContainsSlot = iniContainsSlot,
            EventFileExists = eventFileExists
        };
    }

    var stopwatch = Stopwatch.StartNew();
    while (stopwatch.Elapsed < TimeSpan.FromSeconds(6))
    {
        Application.DoEvents();
        Thread.Sleep(50);
    }

    string finalStatus = statusLabel.Text;
    string finalState = typeof(MainForm).GetField(
        "_currentState",
        BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(form)?.ToString() ?? "<missing>";
    bool slotPlaybackActive = (bool?)typeof(MainForm).GetField(
        "_slotPlaybackActive",
        BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(form) ?? true;
    bool enginePlaying = NativeEngine.TryIsPlaying();

    bool success =
        finalStatus == "Idle" &&
        finalState == "Idle" &&
        slotPlaybackActive == false &&
        enginePlaying == false;

    string failureReason = success
        ? string.Empty
        : "Playback did not settle back to Idle.";

    return new SmokeResult(
        SlotName: slotName,
        SavedCount: savedCount,
        StartStatus: startStatus,
        FinalStatus: finalStatus,
        FinalState: finalState,
        SlotPlaybackActive: slotPlaybackActive,
        EnginePlaying: enginePlaying,
        IniContainsSlot: iniContainsSlot,
        EventFileExists: eventFileExists,
        FailureReason: failureReason,
        Success: success);
}

internal sealed record SmokeResult(
    string SlotName,
    uint SavedCount,
    string StartStatus,
    string FinalStatus,
    string FinalState,
    bool SlotPlaybackActive,
    bool EnginePlaying,
    bool IniContainsSlot,
    bool EventFileExists,
    string FailureReason,
    bool Success)
{
    public static SmokeResult Fail(string slotName, string reason, string workspaceRoot)
    {
        return new SmokeResult(
            SlotName: slotName,
            SavedCount: 0,
            StartStatus: string.Empty,
            FinalStatus: string.Empty,
            FinalState: string.Empty,
            SlotPlaybackActive: false,
            EnginePlaying: false,
            IniContainsSlot: File.Exists(Path.Combine(workspaceRoot, "macros.ini")),
            EventFileExists: File.Exists(Path.Combine(workspaceRoot, "macros_events", slotName + ".txt")),
            FailureReason: reason,
            Success: false);
    }
}
