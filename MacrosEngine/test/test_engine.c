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

/* ------- helpers ------- */

static int  tests_run    = 0;
static int  tests_passed = 0;

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

    Engine_StopRecording();
    CHECK(!Engine_IsRecording(), "IsRecording false after stop");

    uint32_t n = Engine_GetRecordedEventCount();
    CHECK(n == 6, "Recorded event count == 6");
    printf("    recorded %u events\n", n);

    /* Retrieve events */
    MacroEvent buf[16];
    uint32_t got = 0;
    CHECK(Engine_GetRecordedEvents(buf, 16, &got), "GetRecordedEvents ok");
    CHECK(got == 6, "Got 6 events back");

    /* Verify first event */
    CHECK(buf[0].type == EVENT_KEY_DOWN, "First event is KEY_DOWN");
    CHECK(buf[0].data.key.vk_code == 0x41, "First event VK == 0x41 (A)");
    CHECK(buf[0].timestamp_us >= 0, "Timestamp >= 0");
}

static void test_file_io(void)
{
    printf("\n[file I/O]\n");
    remove("test_output.txt");

    /* Create a small event set */
    MacroEvent events[4];
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

    const char *path = "test_output.txt";

    CHECK(Engine_SaveEventsToFile(path, events, 4), "SaveEventsToFile ok");

    /* Load them back */
    MacroEvent loaded[16];
    uint32_t n = Engine_LoadEventsFromFile(path, loaded, 16);
    CHECK(n == 4, "LoadEventsFromFile returns 4");

    CHECK(loaded[0].type == EVENT_MOUSE_MOVE, "Loaded[0] is MOUSE_MOVE");
    CHECK(loaded[0].data.mouse.x == 100, "Loaded[0] x == 100");
    CHECK(loaded[0].data.mouse.y == 200, "Loaded[0] y == 200");

    CHECK(loaded[1].type == EVENT_KEY_DOWN, "Loaded[1] is KEY_DOWN");
    CHECK(loaded[3].type == EVENT_MOUSE_DOWN, "Loaded[3] is MOUSE_DOWN");
    CHECK(loaded[3].data.mouse_button.button == 1, "Loaded[3] button == 1");

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
    test_edge_cases();
    test_shutdown();
    test_uninit_safety();

    remove("test_output.txt");
    printf("\n=== Results: %d / %d passed ===\n", tests_passed, tests_run);
    return (tests_passed == tests_run) ? 0 : 1;
}
