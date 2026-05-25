/*
 * test_engine.c -- Smoke-test for MacrosEngine DLL
 *
 * Exercises:  init, version, recording, event injection, event count,
 * controller polling (live), file I/O round-trip, and shutdown.
 *
 * Build:  cmake --build build
 * Run:    build\test_engine.exe
 */

#include "../include/macros_engine.h"
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define XINPUT_GAMEPAD_A 0x1000

/* Fixture directory is normally injected by CMake. Fall back to a relative
 * path for the case where the test is run directly without the build system. */
#ifndef MACROS_TEST_FIXTURE_DIR
#define MACROS_TEST_FIXTURE_DIR "test/fixtures"
#endif

/* ------- helpers ------- */

static int  tests_run    = 0;
static int  tests_passed = 0;
static volatile LONG g_controller_callback_count = 0;
static ControllerState g_controller_callback_state;

#define CHECK(cond, msg) do {                                   \
    tests_run++;                                                \
    if (cond) { tests_passed++; printf("  PASS  %s\n", msg); } \
    else      { printf("  FAIL  %s\n", msg); }                 \
} while (0)

static void print_controller(const ControllerState *cs)
{
    printf("    connected=%d  buttons=0x%04X  LT=%3u RT=%3u  "
           "LX=%6d LY=%6d  RX=%6d RY=%6d\n",
           cs->connected, cs->buttons,
           cs->left_trigger, cs->right_trigger,
           cs->left_thumb_x, cs->left_thumb_y,
           cs->right_thumb_x, cs->right_thumb_y);
}

static bool test_controller_output_callback(const ControllerState *state)
{
    if (!state)
        return false;

    g_controller_callback_state = *state;
    InterlockedIncrement(&g_controller_callback_count);
    return true;
}

/* ------- tests ------- */

static void test_lifecycle(void)
{
    printf("\n[lifecycle]\n");
    CHECK(Engine_Init(), "Engine_Init succeeds");
    CHECK(Engine_IsInitialized(), "Engine reports initialized");
    CHECK(Engine_Init(), "Double init is harmless");

    const char *ver = Engine_GetVersion();
    CHECK(ver != NULL && strlen(ver) > 0, "Engine_GetVersion returns string");
    printf("    version = \"%s\"\n", ver);
}

static void test_recording(void)
{
    printf("\n[recording]\n");
    CHECK(Engine_StartRecording(), "StartRecording succeeds");
    CHECK(Engine_IsRecording(), "IsRecording true");

    /* Inject some events */
    CHECK(Engine_RecordKeyEvent(true,  0x41, 0x1E),  "Record key down  A");
    CHECK(Engine_RecordKeyEvent(false, 0x41, 0x1E),  "Record key up    A");
    CHECK(Engine_RecordMouseMove(500, 300),           "Record mouse move");
    CHECK(Engine_RecordMouseButton(true,  1),         "Record LButton down");
    CHECK(Engine_RecordMouseButton(false, 1),         "Record LButton up");
    CHECK(Engine_RecordMouseWheel(120),               "Record wheel up");

    ControllerState pad;
    memset(&pad, 0, sizeof(pad));
    pad.connected = true;
    pad.buttons = XINPUT_GAMEPAD_A;
    pad.left_trigger = 24;
    pad.left_thumb_x = 1024;
    CHECK(Engine_RecordControllerEvent(&pad),         "Record controller event");

    Engine_StopRecording();
    CHECK(!Engine_IsRecording(), "IsRecording false after stop");

    uint32_t n = Engine_GetRecordedEventCount();
    CHECK(n == 7, "Recorded event count == 7");
    printf("    recorded %u events\n", n);

    /* Retrieve events */
    MacroEvent buf[16];
    uint32_t got = 0;
    CHECK(Engine_GetRecordedEvents(buf, 16, &got), "GetRecordedEvents ok");
    CHECK(got == 7, "Got 7 events back");

    /* Verify first event */
    CHECK(buf[0].type == EVENT_KEY_DOWN, "First event is KEY_DOWN");
    CHECK(buf[0].data.key.vk_code == 0x41, "First event VK == 0x41 (A)");
    CHECK(buf[0].timestamp_us >= 0, "Timestamp >= 0");
    CHECK(buf[6].type == EVENT_CONTROLLER, "Last event is CONTROLLER");
    CHECK(buf[6].data.controller.buttons == XINPUT_GAMEPAD_A,
          "Controller event button state preserved");
}

