/*
 * test_xinput_diff.c -- Unit tests for the pure helpers in xinput_diff.h.
 *
 * These exercise the quantize / normalize / equality / neutral predicates
 * that decide whether a freshly-polled XINPUT_STATE results in a new
 * EVENT_CONTROLLER row being recorded. They run without a real controller
 * and without invoking the engine's polling thread.
 *
 * Build:  cmake --build build
 * Run:    build\test_xinput_diff.exe
 */

#include "../src/xinput_diff.h"
#include <stdio.h>
#include <string.h>

static int tests_run    = 0;
static int tests_passed = 0;

#define CHECK(cond, msg) do {                                   \
    tests_run++;                                                \
    if (cond) { tests_passed++; printf("  PASS  %s\n", msg); } \
    else      { printf("  FAIL  %s\n", msg); }                 \
} while (0)

#define XINPUT_GAMEPAD_A 0x1000
#define XINPUT_GAMEPAD_B 0x2000

static ControllerState make_state(uint16_t buttons,
                                  uint8_t lt, uint8_t rt,
                                  int16_t lx, int16_t ly,
                                  int16_t rx, int16_t ry)
{
    ControllerState s;
    memset(&s, 0, sizeof(s));
    s.connected = true;
    s.buttons = buttons;
    s.left_trigger = lt;
    s.right_trigger = rt;
    s.left_thumb_x = lx;
    s.left_thumb_y = ly;
    s.right_thumb_x = rx;
    s.right_thumb_y = ry;
    return s;
}

/* ------- quantize_thumb ------- */

static void test_quantize_thumb(void)
{
    printf("\n[quantize_thumb]\n");

    /* Below the recorder deadzone (2500) zeros out. */
    CHECK(quantize_thumb(0) == 0,        "thumb 0 -> 0");
    CHECK(quantize_thumb(2499) == 0,     "thumb 2499 (just below DZ) -> 0");
    CHECK(quantize_thumb(-2499) == 0,    "thumb -2499 (just below DZ) -> 0");

    /* At/above the deadzone, quantizes to the nearest 256-step. */
    int16_t q = quantize_thumb(2500);
    CHECK(q != 0,                         "thumb 2500 (at DZ) crosses threshold");
    CHECK((q % RECORDER_THUMB_STEP) == 0, "thumb 2500 -> multiple of 256");

    int16_t qn = quantize_thumb(-2500);
    CHECK(qn != 0,                         "thumb -2500 crosses threshold");
    CHECK((qn % RECORDER_THUMB_STEP) == 0, "thumb -2500 -> multiple of 256");

    /* Symmetric: positive and negative round consistently. */
    CHECK(quantize_thumb(5000)  == -quantize_thumb(-5000),  "thumb 5000 sym");
    CHECK(quantize_thumb(16384) == -quantize_thumb(-16384), "thumb 16384 sym");

    /* Saturation at int16 limits. */
    CHECK(quantize_thumb(32767) == 32768 - RECORDER_THUMB_STEP || quantize_thumb(32767) == 32767,
          "thumb 32767 saturates near max");
    CHECK(quantize_thumb(-32768) <= -32768 + RECORDER_THUMB_STEP,
          "thumb -32768 saturates near min");
}

/* ------- quantize_trigger ------- */

static void test_quantize_trigger(void)
{
    printf("\n[quantize_trigger]\n");

    CHECK(quantize_trigger(0) == 0,   "trigger 0 -> 0");
    CHECK(quantize_trigger(4) == 0,   "trigger 4 (just below DZ=5) -> 0");
    CHECK(quantize_trigger(5) != 0,   "trigger 5 (at DZ) crosses threshold");

    /* Quantizes to multiples of 4. */
    uint8_t q = quantize_trigger(20);
    CHECK((q % RECORDER_TRIGGER_STEP) == 0, "trigger 20 -> multiple of 4");
    CHECK(q == 20,                          "trigger 20 -> 20");

    CHECK(quantize_trigger(255) == 252 || quantize_trigger(255) == 255,
          "trigger 255 saturates near max");
}

/* ------- normalize_for_recording ------- */

