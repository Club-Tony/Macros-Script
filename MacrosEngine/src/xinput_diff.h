/*
 * xinput_diff.h -- Pure helpers for controller-state quantization and diffing.
 *
 * These are the building blocks used by xinput_poller.c's recording path.
 * They are intentionally side-effect free so they can be unit-tested in
 * isolation by test/test_xinput_diff.c.
 */
#ifndef XINPUT_DIFF_H
#define XINPUT_DIFF_H

#include "../include/macros_engine.h"
#include <string.h>

#define RECORDER_THUMB_DEADZONE   2500
#define RECORDER_TRIGGER_DEADZONE 5
#define RECORDER_THUMB_STEP       256
#define RECORDER_TRIGGER_STEP     4

static inline int16_t quantize_thumb(int16_t value)
{
    int v = value;
    if (v > -RECORDER_THUMB_DEADZONE && v < RECORDER_THUMB_DEADZONE)
        v = 0;
    int q = (v >= 0)
        ? ((v + RECORDER_THUMB_STEP / 2) / RECORDER_THUMB_STEP) * RECORDER_THUMB_STEP
        : -(((-v) + RECORDER_THUMB_STEP / 2) / RECORDER_THUMB_STEP) * RECORDER_THUMB_STEP;
    if (q > 32767) q = 32767;
    if (q < -32768) q = -32768;
    return (int16_t)q;
}

static inline uint8_t quantize_trigger(uint8_t value)
{
    if (value < RECORDER_TRIGGER_DEADZONE)
        return 0;
    unsigned int q = ((unsigned int)value + RECORDER_TRIGGER_STEP / 2)
        / RECORDER_TRIGGER_STEP * RECORDER_TRIGGER_STEP;
    if (q > 255)
        q = 255;
    return (uint8_t)q;
}

static inline ControllerState normalize_for_recording(const ControllerState *state)
{
    ControllerState out = *state;
    out.connected = true;
    out.left_trigger = quantize_trigger(state->left_trigger);
    out.right_trigger = quantize_trigger(state->right_trigger);
    out.left_thumb_x = quantize_thumb(state->left_thumb_x);
    out.left_thumb_y = quantize_thumb(state->left_thumb_y);
    out.right_thumb_x = quantize_thumb(state->right_thumb_x);
    out.right_thumb_y = quantize_thumb(state->right_thumb_y);
    return out;
}

static inline bool states_equal(const ControllerState *a, const ControllerState *b)
{
    return a->buttons == b->buttons &&
           a->left_trigger == b->left_trigger &&
           a->right_trigger == b->right_trigger &&
           a->left_thumb_x == b->left_thumb_x &&
           a->left_thumb_y == b->left_thumb_y &&
           a->right_thumb_x == b->right_thumb_x &&
           a->right_thumb_y == b->right_thumb_y;
}

static inline bool state_is_neutral(const ControllerState *state)
{
    return state->buttons == 0 &&
           state->left_trigger == 0 &&
           state->right_trigger == 0 &&
           state->left_thumb_x == 0 &&
           state->left_thumb_y == 0 &&
           state->right_thumb_x == 0 &&
           state->right_thumb_y == 0;
}

#endif /* XINPUT_DIFF_H */