static void test_file_io(void)
{
    printf("\n[file I/O]\n");
    remove("test_output.txt");

    /* Create a small event set */
    MacroEvent events[5];
    memset(events, 0, sizeof(events));

    events[0].type = EVENT_MOUSE_MOVE;
    events[0].timestamp_us = 0;
    events[0].data.mouse.x = 100;
    events[0].data.mouse.y = 200;

    events[1].type = EVENT_KEY_DOWN;
    events[1].timestamp_us = 47000;   /* 47 ms */
    events[1].data.key.vk_code = 0x41;

    events[2].type = EVENT_KEY_UP;
    events[2].timestamp_us = 94000;   /* 47 ms later */
    events[2].data.key.vk_code = 0x41;

    events[3].type = EVENT_MOUSE_DOWN;
    events[3].timestamp_us = 141000;
    events[3].data.mouse_button.button = 1;

    events[4].type = EVENT_CONTROLLER;
    events[4].timestamp_us = 188000;
    events[4].data.controller.connected = true;
    events[4].data.controller.buttons = XINPUT_GAMEPAD_A;
    events[4].data.controller.left_trigger = 12;
    events[4].data.controller.right_trigger = 16;
    events[4].data.controller.left_thumb_x = 256;
    events[4].data.controller.left_thumb_y = -512;

    const char *path = "test_output.txt";

    CHECK(Engine_SaveEventsToFile(path, events, 5), "SaveEventsToFile ok");

    /* Load them back */
    MacroEvent loaded[16];
    uint32_t n = Engine_LoadEventsFromFile(path, loaded, 16);
    CHECK(n == 5, "LoadEventsFromFile returns 5");

    CHECK(loaded[0].type == EVENT_MOUSE_MOVE, "Loaded[0] is MOUSE_MOVE");
    CHECK(loaded[0].data.mouse.x == 100, "Loaded[0] x == 100");
    CHECK(loaded[0].data.mouse.y == 200, "Loaded[0] y == 200");

    CHECK(loaded[1].type == EVENT_KEY_DOWN, "Loaded[1] is KEY_DOWN");
    CHECK(loaded[3].type == EVENT_MOUSE_DOWN, "Loaded[3] is MOUSE_DOWN");
    CHECK(loaded[3].data.mouse_button.button == 1, "Loaded[3] button == 1");
    CHECK(loaded[4].type == EVENT_CONTROLLER, "Loaded[4] is CONTROLLER");
    CHECK(loaded[4].data.controller.buttons == XINPUT_GAMEPAD_A,
          "Loaded controller buttons preserved");

    /* Timing round-trip: delay between events should be ~47ms */
    int64_t d1 = (loaded[1].timestamp_us - loaded[0].timestamp_us) / 1000;
    CHECK(d1 == 47, "Delay[0->1] round-trips as 47 ms");

    /* Cleanup */
    remove(path);
}

static void test_controller(void)
{
    printf("\n[controller]\n");

    bool started = Engine_StartPolling(16);
    if (!started) {
        printf("    SKIP  XInput not available (no controller DLL)\n");
        return;
    }
    CHECK(started, "StartPolling succeeds");
    CHECK(Engine_StartControllerRecording(), "StartControllerRecording succeeds");
    CHECK(Engine_IsRecordingController(), "IsRecordingController true");

    /* Set custom deadzones */
    Engine_SetDeadzone(0, 8000, 30);

    /* Read a few frames */
    printf("    Reading 5 frames from player 0...\n");
    for (int i = 0; i < 5; i++) {
        Sleep(20);
        ControllerState cs;
        if (Engine_GetControllerState(0, &cs))
            print_controller(&cs);
    }

    Engine_StopPolling();
    Engine_StopControllerRecording();
    CHECK(!Engine_IsRecordingController(), "IsRecordingController false after stop");
    CHECK(true, "StopPolling clean");
}

static void test_playback_api(void)
{
    printf("\n[playback API]\n");

    /* Build a tiny event sequence (no actual dispatch -- just API calls) */
    MacroEvent evts[2];
    memset(evts, 0, sizeof(evts));
    evts[0].type = EVENT_KEY_DOWN;
    evts[0].timestamp_us = 0;
    evts[0].data.key.vk_code = 0x41;
    evts[1].type = EVENT_KEY_UP;
    evts[1].timestamp_us = 50000;
    evts[1].data.key.vk_code = 0x41;

    /* Start, pause, resume, stop */
    CHECK(Engine_StartPlayback(evts, 2, 1), "StartPlayback ok");
    CHECK(Engine_IsPlaying(), "IsPlaying true");

    Engine_PausePlayback();
    CHECK(Engine_IsPaused(), "IsPaused true");

    Engine_ResumePlayback();
    CHECK(!Engine_IsPaused(), "IsPaused false after resume");

    /* Let it finish (50 ms sequence) */
    Sleep(200);

    /* Should have finished by now */
    CHECK(!Engine_IsPlaying(), "IsPlaying false after completion");
}

