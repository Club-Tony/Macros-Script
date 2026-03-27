/*
 * event_recorder.c -- Event recording with dynamic buffer and timestamps
 *
 * Records events into a realloc-growing array.  Each event is stamped
 * with the elapsed microseconds since Engine_StartRecording() was
 * called.  Thread-safe via the engine critical section.
 *
 * External callers (AHK, C#) inject events through the Engine_Record*
 * family of functions.
 */

#include "../include/macros_engine.h"
#include "timing.h"
#include <windows.h>
#include <stdlib.h>
#include <string.h>

extern CRITICAL_SECTION g_engine_cs;

/* ================================================================
 * Module state
 * ================================================================ */

#define INITIAL_CAPACITY 4096

static MacroEvent *g_events     = NULL;
static uint32_t    g_count      = 0;
static uint32_t    g_capacity   = 0;
static bool        g_recording  = false;
static int64_t     g_start_us   = 0;

/* ================================================================
 * Internal helpers
 * ================================================================ */

/* Ensure room for at least one more event.  Caller must hold g_engine_cs. */
static bool ensure_capacity(void)
{
    if (g_count < g_capacity)
        return true;

    uint32_t new_cap = (g_capacity == 0) ? INITIAL_CAPACITY : g_capacity * 2;
    MacroEvent *tmp = (MacroEvent *)realloc(g_events,
                                             new_cap * sizeof(MacroEvent));
    if (!tmp)
        return false;
    g_events   = tmp;
    g_capacity = new_cap;
    return true;
}

/* Append one event.  Caller must hold g_engine_cs. */
static bool push_event(const MacroEvent *evt)
{
    if (!ensure_capacity())
        return false;
    g_events[g_count++] = *evt;
    return true;
}

/* ================================================================
 * Public API
 * ================================================================ */

ENGINE_API bool Engine_StartRecording(void)
{
    if (!Engine_IsInitialized())
        return false;

    EnterCriticalSection(&g_engine_cs);

    /* Reset buffer */
    g_count = 0;
    g_recording = true;
    g_start_us  = timing_get_us();

    LeaveCriticalSection(&g_engine_cs);
    return true;
}

ENGINE_API void Engine_StopRecording(void)
{
    if (!Engine_IsInitialized())
        return;
    EnterCriticalSection(&g_engine_cs);
    g_recording = false;
    LeaveCriticalSection(&g_engine_cs);
}

ENGINE_API bool Engine_IsRecording(void)
{
    if (!Engine_IsInitialized())
        return false;
    bool r;
    EnterCriticalSection(&g_engine_cs);
    r = g_recording;
    LeaveCriticalSection(&g_engine_cs);
    return r;
}

ENGINE_API uint32_t Engine_GetRecordedEventCount(void)
{
    if (!Engine_IsInitialized())
        return 0;
    uint32_t n;
    EnterCriticalSection(&g_engine_cs);
    n = g_count;
    LeaveCriticalSection(&g_engine_cs);
    return n;
}

ENGINE_API bool Engine_GetRecordedEvents(MacroEvent *buffer,
                                          uint32_t   buffer_size,
                                          uint32_t  *out_count)
{
    if (!buffer || !out_count)
        return false;
    if (!Engine_IsInitialized())
        return false;

    EnterCriticalSection(&g_engine_cs);

    uint32_t copy = (g_count < buffer_size) ? g_count : buffer_size;
    if (copy > 0 && g_events != NULL)
        memcpy(buffer, g_events, copy * sizeof(MacroEvent));
    else
        copy = 0;
    *out_count = copy;

    LeaveCriticalSection(&g_engine_cs);
    return true;
}

/* ================================================================
 * Manual event injection (called from AHK / C# UI)
 * ================================================================ */

ENGINE_API bool Engine_RecordKeyEvent(bool     down,
                                       uint16_t vk_code,
                                       uint16_t scan_code)
{
    if (!Engine_IsInitialized())
        return false;

    MacroEvent evt;
    memset(&evt, 0, sizeof(evt));
    evt.type = down ? EVENT_KEY_DOWN : EVENT_KEY_UP;
    evt.data.key.vk_code   = vk_code;
    evt.data.key.scan_code = scan_code;

    EnterCriticalSection(&g_engine_cs);
    if (!g_recording) {
        LeaveCriticalSection(&g_engine_cs);
        return false;
    }
    evt.timestamp_us = timing_get_us() - g_start_us;
    bool ok = push_event(&evt);
    LeaveCriticalSection(&g_engine_cs);
    return ok;
}

ENGINE_API bool Engine_RecordMouseMove(int32_t x, int32_t y)
{
    if (!Engine_IsInitialized())
        return false;

    MacroEvent evt;
    memset(&evt, 0, sizeof(evt));
    evt.type         = EVENT_MOUSE_MOVE;
    evt.data.mouse.x = x;
    evt.data.mouse.y = y;

    EnterCriticalSection(&g_engine_cs);
    if (!g_recording) {
        LeaveCriticalSection(&g_engine_cs);
        return false;
    }
    evt.timestamp_us = timing_get_us() - g_start_us;
    bool ok = push_event(&evt);
    LeaveCriticalSection(&g_engine_cs);
    return ok;
}

ENGINE_API bool Engine_RecordMouseButton(bool down, uint16_t button)
{
    if (!Engine_IsInitialized())
        return false;

    MacroEvent evt;
    memset(&evt, 0, sizeof(evt));
    evt.type = down ? EVENT_MOUSE_DOWN : EVENT_MOUSE_UP;
    evt.data.mouse_button.button = button;

    EnterCriticalSection(&g_engine_cs);
    if (!g_recording) {
        LeaveCriticalSection(&g_engine_cs);
        return false;
    }
    evt.timestamp_us = timing_get_us() - g_start_us;
    bool ok = push_event(&evt);
    LeaveCriticalSection(&g_engine_cs);
    return ok;
}

ENGINE_API bool Engine_RecordMouseWheel(int32_t delta)
{
    if (!Engine_IsInitialized())
        return false;

    MacroEvent evt;
    memset(&evt, 0, sizeof(evt));
    evt.type           = EVENT_MOUSE_WHEEL;
    evt.data.wheel.delta = delta;

    EnterCriticalSection(&g_engine_cs);
    if (!g_recording) {
        LeaveCriticalSection(&g_engine_cs);
        return false;
    }
    evt.timestamp_us = timing_get_us() - g_start_us;
    bool ok = push_event(&evt);
    LeaveCriticalSection(&g_engine_cs);
    return ok;
}

/* ================================================================
 * Cleanup (called by Engine_Shutdown)
 * ================================================================ */

void recorder_cleanup(void)
{
    free(g_events);
    g_events   = NULL;
    g_count    = 0;
    g_capacity = 0;
    g_recording = false;
}
