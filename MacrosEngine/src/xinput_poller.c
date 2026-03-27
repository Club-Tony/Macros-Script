/*
 * xinput_poller.c -- Threaded XInput polling with dynamic DLL loading
 *
 * Loads xinput1_3.dll (or xinput1_4.dll / xinput9_1_0.dll as fallbacks)
 * at runtime via LoadLibrary so the DLL works even on systems without
 * XInput installed.  Polls at a configurable interval on a dedicated
 * thread and stores the latest state behind the engine critical section.
 */

#include "../include/macros_engine.h"
#include "timing.h"
#include <windows.h>
#include <string.h>

/* ================================================================
 * XInput type / constant definitions (MinGW may lack the headers)
 * ================================================================ */

#define MAX_PLAYERS 4

#define XINPUT_GAMEPAD_DPAD_UP        0x0001
#define XINPUT_GAMEPAD_DPAD_DOWN      0x0002
#define XINPUT_GAMEPAD_DPAD_LEFT      0x0004
#define XINPUT_GAMEPAD_DPAD_RIGHT     0x0008
#define XINPUT_GAMEPAD_START          0x0010
#define XINPUT_GAMEPAD_BACK           0x0020
#define XINPUT_GAMEPAD_LEFT_THUMB     0x0040
#define XINPUT_GAMEPAD_RIGHT_THUMB    0x0080
#define XINPUT_GAMEPAD_LEFT_SHOULDER  0x0100
#define XINPUT_GAMEPAD_RIGHT_SHOULDER 0x0200
#define XINPUT_GAMEPAD_A              0x1000
#define XINPUT_GAMEPAD_B              0x2000
#define XINPUT_GAMEPAD_X              0x4000
#define XINPUT_GAMEPAD_Y              0x8000

#define XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE  7849
#define XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE 8689
#define XINPUT_GAMEPAD_TRIGGER_THRESHOLD    30

#ifndef ERROR_DEVICE_NOT_CONNECTED
#define ERROR_DEVICE_NOT_CONNECTED 1167
#endif

#pragma pack(push, 2)
typedef struct {
    uint16_t wButtons;
    uint8_t  bLeftTrigger;
    uint8_t  bRightTrigger;
    int16_t  sThumbLX;
    int16_t  sThumbLY;
    int16_t  sThumbRX;
    int16_t  sThumbRY;
} XINPUT_GAMEPAD_S;

typedef struct {
    uint32_t        dwPacketNumber;
    XINPUT_GAMEPAD_S Gamepad;
} XINPUT_STATE_S;
#pragma pack(pop)

typedef DWORD (WINAPI *XInputGetState_t)(DWORD dwUserIndex,
                                          XINPUT_STATE_S *pState);

/* ================================================================
 * Module state
 * ================================================================ */

extern CRITICAL_SECTION g_engine_cs;

static HMODULE           g_xinput_dll   = NULL;
static XInputGetState_t  g_XInputGetState = NULL;

static HANDLE            g_poll_thread  = NULL;
static volatile bool     g_poll_running = false;
static uint32_t          g_poll_interval_ms = 4;  /* ~250 Hz default */

static ControllerState   g_states[MAX_PLAYERS];

/* Per-player deadzones */
static int16_t           g_thumb_deadzone[MAX_PLAYERS];
static uint8_t           g_trigger_deadzone[MAX_PLAYERS];

/* ================================================================
 * Internal helpers
 * ================================================================ */

/* Try to load XInput from multiple DLL names.  Returns true on success. */
static bool load_xinput(void)
{
    if (g_xinput_dll)
        return true;

    static const char *dll_names[] = {
        "xinput1_4.dll",
        "xinput1_3.dll",
        "xinput9_1_0.dll",
        NULL
    };

    for (int i = 0; dll_names[i]; i++) {
        g_xinput_dll = LoadLibraryA(dll_names[i]);
        if (g_xinput_dll) {
            g_XInputGetState = (XInputGetState_t)
                GetProcAddress(g_xinput_dll, "XInputGetState");
            if (g_XInputGetState)
                return true;
            FreeLibrary(g_xinput_dll);
            g_xinput_dll = NULL;
        }
    }
    return false;
}