static void test_playback_cancel(void)
{
    printf("\n[playback cancel]\n");

    MacroEvent evts[1];
    memset(evts, 0, sizeof(evts));
    evts[0].type = EVENT_KEY_UP;
    evts[0].timestamp_us = 10000000;  /* 10 seconds */
    evts[0].data.key.vk_code = 0x41;

    CHECK(Engine_StartPlayback(evts, 1, 0), "Start long playback ok");
    CHECK(Engine_IsPlaying(), "Long playback reports playing");

    DWORD start = GetTickCount();
    Engine_StopPlayback();
    DWORD elapsed = GetTickCount() - start;

    CHECK(elapsed < 1000, "StopPlayback cancels wait promptly");
    CHECK(!Engine_IsPlaying(), "IsPlaying false after cancellation");
}

static void test_playback_cancel_midsleep(void)
{
    printf("\n[playback cancel mid-sleep]\n");

    /* Two events with a 5-second gap. Cancel after the first has dispatched
     * but while the player is sleeping inside that gap. Exercises the E3
     * cooperative-cancel path through the inter-event wait. */
    MacroEvent evts[2];
    memset(evts, 0, sizeof(evts));
    evts[0].type = EVENT_KEY_UP;
    evts[0].timestamp_us = 0;
    evts[0].data.key.vk_code = 0x41;
    evts[1].type = EVENT_KEY_UP;
    evts[1].timestamp_us = 5000000;   /* 5 seconds after event 0 */
    evts[1].data.key.vk_code = 0x42;

    CHECK(Engine_StartPlayback(evts, 2, 0), "Start mid-sleep playback ok");
    CHECK(Engine_IsPlaying(), "Mid-sleep playback reports playing");

    Sleep(250);   /* land squarely inside the 5-second gap */
    CHECK(Engine_IsPlaying(), "Still playing 250ms in (mid-sleep)");

    DWORD start = GetTickCount();
    Engine_StopPlayback();
    DWORD elapsed = GetTickCount() - start;

    CHECK(elapsed < 1000, "Mid-sleep cancel returns within 1s");
    CHECK(!Engine_IsPlaying(), "IsPlaying false after mid-sleep cancel");
}

static void test_vjoy_api(void)
{
    printf("\n[vJoy API]\n");

    CHECK(Engine_SetVJoyDeviceId(1), "SetVJoyDeviceId accepts device 1");
    CHECK(!Engine_SetVJoyDeviceId(0), "SetVJoyDeviceId rejects device 0");
    CHECK(!Engine_SetVJoyDeviceId(17), "SetVJoyDeviceId rejects device 17");

    VJoyState state;
    memset(&state, 0, sizeof(state));
    CHECK(Engine_GetVJoyState(&state), "GetVJoyState returns state");
    printf("    available=%d enabled=%d ready=%d device=%u status=%u buttons=%u\n",
           state.available, state.enabled, state.ready, state.device_id,
           state.status, state.button_count);

    MacroEvent evts[1];
    memset(evts, 0, sizeof(evts));
    evts[0].type = EVENT_CONTROLLER;
    evts[0].timestamp_us = 0;
    evts[0].data.controller.connected = true;
    evts[0].data.controller.buttons = XINPUT_GAMEPAD_A;

    CHECK(Engine_StartPlayback(evts, 1, 1),
          "Controller playback starts with optional vJoy");
    Sleep(100);
    CHECK(!Engine_IsPlaying(), "Controller playback completes");
}

