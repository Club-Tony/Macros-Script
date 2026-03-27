/*
 * event_player.c -- Event playback with QPC timing
 *
 * Runs a dedicated thread that walks the event array, waits for each
 * event's timestamp using the high-resolution busy-wait from timing.c,
 * and dispatches the appropriate SendInput call.
 *
 * Supports:
 *   - Loop N times (loop_count > 0) or infinite looping (loop_count == 0)
 *   - Pause / resume via an event flag
 *   - Graceful stop
 */

#include "../include/macros_engine.h"
#include "timing.h"
#include <windows.h>
#include <string.h>

#ifndef MOUSEEVENTF_HWHEEL
#define MOUSEEVENTF_HWHEEL 0x01000
#endif

extern CRITICAL_SECTION g_engine_cs;

/* ================================================================
 * Module state
 * ================================================================ */

static HANDLE          g_play_thread     = NULL;
static volatile bool   g_playing         = false;
static volatile bool   g_paused          = false;
static volatile bool   g_stop_requested  = false;

/* Copy of the event buffer handed to the playback thread */
static MacroEvent     *g_play_events     = NULL;
static uint32_t        g_play_count      = 0;
static uint32_t        g_play_loops      = 0;   /* 0 = infinite */

/* ================================================================
 * Dispatch helpers
 * ================================================================ */

/* Mouse button codes used by the AHK format (matches VK values):
 *   1 = LButton, 2 = RButton, 3 = MButton, 4 = XButton1, 5 = XButton2 */

/* Extended key VK codes that require KEYEVENTF_EXTENDEDKEY */
static bool is_extended_key(uint16_t vk)
{
    switch (vk) {
    case VK_INSERT: case VK_DELETE: case VK_HOME: case VK_END:
    case VK_PRIOR:  case VK_NEXT:  case VK_UP:   case VK_DOWN:
    case VK_LEFT:   case VK_RIGHT: case VK_NUMLOCK:
    case VK_RCONTROL: case VK_RMENU: case VK_RWIN:
    case VK_LWIN:   case VK_APPS:  case VK_SNAPSHOT:
    case VK_DIVIDE:
        return true;
    default:
        return false;
    }
}

static void dispatch_key(const MacroEvent *evt)
{
    INPUT inp;
    memset(&inp, 0, sizeof(inp));
    inp.type           = INPUT_KEYBOARD;
    inp.ki.wVk         = evt->data.key.vk_code;
    inp.ki.wScan       = evt->data.key.scan_code;
    inp.ki.dwFlags     = (evt->data.key.scan_code ? KEYEVENTF_SCANCODE : 0);
    if (is_extended_key(evt->data.key.vk_code))
        inp.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
    if (evt->type == EVENT_KEY_UP)
        inp.ki.dwFlags |= KEYEVENTF_KEYUP;
    SendInput(1, &inp, sizeof(INPUT));
}

static void dispatch_mouse_move(const MacroEvent *evt)
{
    /* Absolute move -- normalize to 0..65535 range for SendInput */
    int sx = GetSystemMetrics(SM_CXSCREEN);
    int sy = GetSystemMetrics(SM_CYSCREEN);
    if (sx <= 0) sx = 1;
    if (sy <= 0) sy = 1;

    INPUT inp;
    memset(&inp, 0, sizeof(inp));
    inp.type        = INPUT_MOUSE;
    inp.mi.dx       = (LONG)(((int64_t)evt->data.mouse.x * 65535) / sx);
    inp.mi.dy       = (LONG)(((int64_t)evt->data.mouse.y * 65535) / sy);
    inp.mi.dwFlags  = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;
    SendInput(1, &inp, sizeof(INPUT));
}

static void dispatch_mouse_button(const MacroEvent *evt)
{
    INPUT inp;
    memset(&inp, 0, sizeof(inp));
    inp.type = INPUT_MOUSE;

    uint16_t btn  = evt->data.mouse_button.button;
    bool     down = (evt->type == EVENT_MOUSE_DOWN);

    switch (btn) {
    case 1:  /* LButton */
        inp.mi.dwFlags = down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
        break;
    case 2:  /* RButton */
        inp.mi.dwFlags = down ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP;
        break;
    case 3:  /* MButton */
        inp.mi.dwFlags = down ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP;
        break;
    case 4:  /* XButton1 */
        inp.mi.dwFlags = down ? MOUSEEVENTF_XDOWN : MOUSEEVENTF_XUP;
        inp.mi.mouseData = XBUTTON1;
        break;
    case 5:  /* XButton2 */
        inp.mi.dwFlags = down ? MOUSEEVENTF_XDOWN : MOUSEEVENTF_XUP;
        inp.mi.mouseData = XBUTTON2;
        break;
    default:
        return;
    }
    SendInput(1, &inp, sizeof(INPUT));
}

