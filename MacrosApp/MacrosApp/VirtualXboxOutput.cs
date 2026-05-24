using Nefarius.ViGEm.Client;
using Nefarius.ViGEm.Client.Targets;
using Nefarius.ViGEm.Client.Targets.Xbox360;

namespace MacrosApp;

internal static class VirtualXboxOutput
{
    private static readonly object Sync = new();

    private static ViGEmClient? _client;
    private static IXbox360Controller? _controller;
    private static bool _connected;

    public static bool IsConnected
    {
        get
        {
            lock (Sync)
            {
                return _connected && _controller != null;
            }
        }
    }

    public static bool TryEnsureConnected(out string error)
    {
        lock (Sync)
        {
            return TryEnsureConnectedLocked(out error);
        }
    }

    public static bool TryResetReport(out string error)
    {
        lock (Sync)
        {
            if (!TryEnsureConnectedLocked(out error))
                return false;

            try
            {
                ResetReportLocked();
                error = string.Empty;
                return true;
            }
            catch (Exception ex)
            {
                error = ex.Message;
                DisconnectLocked();
                return false;
            }
        }
    }

    public static bool TryDispatch(ControllerState state, out string error)
    {
        lock (Sync)
        {
            if (!TryEnsureConnectedLocked(out error))
                return false;

            try
            {
                if (!state.Connected)
                {
                    ResetReportLocked();
                    return true;
                }

                _controller!.SetButtonsFull(state.Buttons);
                _controller.SetAxisValue(Xbox360Axis.LeftThumbX, state.LeftThumbX);
                _controller.SetAxisValue(Xbox360Axis.LeftThumbY, state.LeftThumbY);
                _controller.SetAxisValue(Xbox360Axis.RightThumbX, state.RightThumbX);
                _controller.SetAxisValue(Xbox360Axis.RightThumbY, state.RightThumbY);
                _controller.SetSliderValue(Xbox360Slider.LeftTrigger, state.LeftTrigger);
                _controller.SetSliderValue(Xbox360Slider.RightTrigger, state.RightTrigger);
                _controller.SubmitReport();

                error = string.Empty;
                return true;
            }
            catch (Exception ex)
            {
                error = ex.Message;
                DisconnectLocked();
                return false;
            }
        }
    }

    public static void Disconnect()
    {
        lock (Sync)
        {
            DisconnectLocked();
        }
    }

    private static bool TryEnsureConnectedLocked(out string error)
    {
        if (_connected && _controller != null)
        {
            error = string.Empty;
            return true;
        }

        try
        {
            _client ??= new ViGEmClient();
            _controller = _client.CreateXbox360Controller();
            _controller.AutoSubmitReport = false;
            _controller.Connect();
            _connected = true;
            ResetReportLocked();

            error = string.Empty;
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            DisconnectLocked();
            return false;
        }
    }

    private static void ResetReportLocked()
    {
        if (_controller == null)
            return;

        _controller.ResetReport();
        _controller.SubmitReport();
    }

    private static void DisconnectLocked()
    {
        if (_controller != null)
        {
            try
            {
                if (_connected)
                    ResetReportLocked();
            }
            catch
            {
            }

            try
            {
                if (_connected)
                    _controller.Disconnect();
            }
            catch
            {
            }

            _controller = null;
        }

        try
        {
            _client?.Dispose();
        }
        catch
        {
        }

        _client = null;
        _connected = false;
    }
}
