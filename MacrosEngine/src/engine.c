/*
 * engine.c -- Core engine init / shutdown / state management
 *
 * Owns the global mutex and the initialized flag.  Every other module
 * checks Engine_IsInitialized() before touching shared state.
 */

#include "../include/macros_engine.h"
#include "timing.h"
#include <windows.h>

/* ---- globals visible to other translation units via extern ----- */
CRITICAL_SECTION g_engine_cs;        /* protects all shared state   */
static volatile LONG g_initialized = 0;   /* 0 = false, 1 = true   */

/* One-time init guard for the critical section itself.
 * 0 = not started, 1 = in progress, 2 = done */
static volatile LONG g_cs_init_state = 0;

/* Defined in other modules -- called during shutdown */
extern void poller_cleanup(void);
extern void recorder_cleanup(void);
extern void player_cleanup(void);

/* Ensure the critical section is initialized exactly once (MinGW-safe) */
static void ensure_cs_initialized(void)
{
    if (InterlockedCompareExchange(&g_cs_init_state, 1, 0) == 0) {
        /* We won the race -- initialize */
        InitializeCriticalSection(&g_engine_cs);
        InterlockedExchange(&g_cs_init_state, 2);
    } else {
        /* Another thread is initializing or already done -- spin until ready */
        while (InterlockedCompareExchange(&g_cs_init_state, 2, 2) != 2)
            Sleep(0);
    }
}

/* ----------------------------------------------------------------
 * Engine_Init
 * ---------------------------------------------------------------- */
ENGINE_API bool Engine_Init(void)
{
    if (g_initialized)
        return true;

    ensure_cs_initialized();

    EnterCriticalSection(&g_engine_cs);
    if (g_initialized) {
        /* Another thread won the race */
        LeaveCriticalSection(&g_engine_cs);
        return true;
    }

    timing_init();
    InterlockedExchange(&g_initialized, 1);

    LeaveCriticalSection(&g_engine_cs);
    return true;
}

/* ----------------------------------------------------------------
 * Engine_Shutdown
 * ---------------------------------------------------------------- */
ENGINE_API void Engine_Shutdown(void)
{
    if (!g_initialized)
        return;

    EnterCriticalSection(&g_engine_cs);
    if (!g_initialized) {
        LeaveCriticalSection(&g_engine_cs);
        return;
    }
    LeaveCriticalSection(&g_engine_cs);

    /* Stop active operations while still "initialized" so their
     * Engine_IsInitialized() guards pass */
    Engine_StopPolling();
    Engine_StopPlayback();
    Engine_StopRecording();

    /* Now mark as not initialized to prevent new operations */
    InterlockedExchange(&g_initialized, 0);

    poller_cleanup();
    recorder_cleanup();
    player_cleanup();
    timing_cleanup();

    /* Note: we intentionally do NOT DeleteCriticalSection here.
     * It was initialized via the one-time guard and remains valid for
     * future Engine_Init calls. This is safe since the CS is process-lifetime. */
}

/* ----------------------------------------------------------------
 * Engine_IsInitialized
 * ---------------------------------------------------------------- */
ENGINE_API bool Engine_IsInitialized(void)
{
    return g_initialized != 0;
}

/* ----------------------------------------------------------------
 * Engine_GetVersion
 * ---------------------------------------------------------------- */
ENGINE_API const char* Engine_GetVersion(void)
{
    return "MacrosEngine 1.0.0";
}
