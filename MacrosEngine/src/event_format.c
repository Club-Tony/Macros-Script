/*
 * event_format.c -- Read / write the AHK pipe-delimited event format
 *
 * File format (one event per line):
 *   key|code|Down/Up|delay_ms
 *   mousebtn|button|Down/Up|delay_ms
 *   M|x|y|delay_ms
 *   C|buttons|lt|rt|lx|ly|rx|ry|delay_ms
 *
 * On load, delay values are converted to cumulative microsecond
 * timestamps (summing each delay).  On save, timestamps are
 * converted back to inter-event delays in milliseconds.
 *
 * Key codes:  The AHK format stores key *names* (e.g. "a", "Space",
 * "LShift", "vkBC").  When reading we store a hash of the name string
 * in vk_code as a round-trip identifier; the actual VK lookup would
 * happen on the AHK side.  For "vkXX" names we parse the hex value
 * directly.
 *
 * Mouse button names:  "LButton"=1, "RButton"=2, "MButton"=3,
 *   "XButton1"=4, "XButton2"=5, "WheelUp"=120, "WheelDown"=-120,
 *   "WheelLeft"=121, "WheelRight"=122
 */

#include "../include/macros_engine.h"
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
/* MinGW's PRId64 maps to "I64d" which triggers -Wpedantic.
 * Delays in ms fit easily in a long, so we cast to long for printf. */

/* ================================================================
 * Helpers
 * ================================================================ */

/* Simple hash for key-name round-tripping */
static uint16_t hash_keyname(const char *s)
{
    uint32_t h = 5381;
    while (*s)
        h = ((h << 5) + h) + (uint8_t)*s++;
    return (uint16_t)(h & 0xFFFF);
}

/* Parse "vkXX" hex notation.  Returns parsed value or hash fallback. */
static uint16_t parse_vk(const char *name)
{
    if ((name[0] == 'v' || name[0] == 'V') &&
        (name[1] == 'k' || name[1] == 'K'))
    {
        unsigned int val = 0;
        if (sscanf(name + 2, "%x", &val) == 1)
            return (uint16_t)val;
    }
    return hash_keyname(name);
}

/* Map AHK mouse-button name to numeric id */
static uint16_t parse_mouse_button(const char *name)
{
    if (strcmp(name, "LButton")  == 0) return 1;
    if (strcmp(name, "RButton")  == 0) return 2;
    if (strcmp(name, "MButton")  == 0) return 3;
    if (strcmp(name, "XButton1") == 0) return 4;
    if (strcmp(name, "XButton2") == 0) return 5;
    return 0;
}

/* Map numeric button id back to AHK name */
static const char* button_to_name(uint16_t btn)
{
    switch (btn) {
    case 1: return "LButton";
    case 2: return "RButton";
    case 3: return "MButton";
    case 4: return "XButton1";
    case 5: return "XButton2";
    default: return "LButton";
    }
}

/* Split a line by '|' into tokens.  Returns token count. */
#define MAX_TOKENS 12
static int split_pipe(char *line, char *tokens[], int max)
{
    int n = 0;
    char *p = line;
    while (n < max) {
        tokens[n++] = p;
        char *sep = strchr(p, '|');
        if (!sep) break;
        *sep = '\0';
        p = sep + 1;
    }
    return n;
}

/* ================================================================
 * Load
 * ================================================================ */

