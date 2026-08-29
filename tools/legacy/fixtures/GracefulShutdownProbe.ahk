#NoEnv
#NoTrayIcon
#Persistent
#SingleInstance, Off
OnExit("GracefulExit")
return

GracefulExit(exitReason, exitCode)
{
    if (A_Args.Length() > 0)
        FileAppend, graceful, % A_Args[1]
}