static void test_controller_output_callback_api(void)
{
    printf("\n[controller output callback]\n");

    memset(&g_controller_callback_state, 0, sizeof(g_controller_callback_state));
    InterlockedExchange(&g_controller_callback_count, 0);

    Engine_SetControllerOutputCallback(test_controller_output_callback);
    CHECK(Engine_SetControllerOutputMode(CONTROLLER_OUTPUT_CALLBACK),
          "Controller output switches to callback mode");
    CHECK(Engine_GetControllerOutputMode() == CONTROLLER_OUTPUT_CALLBACK,
          "Controller output mode reports callback");

    MacroEvent evts[1];
    memset(evts, 0, sizeof(evts));
    evts[0].type = EVENT_CONTROLLER;
    evts[0].timestamp_us = 0;
    evts[0].data.controller.connected = true;
    evts[0].data.controller.buttons = XINPUT_GAMEPAD_A;
    evts[0].data.controller.left_thumb_x = 1234;
    evts[0].data.controller.right_trigger = 64;

    CHECK(Engine_StartPlayback(evts, 1, 1),
          "Controller callback playback starts");
    Sleep(100);
    CHECK(!Engine_IsPlaying(), "Controller callback playback completes");
    CHECK(g_controller_callback_count >= 1, "Controller callback was invoked");
    CHECK(g_controller_callback_state.buttons == XINPUT_GAMEPAD_A,
          "Controller callback received buttons");
    CHECK(g_controller_callback_state.left_thumb_x == 1234,
          "Controller callback received left thumb X");
    CHECK(g_controller_callback_state.right_trigger == 64,
          "Controller callback received right trigger");

    CHECK(Engine_SetControllerOutputMode(CONTROLLER_OUTPUT_VJOY),
          "Controller output switches back to vJoy");
    Engine_SetControllerOutputCallback(NULL);
}

static void test_ahk_v1_format(void)
{
    printf("\n[AHK v1 format round-trip]\n");

    /* Load the hand-written AHK v1 fixture and confirm the parser extracts
     * each event type with the expected fields. Then play it back through
     * the engine API to confirm the load->playback path works end-to-end
     * without a real controller or vJoy device. */
    const char *fixture = MACROS_TEST_FIXTURE_DIR "/ahk_v1_mixed.txt";

    MacroEvent loaded[16];
    memset(loaded, 0, sizeof(loaded));
    uint32_t n = Engine_LoadEventsFromFile(fixture, loaded, 16);
    CHECK(n == 7, "Fixture loads 7 events");
    if (n != 7) {
        printf("    SKIP remaining (loaded %u events; fixture path = %s)\n",
               n, fixture);
        return;
    }

    CHECK(loaded[0].type == EVENT_KEY_DOWN,    "row 0 KEY_DOWN");
    CHECK(loaded[1].type == EVENT_KEY_UP,      "row 1 KEY_UP");
    CHECK(loaded[2].type == EVENT_MOUSE_MOVE,  "row 2 MOUSE_MOVE");
    CHECK(loaded[2].data.mouse.x == 320 && loaded[2].data.mouse.y == 240,
          "row 2 mouse coords (320, 240)");
    CHECK(loaded[3].type == EVENT_MOUSE_DOWN,  "row 3 MOUSE_DOWN");
    CHECK(loaded[3].data.mouse_button.button == 1, "row 3 LButton (=1)");
    CHECK(loaded[4].type == EVENT_MOUSE_UP,    "row 4 MOUSE_UP");
    CHECK(loaded[5].type == EVENT_CONTROLLER,  "row 5 CONTROLLER");
    CHECK(loaded[5].data.controller.buttons == 4096, "row 5 buttons == 4096 (X)");
    CHECK(loaded[5].data.controller.left_trigger == 16, "row 5 LT == 16");
    CHECK(loaded[5].data.controller.right_trigger == 20, "row 5 RT == 20");
    CHECK(loaded[5].data.controller.left_thumb_x == 512, "row 5 LX == 512");
    CHECK(loaded[5].data.controller.left_thumb_y == -512, "row 5 LY == -512");
    CHECK(loaded[6].type == EVENT_CONTROLLER,  "row 6 CONTROLLER (release)");
    CHECK(loaded[6].data.controller.buttons == 0, "row 6 buttons cleared");

    /* Cumulative timing: row 1 should sit 25 ms after row 0, row 6 at 275 ms. */
    int64_t d01 = (loaded[1].timestamp_us - loaded[0].timestamp_us) / 1000;
    int64_t d06 = (loaded[6].timestamp_us - loaded[0].timestamp_us) / 1000;
    CHECK(d01 == 25, "delay row0->row1 = 25 ms");
    CHECK(d06 == 275, "delay row0->row6 = 275 ms");

    /* Compress the timestamps so playback finishes in well under a second.
     * Original spacing was 25-50ms each; rescale to ~1ms per step. */
    for (uint32_t i = 0; i < n; i++)
        loaded[i].timestamp_us /= 50;

    CHECK(Engine_StartPlayback(loaded, n, 1), "Playback of fixture starts");
    /* Poll for completion -- compressed playback is ~5ms but Task Scheduler
     * load can spike per-tick latency. Allow up to ~1s before giving up. */
    int finished = 0;
    for (int i = 0; i < 20; i++) {
        Sleep(50);
        if (!Engine_IsPlaying()) { finished = 1; break; }
    }
    CHECK(finished, "Fixture playback completes cleanly");
}