ENGINE_API uint32_t Engine_LoadEventsFromFile(const char  *path,
                                               MacroEvent  *buffer,
                                               uint32_t     buffer_size)
{
    if (!path || !buffer || buffer_size == 0)
        return 0;

    FILE *f = fopen(path, "r");
    if (!f)
        return 0;

    char line[1024];
    uint32_t count = 0;
    int64_t  cumulative_us = 0;   /* running timestamp */

    while (fgets(line, sizeof(line), f) && count < buffer_size) {
        /* Strip trailing whitespace */
        size_t len = strlen(line);

        /* If line was truncated (no newline and not EOF), skip the rest */
        if (len > 0 && line[len - 1] != '\n' && !feof(f)) {
            int ch;
            while ((ch = fgetc(f)) != '\n' && ch != EOF)
                ;
            /* Skip this truncated line entirely */
            continue;
        }

        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r'
                           || line[len - 1] == ' '))
            line[--len] = '\0';
        if (len == 0 || line[0] == ';')
            continue;

        char *tok[MAX_TOKENS];
        int ntok = split_pipe(line, tok, MAX_TOKENS);
        if (ntok < 2)
            continue;

        MacroEvent evt;
        memset(&evt, 0, sizeof(evt));

        if (strcmp(tok[0], "key") == 0 && ntok >= 4) {
            /* key|name|Down/Up|delay_ms */
            bool down = (strcmp(tok[2], "Down") == 0);
            evt.type = down ? EVENT_KEY_DOWN : EVENT_KEY_UP;
            evt.data.key.vk_code   = parse_vk(tok[1]);
            evt.data.key.scan_code = 0;
            strncpy(evt.data.key.key_name, tok[1], sizeof(evt.data.key.key_name) - 1);
            evt.data.key.key_name[sizeof(evt.data.key.key_name) - 1] = '\0';

            int64_t delay_ms = (int64_t)atoll(tok[3]);
            cumulative_us += delay_ms * 1000;
            evt.timestamp_us = cumulative_us;

        } else if (strcmp(tok[0], "mousebtn") == 0 && ntok >= 4) {
            /* mousebtn|button|Down/Up|delay_ms  OR  wheel event */
            const char *btn_name = tok[1];

            /* Wheel events are stored as mousebtn with empty state */
            if (strcmp(btn_name, "WheelUp") == 0) {
                evt.type = EVENT_MOUSE_WHEEL;
                evt.data.wheel.delta = 120;
            } else if (strcmp(btn_name, "WheelDown") == 0) {
                evt.type = EVENT_MOUSE_WHEEL;
                evt.data.wheel.delta = -120;
            } else if (strcmp(btn_name, "WheelLeft") == 0) {
                evt.type = EVENT_MOUSE_WHEEL;
                evt.data.wheel.delta = -1;  /* lateral */
            } else if (strcmp(btn_name, "WheelRight") == 0) {
                evt.type = EVENT_MOUSE_WHEEL;
                evt.data.wheel.delta = 1;   /* lateral */
            } else {
                bool down = (strcmp(tok[2], "Down") == 0);
                evt.type = down ? EVENT_MOUSE_DOWN : EVENT_MOUSE_UP;
                evt.data.mouse_button.button = parse_mouse_button(btn_name);
            }

            int64_t delay_ms = (int64_t)atoll(tok[3]);
            cumulative_us += delay_ms * 1000;
            evt.timestamp_us = cumulative_us;

        } else if (strcmp(tok[0], "M") == 0 && ntok >= 4) {
            /* M|x|y|delay_ms */
            evt.type         = EVENT_MOUSE_MOVE;
            evt.data.mouse.x = (int32_t)atoi(tok[1]);
            evt.data.mouse.y = (int32_t)atoi(tok[2]);

            int64_t delay_ms = (int64_t)atoll(tok[3]);
            cumulative_us += delay_ms * 1000;
            evt.timestamp_us = cumulative_us;

        } else if (strcmp(tok[0], "C") == 0 && ntok >= 9) {
            /* C|buttons|lt|rt|lx|ly|rx|ry|delay_ms */
            evt.type = EVENT_CONTROLLER;
            evt.data.controller.connected     = true;
            evt.data.controller.buttons       = (uint16_t)atoi(tok[1]);
            evt.data.controller.left_trigger  = (uint8_t)atoi(tok[2]);
            evt.data.controller.right_trigger = (uint8_t)atoi(tok[3]);
            evt.data.controller.left_thumb_x  = (int16_t)atoi(tok[4]);
            evt.data.controller.left_thumb_y  = (int16_t)atoi(tok[5]);
            evt.data.controller.right_thumb_x = (int16_t)atoi(tok[6]);
            evt.data.controller.right_thumb_y = (int16_t)atoi(tok[7]);

            int64_t delay_ms = (int64_t)atoll(tok[8]);
            cumulative_us += delay_ms * 1000;
            evt.timestamp_us = cumulative_us;

        } else {
            continue;   /* unknown format -- skip */
        }

        buffer[count++] = evt;
    }

    fclose(f);
    return count;
}