static void dispatch_mouse_wheel(const MacroEvent *evt)
{
    INPUT inp;
    memset(&inp, 0, sizeof(inp));
    inp.type = INPUT_MOUSE;
    int32_t delta = evt->data.wheel.delta;
    if (delta == 1 || delta == -1) {
        /* Lateral wheel event */
        inp.mi.dwFlags  = MOUSEEVENTF_HWHEEL;
        inp.mi.mouseData = (delta == 1) ? 120 : -120;
    } else {
        inp.mi.dwFlags  = MOUSEEVENTF_WHEEL;
        inp.mi.mouseData = (DWORD)delta;
    }
    SendInput(1, &inp, sizeof(INPUT));
}

static void dispatch_event(const MacroEvent *evt)
{
    switch (evt->type) {
    case EVENT_KEY_DOWN:
    case EVENT_KEY_UP:
        dispatch_key(evt);
        break;
    case EVENT_MOUSE_MOVE:
        dispatch_mouse_move(evt);
        break;
    case EVENT_MOUSE_DOWN:
    case EVENT_MOUSE_UP:
        dispatch_mouse_button(evt);
        break;
    case EVENT_MOUSE_WHEEL:
        dispatch_mouse_wheel(evt);
        break;
    case EVENT_CONTROLLER:
        /* Controller output requires vJoy -- log and skip */
        OutputDebugStringA("MacrosEngine: EVENT_CONTROLLER skipped (vJoy not implemented)\n");
        break;
    }
}

/* ================================================================
 * Playback thread
 * ================================================================ */

static DWORD WINAPI play_thread_proc(LPVOID param)
{
    (void)param;

    uint32_t loops_done = 0;

    while (!g_stop_requested) {
        /* Walk the event buffer */
        int64_t base_us = timing_get_us();

        for (uint32_t i = 0; i < g_play_count && !g_stop_requested; i++) {
            /* Handle pause */
            while (g_paused && !g_stop_requested)
                Sleep(5);

            if (g_stop_requested)
                break;

            /* Wait for this event's timestamp */
            int64_t target = base_us + g_play_events[i].timestamp_us;
            int64_t remain = target - timing_get_us();
            if (remain > 0)
                timing_sleep_us(remain);

            if (g_stop_requested)
                break;

            dispatch_event(&g_play_events[i]);
        }

        loops_done++;
        if (g_play_loops > 0 && loops_done >= g_play_loops)
            break;
    }

    g_playing = false;
    return 0;
}

/* ================================================================
 * Public API
 * ================================================================ */

ENGINE_API bool Engine_StartPlayback(const MacroEvent *events,
                                      uint32_t count,
                                      uint32_t loop_count)
{
    if (!Engine_IsInitialized() || !events || count == 0)
        return false;

    EnterCriticalSection(&g_engine_cs);

    if (g_playing) {
        LeaveCriticalSection(&g_engine_cs);
        return false;   /* already playing -- stop first */
    }

    /* Copy events into our own buffer */
    MacroEvent *buf = (MacroEvent *)malloc(count * sizeof(MacroEvent));
    if (!buf) {
        LeaveCriticalSection(&g_engine_cs);
        return false;
    }
    memcpy(buf, events, count * sizeof(MacroEvent));

    /* Free any previous buffer */
    free(g_play_events);
    g_play_events    = buf;
    g_play_count     = count;
    g_play_loops     = loop_count;
    g_stop_requested = false;
    g_paused         = false;
    g_playing        = true;

    g_play_thread = CreateThread(NULL, 0, play_thread_proc, NULL, 0, NULL);
    if (!g_play_thread) {
        g_playing = false;
        LeaveCriticalSection(&g_engine_cs);
        return false;
    }

    LeaveCriticalSection(&g_engine_cs);
    return true;
}

ENGINE_API void Engine_StopPlayback(void)
{
    if (!g_playing && !g_play_thread)
        return;

    g_stop_requested = true;
    g_paused = false;   /* un-pause so the thread can exit */

    if (g_play_thread) {
        DWORD wait_result = WaitForSingleObject(g_play_thread, 3000);
        if (wait_result == WAIT_TIMEOUT)
            TerminateThread(g_play_thread, 1);
        CloseHandle(g_play_thread);
        g_play_thread = NULL;
    }
    g_playing = false;
}

ENGINE_API void Engine_PausePlayback(void)
{
    g_paused = true;
}

ENGINE_API void Engine_ResumePlayback(void)
{
    g_paused = false;
}

ENGINE_API bool Engine_IsPlaying(void)
{
    return g_playing;
}

ENGINE_API bool Engine_IsPaused(void)
{
    return g_paused;
}

/* ================================================================
 * Cleanup (called by Engine_Shutdown)
 * ================================================================ */

void player_cleanup(void)
{
    free(g_play_events);
    g_play_events = NULL;
    g_play_count  = 0;
}