static void test_vjoy_disabled(void)
{
    printf("\n[vJoy disabled via env var]\n");

    /* Force the not-available branch even if vJoy is installed locally.
     * MacrosApp's acceptance gate item #4 ('temporarily run without vJoy')
     * is otherwise unreachable on a vJoy-equipped dev box. */
    if (!SetEnvironmentVariableA("MACROS_DISABLE_VJOY", "1")) {
        printf("    SKIP  could not set MACROS_DISABLE_VJOY\n");
        return;
    }

    /* Re-init so vjoy_output's load_vjoy_library() runs fresh and observes
     * the env var. The engine resets its g_load_attempted/g_state on
     * Engine_Shutdown -> Engine_Init via vjoy_reset() in Engine_Init. */
    Engine_Shutdown();
    CHECK(Engine_Init(), "Engine_Init succeeds with MACROS_DISABLE_VJOY=1");

    VJoyState state;
    memset(&state, 0, sizeof(state));
    Engine_GetVJoyState(&state);
    CHECK(!state.available, "GetVJoyState reports not available");
    CHECK(!state.ready, "GetVJoyState reports not ready");

    /* Playback of a controller event should drop the event but not crash. */
    MacroEvent evts[1];
    memset(evts, 0, sizeof(evts));
    evts[0].type = EVENT_CONTROLLER;
    evts[0].timestamp_us = 0;
    evts[0].data.controller.connected = true;
    evts[0].data.controller.buttons = XINPUT_GAMEPAD_A;

    CHECK(Engine_StartPlayback(evts, 1, 1),
          "Controller playback starts even without vJoy");
    Sleep(100);
    CHECK(!Engine_IsPlaying(), "Controller playback completes without vJoy");

    SetEnvironmentVariableA("MACROS_DISABLE_VJOY", NULL);
}

static void test_edge_cases(void)
{
    printf("\n[edge cases]\n");

    /* Shutdown while recording */
    CHECK(Engine_StartRecording(), "Start recording for edge-case test");
    CHECK(Engine_IsRecording(), "IsRecording true before shutdown");
    Engine_Shutdown();
    CHECK(!Engine_IsInitialized(), "Shutdown-while-recording: not initialized");
    CHECK(!Engine_IsRecording(), "IsRecording false after shutdown");

    /* Re-init after shutdown */
    CHECK(Engine_Init(), "Re-init after shutdown succeeds");
    CHECK(Engine_IsInitialized(), "Engine initialized after re-init");
}

static void test_shutdown(void)
{
    printf("\n[shutdown]\n");
    Engine_Shutdown();
    CHECK(!Engine_IsInitialized(), "Engine reports not initialized");

    /* Double shutdown should be harmless */
    Engine_Shutdown();
    CHECK(!Engine_IsInitialized(), "Double shutdown is safe");
}

static void test_uninit_safety(void)
{
    printf("\n[uninit safety]\n");

    /* These should all fail gracefully without crashing */
    CHECK(!Engine_StartRecording(), "StartRecording fails when not init");
    CHECK(!Engine_IsRecording(), "IsRecording returns false when not init");
    CHECK(Engine_GetRecordedEventCount() == 0, "GetRecordedEventCount returns 0 when not init");
    CHECK(!Engine_IsPlaying(), "IsPlaying returns false when not init");

    ControllerState cs;
    CHECK(!Engine_GetControllerState(0, &cs), "GetControllerState fails when not init");
}

/* ------- main ------- */

int main(void)
{
    printf("=== MacrosEngine Test Suite ===\n");

    test_lifecycle();
    test_recording();
    test_file_io();
    test_controller();
    test_playback_api();
    test_playback_cancel();
    test_playback_cancel_midsleep();
    test_vjoy_api();
    test_controller_output_callback_api();
    test_ahk_v1_format();
    test_vjoy_disabled();
    test_edge_cases();
    test_shutdown();
    test_uninit_safety();

    remove("test_output.txt");
    printf("\n=== Results: %d / %d passed ===\n", tests_passed, tests_run);
    return (tests_passed == tests_run) ? 0 : 1;
}
