/*
 * timing.c -- QueryPerformanceCounter wrapper utilities
 *
 * Provides microsecond-resolution timing and a hybrid busy-wait sleep
 * that yields when the remaining interval exceeds 1 ms, then spin-waits
 * for the final stretch to hit sub-millisecond accuracy.
 */

#include "timing.h"
#include <mmsystem.h>

static LARGE_INTEGER g_freq;
static bool          g_timing_initialized = false;

/* ---------------------------------------------------------------- */
void timing_init(void)
{
    QueryPerformanceFrequency(&g_freq);
    timeBeginPeriod(1);
    g_timing_initialized = true;
}

void timing_cleanup(void)
{
    if (g_timing_initialized) {
        timeEndPeriod(1);
        g_timing_initialized = false;
    }
}

/* ---------------------------------------------------------------- */
bool timing_is_initialized(void)
{
    return g_timing_initialized;
}

/* ---------------------------------------------------------------- */
int64_t timing_get_us(void)
{
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    return (int64_t)((now.QuadPart * 1000000LL) / g_freq.QuadPart);
}

/* ---------------------------------------------------------------- */
void timing_sleep_us(int64_t microseconds)
{
    if (microseconds <= 0)
        return;

    int64_t target = timing_get_us() + microseconds;

    /* Coarse phase: yield CPU while > 1.5 ms remain */
    while (target - timing_get_us() > 1500) {
        Sleep(1);
    }

    /* Fine phase: busy-wait with Sleep(0) yields */
    while (timing_get_us() < target) {
        Sleep(0);           /* relinquish remainder of time slice */
    }
}

/* ---------------------------------------------------------------- */
double timing_get_freq(void)
{
    return (double)g_freq.QuadPart;
}
