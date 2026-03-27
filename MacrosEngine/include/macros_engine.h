#ifndef MACROS_ENGINE_H
#define MACROS_ENGINE_H

#ifdef _WIN32
  #ifdef MACROS_ENGINE_EXPORTS
    #define ENGINE_API __declspec(dllexport)
  #else
    #define ENGINE_API __declspec(dllimport)
  #endif
#else
  #define ENGINE_API
#endif

#include <stdint.h>
#include <stdbool.h>

/* ----------------------------------------------------------------
 * Controller state (mirrors XINPUT_GAMEPAD layout)
 * ---------------------------------------------------------------- */
typedef struct {
    bool     connected;
    uint16_t buttons;         /* XINPUT_GAMEPAD button flags          */
    int16_t  left_thumb_x;    /* -32768 .. 32767                     */
    int16_t  left_thumb_y;
    int16_t  right_thumb_x;
    int16_t  right_thumb_y;
    uint8_t  left_trigger;    /* 0 .. 255                            */
    uint8_t  right_trigger;
} ControllerState;

/* ----------------------------------------------------------------
 * Event types
 * ---------------------------------------------------------------- */
typedef enum {
    EVENT_KEY_DOWN       = 1,
    EVENT_KEY_UP         = 2,
    EVENT_MOUSE_MOVE     = 3,
    EVENT_MOUSE_DOWN     = 4,
    EVENT_MOUSE_UP       = 5,
    EVENT_MOUSE_WHEEL    = 6,
    EVENT_CONTROLLER     = 7,
} EventType;

/* ----------------------------------------------------------------
 * Recorded event
 * ---------------------------------------------------------------- */
typedef struct {
    EventType type;
    int64_t   timestamp_us;   /* microseconds from recording start   */
    union {
        struct { uint16_t vk_code; uint16_t scan_code; char key_name[16]; } key;
        struct { int32_t x; int32_t y; int32_t delta_x; int32_t delta_y; } mouse;
        struct { uint16_t button; }                                        mouse_button;
        struct { int32_t delta; }                                          wheel;
        ControllerState controller;
    } data;
} MacroEvent;

/* ----------------------------------------------------------------
 * Engine lifecycle
 * ---------------------------------------------------------------- */
ENGINE_API bool        Engine_Init(void);
ENGINE_API void        Engine_Shutdown(void);
ENGINE_API bool        Engine_IsInitialized(void);

/* ----------------------------------------------------------------
 * Controller polling
 * ---------------------------------------------------------------- */
ENGINE_API bool        Engine_StartPolling(uint32_t interval_ms);
ENGINE_API void        Engine_StopPolling(void);
ENGINE_API bool        Engine_GetControllerState(uint32_t player_index,
                                                  ControllerState *state);
ENGINE_API void        Engine_SetDeadzone(uint32_t player_index,
                                           int16_t  thumb_deadzone,
                                           uint8_t  trigger_deadzone);

/* ----------------------------------------------------------------
 * Recording
 * ---------------------------------------------------------------- */
ENGINE_API bool        Engine_StartRecording(void);
ENGINE_API void        Engine_StopRecording(void);
ENGINE_API bool        Engine_IsRecording(void);
ENGINE_API uint32_t    Engine_GetRecordedEventCount(void);
ENGINE_API bool        Engine_GetRecordedEvents(MacroEvent *buffer,
                                                 uint32_t   buffer_size,
                                                 uint32_t  *out_count);

/* Manual event injection (for AHK / C# UI to feed keyboard/mouse) */
ENGINE_API bool        Engine_RecordKeyEvent(bool     down,
                                              uint16_t vk_code,
                                              uint16_t scan_code);
ENGINE_API bool        Engine_RecordMouseMove(int32_t x, int32_t y);
ENGINE_API bool        Engine_RecordMouseButton(bool     down,
                                                 uint16_t button);
ENGINE_API bool        Engine_RecordMouseWheel(int32_t delta);

/* ----------------------------------------------------------------
 * Playback
 * ---------------------------------------------------------------- */
ENGINE_API bool        Engine_StartPlayback(const MacroEvent *events,
                                             uint32_t count,
                                             uint32_t loop_count);
ENGINE_API void        Engine_StopPlayback(void);
ENGINE_API void        Engine_PausePlayback(void);
ENGINE_API void        Engine_ResumePlayback(void);
ENGINE_API bool        Engine_IsPlaying(void);
ENGINE_API bool        Engine_IsPaused(void);

/* ----------------------------------------------------------------
 * Event file I/O (backward-compatible AHK pipe-delimited format)
 * ---------------------------------------------------------------- */
ENGINE_API uint32_t    Engine_LoadEventsFromFile(const char  *path,
                                                  MacroEvent  *buffer,
                                                  uint32_t     buffer_size);
ENGINE_API bool        Engine_SaveEventsToFile(const char       *path,
                                                const MacroEvent *events,
                                                uint32_t          count);

/* ----------------------------------------------------------------
 * Version
 * ---------------------------------------------------------------- */
ENGINE_API const char* Engine_GetVersion(void);

#endif /* MACROS_ENGINE_H */