/* Apply deadzones: zero out values below the threshold. */
static void apply_deadzone(ControllerState *cs, uint32_t idx)
{
    int16_t tdz = g_thumb_deadzone[idx];
    uint8_t gdz = g_trigger_deadzone[idx];

    if (cs->left_thumb_x > -tdz && cs->left_thumb_x < tdz)
        cs->left_thumb_x = 0;
    if (cs->left_thumb_y > -tdz && cs->left_thumb_y < tdz)
        cs->left_thumb_y = 0;
    if (cs->right_thumb_x > -tdz && cs->right_thumb_x < tdz)
        cs->right_thumb_x = 0;
    if (cs->right_thumb_y > -tdz && cs->right_thumb_y < tdz)
        cs->right_thumb_y = 0;

    if (cs->left_trigger < gdz)
        cs->left_trigger = 0;
    if (cs->right_trigger < gdz)
        cs->right_trigger = 0;
}

/* ================================================================
 * Poll thread
 * ================================================================ */

static DWORD WINAPI poll_thread_proc(LPVOID param)
{
    (void)param;

    while (g_poll_running) {
        for (uint32_t i = 0; i < MAX_PLAYERS; i++) {
            XINPUT_STATE_S xs;
            memset(&xs, 0, sizeof(xs));

            DWORD result = g_XInputGetState(i, &xs);

            EnterCriticalSection(&g_engine_cs);
            if (result == 0) {  /* ERROR_SUCCESS */
                g_states[i].connected     = true;
                g_states[i].buttons       = xs.Gamepad.wButtons;
                g_states[i].left_trigger  = xs.Gamepad.bLeftTrigger;
                g_states[i].right_trigger = xs.Gamepad.bRightTrigger;
                g_states[i].left_thumb_x  = xs.Gamepad.sThumbLX;
                g_states[i].left_thumb_y  = xs.Gamepad.sThumbLY;
                g_states[i].right_thumb_x = xs.Gamepad.sThumbRX;
                g_states[i].right_thumb_y = xs.Gamepad.sThumbRY;
                apply_deadzone(&g_states[i], i);
            } else {
                g_states[i].connected = false;
            }
            LeaveCriticalSection(&g_engine_cs);
        }

        Sleep(g_poll_interval_ms);
    }
    return 0;
}

/* ================================================================
 * Public API
 * ================================================================ */

ENGINE_API bool Engine_StartPolling(uint32_t interval_ms)
{
    if (!Engine_IsInitialized())
        return false;
    if (g_poll_running)
        return true;   /* already running */

    if (!load_xinput())
        return false;  /* XInput not available */

    /* Set default deadzones for any player that hasn't been configured */
    for (int i = 0; i < MAX_PLAYERS; i++) {
        if (g_thumb_deadzone[i] == 0)
            g_thumb_deadzone[i] = XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE;
        if (g_trigger_deadzone[i] == 0)
            g_trigger_deadzone[i] = XINPUT_GAMEPAD_TRIGGER_THRESHOLD;
    }

    g_poll_interval_ms = (interval_ms > 0) ? interval_ms : 4;
    g_poll_running = true;

    g_poll_thread = CreateThread(NULL, 0, poll_thread_proc, NULL, 0, NULL);
    if (!g_poll_thread) {
        g_poll_running = false;
        return false;
    }
    return true;
}

ENGINE_API void Engine_StopPolling(void)
{
    if (!g_poll_running)
        return;

    g_poll_running = false;
    if (g_poll_thread) {
        WaitForSingleObject(g_poll_thread, 2000);
        CloseHandle(g_poll_thread);
        g_poll_thread = NULL;
    }
}

ENGINE_API bool Engine_GetControllerState(uint32_t player_index,
                                           ControllerState *state)
{
    if (!state || player_index >= MAX_PLAYERS)
        return false;
    if (!Engine_IsInitialized())
        return false;

    EnterCriticalSection(&g_engine_cs);
    *state = g_states[player_index];
    LeaveCriticalSection(&g_engine_cs);
    return true;
}

ENGINE_API void Engine_SetDeadzone(uint32_t player_index,
                                    int16_t  thumb_deadzone,
                                    uint8_t  trigger_deadzone)
{
    if (player_index >= MAX_PLAYERS)
        return;
    if (!Engine_IsInitialized())
        return;

    EnterCriticalSection(&g_engine_cs);
    g_thumb_deadzone[player_index]   = thumb_deadzone;
    g_trigger_deadzone[player_index] = trigger_deadzone;
    LeaveCriticalSection(&g_engine_cs);
}

/* ================================================================
 * Cleanup (called by Engine_Shutdown)
 * ================================================================ */

void poller_cleanup(void)
{
    if (g_xinput_dll) {
        FreeLibrary(g_xinput_dll);
        g_xinput_dll = NULL;
        g_XInputGetState = NULL;
    }
    memset(g_states, 0, sizeof(g_states));
}