/* ================================================================
 * Save
 * ================================================================ */

/*
 * Key-name round-trip table.  Since we only store a hash in vk_code
 * on load, saving back requires an external name.  For events recorded
 * via the C API (Engine_RecordKeyEvent) the caller provides a VK code;
 * we write it as "vkXX" hex so AHK can parse it.
 *
 * When loading files that were originally saved by AHK and then
 * round-tripped through the C engine, the key names will change to
 * hex notation.  This is acceptable because AHK supports both.
 */

ENGINE_API bool Engine_SaveEventsToFile(const char       *path,
                                         const MacroEvent *events,
                                         uint32_t          count)
{
    if (!path || !events)
        return false;

    FILE *f = fopen(path, "w");
    if (!f)
        return false;

    int64_t prev_us = 0;

    for (uint32_t i = 0; i < count; i++) {
        const MacroEvent *e = &events[i];
        int64_t delay_ms = (e->timestamp_us - prev_us) / 1000;
        if (delay_ms < 0) delay_ms = 0;
        prev_us = e->timestamp_us;

        switch (e->type) {
        case EVENT_KEY_DOWN:
            if (e->data.key.key_name[0] != '\0')
                fprintf(f, "key|%s|Down|%ld\n",
                        e->data.key.key_name, (long)delay_ms);
            else
                fprintf(f, "key|vk%02X|Down|%ld\n",
                        (unsigned)e->data.key.vk_code, (long)delay_ms);
            break;
        case EVENT_KEY_UP:
            if (e->data.key.key_name[0] != '\0')
                fprintf(f, "key|%s|Up|%ld\n",
                        e->data.key.key_name, (long)delay_ms);
            else
                fprintf(f, "key|vk%02X|Up|%ld\n",
                        (unsigned)e->data.key.vk_code, (long)delay_ms);
            break;
        case EVENT_MOUSE_MOVE:
            fprintf(f, "M|%d|%d|%ld\n",
                    e->data.mouse.x, e->data.mouse.y, (long)delay_ms);
            break;
        case EVENT_MOUSE_DOWN:
            fprintf(f, "mousebtn|%s|Down|%ld\n",
                    button_to_name(e->data.mouse_button.button),
                    (long)delay_ms);
            break;
        case EVENT_MOUSE_UP:
            fprintf(f, "mousebtn|%s|Up|%ld\n",
                    button_to_name(e->data.mouse_button.button),
                    (long)delay_ms);
            break;
        case EVENT_MOUSE_WHEEL:
            if (e->data.wheel.delta == 1)
                fprintf(f, "mousebtn|WheelRight||%ld\n", (long)delay_ms);
            else if (e->data.wheel.delta == -1)
                fprintf(f, "mousebtn|WheelLeft||%ld\n", (long)delay_ms);
            else if (e->data.wheel.delta > 0)
                fprintf(f, "mousebtn|WheelUp||%ld\n", (long)delay_ms);
            else if (e->data.wheel.delta < 0)
                fprintf(f, "mousebtn|WheelDown||%ld\n", (long)delay_ms);
            break;
        case EVENT_CONTROLLER:
            fprintf(f, "C|%u|%u|%u|%d|%d|%d|%d|%ld\n",
                    (unsigned)e->data.controller.buttons,
                    (unsigned)e->data.controller.left_trigger,
                    (unsigned)e->data.controller.right_trigger,
                    (int)e->data.controller.left_thumb_x,
                    (int)e->data.controller.left_thumb_y,
                    (int)e->data.controller.right_thumb_x,
                    (int)e->data.controller.right_thumb_y,
                    (long)delay_ms);
            break;
        }
    }

    fclose(f);
    return true;
}
