/*
 * timing.h -- Internal timing utilities (not part of the public API)
 */
#ifndef TIMING_H
#define TIMING_H

#include <windows.h>
#include <stdint.h>
#include <stdbool.h>

void    timing_init(void);
void    timing_cleanup(void);
bool    timing_is_initialized(void);
int64_t timing_get_us(void);         /* microseconds since arbitrary epoch */
void    timing_sleep_us(int64_t us); /* hybrid yield + busy-wait sleep     */
double  timing_get_freq(void);       /* raw QPC frequency (Hz)             */

#endif /* TIMING_H */