static void test_normalize_for_recording(void)
{
    printf("\n[normalize_for_recording]\n");

    ControllerState s = make_state(XINPUT_GAMEPAD_A, 16, 0, 5000, -5000, 0, 0);
    s.connected = false;  /* should be forced to true */

    ControllerState n = normalize_for_recording(&s);
    CHECK(n.connected == true,            "connected forced to true");
    CHECK(n.buttons == XINPUT_GAMEPAD_A,  "buttons preserved");
    CHECK(n.left_trigger == 16,           "trigger 16 unchanged (multiple of 4)");
    CHECK(n.right_trigger == 0,           "trigger 0 stays 0");
    CHECK(n.left_thumb_x != 0,            "thumb 5000 quantized non-zero");
    CHECK(n.left_thumb_y != 0,            "thumb -5000 quantized non-zero");
    CHECK(n.right_thumb_x == 0,           "thumb 0 stays 0");
}

/* ------- states_equal ------- */

static void test_states_equal(void)
{
    printf("\n[states_equal]\n");

    ControllerState a = make_state(XINPUT_GAMEPAD_A, 16, 0, 256, 0, 0, 0);
    ControllerState b = make_state(XINPUT_GAMEPAD_A, 16, 0, 256, 0, 0, 0);

    CHECK(states_equal(&a, &b), "identical states equal");
    CHECK(states_equal(&b, &a), "states_equal symmetric");

    ControllerState diff_button = a; diff_button.buttons = XINPUT_GAMEPAD_B;
    CHECK(!states_equal(&a, &diff_button), "different buttons unequal");

    ControllerState diff_lt = a; diff_lt.left_trigger = 20;
    CHECK(!states_equal(&a, &diff_lt), "different LT unequal");

    ControllerState diff_lx = a; diff_lx.left_thumb_x = 512;
    CHECK(!states_equal(&a, &diff_lx), "different LX unequal");

    /* connected flag is not part of the equality check (recorder forces it
     * to true), so two states differing only in connected should still
     * compare equal. */
    ControllerState other = a; other.connected = false;
    CHECK(states_equal(&a, &other), "connected ignored in equality");
}

/* ------- state_is_neutral ------- */

static void test_state_is_neutral(void)
{
    printf("\n[state_is_neutral]\n");

    ControllerState neutral = make_state(0, 0, 0, 0, 0, 0, 0);
    CHECK(state_is_neutral(&neutral), "all-zero state is neutral");

    /* Each non-zero field individually breaks neutrality. */
    ControllerState bn = neutral; bn.buttons = XINPUT_GAMEPAD_A;
    CHECK(!state_is_neutral(&bn), "buttons set -> not neutral");

    ControllerState tn = neutral; tn.left_trigger = 4;
    CHECK(!state_is_neutral(&tn), "LT set -> not neutral");

    ControllerState sn = neutral; sn.left_thumb_x = 256;
    CHECK(!state_is_neutral(&sn), "LX set -> not neutral");
}

/* ------- combined diff scenarios ------- */

static void test_combined_diff_scenarios(void)
{
    printf("\n[combined diff scenarios]\n");

    /* Simultaneous button + trigger + thumb change in one frame should
     * produce a normalized state that differs from the previous frame. */
    ControllerState prev = normalize_for_recording(
        &(ControllerState){.connected = true});
    ControllerState raw  = make_state(XINPUT_GAMEPAD_A, 30, 0, 8000, 0, 0, 0);
    ControllerState curr = normalize_for_recording(&raw);
    CHECK(!states_equal(&prev, &curr), "multi-field change registers as diff");

    /* Sub-deadzone thumb wiggle should NOT change the normalized state. */
    ControllerState wiggle1 = normalize_for_recording(
        &(ControllerState){.left_thumb_x = 1000});
    ControllerState wiggle2 = normalize_for_recording(
        &(ControllerState){.left_thumb_x = 2000});
    CHECK(states_equal(&wiggle1, &wiggle2), "sub-DZ wiggle filtered out");

    /* Same dpad transition exercise: dpad bits live in buttons. */
    ControllerState dpad_up    = make_state(0x0001, 0, 0, 0, 0, 0, 0);
    ControllerState dpad_right = make_state(0x0008, 0, 0, 0, 0, 0, 0);
    CHECK(!states_equal(&dpad_up, &dpad_right),
          "dpad up vs dpad right unequal");
}

int main(void)
{
    printf("=== xinput_diff Test Suite ===\n");

    test_quantize_thumb();
    test_quantize_trigger();
    test_normalize_for_recording();
    test_states_equal();
    test_state_is_neutral();
    test_combined_diff_scenarios();

    printf("\n=== Results: %d / %d passed ===\n", tests_passed, tests_run);
    return (tests_passed == tests_run) ? 0 : 1;
}
