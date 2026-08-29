using System.IO.Pipes;
using System.Text;

namespace MacrosApp;

public sealed class ControlPipeServer : IDisposable
{
    public static string PipeName => "MacrosApp.Control." + Environment.UserName +
        (Environment.GetEnvironmentVariable("MACROSAPP_INSTANCE_SUFFIX") is { Length: > 0 } suffix ? "." + suffix : string.Empty);

    private readonly CancellationTokenSource _cancel = new();
    private readonly Action _shutdown;
    private readonly Task _listener;

    public ControlPipeServer(Action shutdown)
    {
        _shutdown = shutdown;
        _listener = Task.Run(ListenAsync);
    }

    private async Task ListenAsync()
    {
        while (!_cancel.IsCancellationRequested)
        {
            try
            {
                await using var pipe = new NamedPipeServerStream(
                    PipeName,
                    PipeDirection.InOut,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await pipe.WaitForConnectionAsync(_cancel.Token).ConfigureAwait(false);
                using var reader = new StreamReader(pipe, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);
                using var writer = new StreamWriter(pipe, new UTF8Encoding(false), leaveOpen: true) { AutoFlush = true };
                string command = (await reader.ReadLineAsync(_cancel.Token).ConfigureAwait(false) ?? string.Empty).Trim();
                if (command.Equals("status", StringComparison.OrdinalIgnoreCase))
                    await writer.WriteLineAsync("running").ConfigureAwait(false);
                else if (command.Equals("shutdown", StringComparison.OrdinalIgnoreCase))
                {
                    await writer.WriteLineAsync("ok").ConfigureAwait(false);
                    _shutdown();
                }
                else
                    await writer.WriteLineAsync("unknown").ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (IOException)
            {
                if (_cancel.IsCancellationRequested)
                    break;
            }
        }
    }

    public void Dispose()
    {
        _cancel.Cancel();
        try { _listener.Wait(TimeSpan.FromSeconds(1)); } catch { }
        _cancel.Dispose();
    }
}
