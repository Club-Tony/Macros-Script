/*
 * vjoy_output.c -- Optional vJoy controller playback
 *
 * Loads vJoyInterface.dll at runtime so MacrosEngine remains usable on
 * systems without vJoy installed.  The controller mapping mirrors the AHK v1
 * implementation: thumb axes map to X/Y/RX/RY, triggers map to Z/RZ with
 * slider fallbacks, D-pad maps to POV, and face/shoulder/menu/thumb buttons
 * map to vJoy buttons 1..10.
 */

#include "../include/macros_engine.h"
#include <windows.h>
#include <stdint.h>
#include <string.h>

extern CRITICAL_SECTION g_engine_cs;

#define VJD_MAXDEV      16
#define VJD_STAT_OWN    0
#define VJD_STAT_FREE   1
#define VJD_STAT_BUSY   2
#define VJD_STAT_MISS   3
#define VJD_STAT_UNKN   4

#define HID_USAGE_X     0x30
#define HID_USAGE_Y     0x31
#define HID_USAGE_Z     0x32
#define HID_USAGE_RX    0x33
#define HID_USAGE_RY    0x34
#define HID_USAGE_RZ    0x35
#define HID_USAGE_SL0   0x36
#define HID_USAGE_SL1   0x37

#define AXIS_BIT_X      0x01
#define AXIS_BIT_Y      0x02
#define AXIS_BIT_Z      0x04
#define AXIS_BIT_RX     0x08
#define AXIS_BIT_RY     0x10
#define AXIS_BIT_RZ     0x20
#define AXIS_BIT_SL0    0x40
#define AXIS_BIT_SL1    0x80

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

typedef BOOL (__cdecl *vjoy_enabled_t)(void);
typedef int  (__cdecl *get_vjd_status_t)(UINT id);
typedef BOOL (__cdecl *acquire_vjd_t)(UINT id);
typedef void (__cdecl *relinquish_vjd_t)(UINT id);
typedef BOOL (__cdecl *reset_vjd_t)(UINT id);
typedef int  (__cdecl *get_vjd_button_number_t)(UINT id);
typedef int  (__cdecl *get_vjd_cont_pov_number_t)(UINT id);
typedef int  (__cdecl *get_vjd_disc_pov_number_t)(UINT id);
typedef BOOL (__cdecl *get_vjd_axis_exist_t)(UINT id, UINT usage);
typedef BOOL (__cdecl *get_vjd_axis_max_t)(UINT id, UINT usage, LONG *max);
typedef BOOL (__cdecl *set_axis_t)(LONG value, UINT id, UINT usage);
typedef BOOL (__cdecl *set_btn_t)(BOOL pressed, UINT id, UCHAR button);
typedef BOOL (__cdecl *set_cont_pov_t)(DWORD value, UINT id, UCHAR pov);
typedef BOOL (__cdecl *set_disc_pov_t)(int value, UINT id, UCHAR pov);

typedef struct {
    HMODULE dll;
    vjoy_enabled_t vJoyEnabled;
    get_vjd_status_t GetVJDStatus;
    acquire_vjd_t AcquireVJD;
    relinquish_vjd_t RelinquishVJD;
    reset_vjd_t ResetVJD;
    get_vjd_button_number_t GetVJDButtonNumber;
    get_vjd_cont_pov_number_t GetVJDContPovNumber;
    get_vjd_disc_pov_number_t GetVJDDiscPovNumber;
    get_vjd_axis_exist_t GetVJDAxisExist;
    get_vjd_axis_max_t GetVJDAxisMax;
    set_axis_t SetAxis;
    set_btn_t SetBtn;
    set_cont_pov_t SetContPov;
    set_disc_pov_t SetDiscPov;
} VJoyApi;

static VJoyApi  g_api;
static VJoyState g_state = { false, false, false, 1, VJD_STAT_UNKN, 0, 0, 0, 0 };
static LONG      g_axis_max[8];
static bool      g_load_attempted = false;

static bool append_dll_name(const char *folder, char *out, DWORD out_size)
{
    if (!folder || !folder[0])
        return false;

    DWORD len = (DWORD)strlen(folder);
    if (len + 19 >= out_size)
        return false;

    strcpy(out, folder);
    if (len > 0 && out[len - 1] != '\\' && out[len - 1] != '/') {
        out[len++] = '\\';
        out[len] = '\0';
    }
    strcat(out, "vJoyInterface.dll");
    return true;
}

static bool query_reg_string(REGSAM view, const char *name, char *out, DWORD out_size)
{
    static const char *key =
        "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\"
        "{8E31F76F-74C3-47F1-9550-E041EEDC5FBB}_is1";

    HKEY hkey = NULL;
    LONG open_result = RegOpenKeyExA(HKEY_LOCAL_MACHINE, key, 0,
                                     KEY_READ | view, &hkey);
    if (open_result != ERROR_SUCCESS)
        return false;

    DWORD type = 0;
    DWORD size = out_size;
    LONG query_result = RegQueryValueExA(hkey, name, NULL, &type,
                                         (LPBYTE)out, &size);
    RegCloseKey(hkey);

    if (query_result != ERROR_SUCCESS ||
        (type != REG_SZ && type != REG_EXPAND_SZ) ||
        size == 0) {
        return false;
    }

    out[out_size - 1] = '\0';
    return true;
}

static HMODULE try_load_path(const char *path)
{
    if (!path || !path[0])
        return NULL;
    return LoadLibraryA(path);
}

static FARPROC require_proc(const char *name)
{
    return g_api.dll ? GetProcAddress(g_api.dll, name) : NULL;
}

static bool load_functions(void)
{
    g_api.vJoyEnabled = (vjoy_enabled_t)require_proc("vJoyEnabled");
    g_api.GetVJDStatus = (get_vjd_status_t)require_proc("GetVJDStatus");
    g_api.AcquireVJD = (acquire_vjd_t)require_proc("AcquireVJD");
    g_api.RelinquishVJD = (relinquish_vjd_t)require_proc("RelinquishVJD");
    g_api.ResetVJD = (reset_vjd_t)require_proc("ResetVJD");
    g_api.GetVJDButtonNumber =
        (get_vjd_button_number_t)require_proc("GetVJDButtonNumber");
    g_api.GetVJDContPovNumber =
        (get_vjd_cont_pov_number_t)require_proc("GetVJDContPovNumber");
    g_api.GetVJDDiscPovNumber =
        (get_vjd_disc_pov_number_t)require_proc("GetVJDDiscPovNumber");
    g_api.GetVJDAxisExist =
        (get_vjd_axis_exist_t)require_proc("GetVJDAxisExist");
    g_api.GetVJDAxisMax = (get_vjd_axis_max_t)require_proc("GetVJDAxisMax");
    g_api.SetAxis = (set_axis_t)require_proc("SetAxis");
    g_api.SetBtn = (set_btn_t)require_proc("SetBtn");
    g_api.SetContPov = (set_cont_pov_t)require_proc("SetContPov");
    g_api.SetDiscPov = (set_disc_pov_t)require_proc("SetDiscPov");

    return g_api.vJoyEnabled && g_api.GetVJDStatus && g_api.AcquireVJD &&
           g_api.RelinquishVJD && g_api.ResetVJD &&
           g_api.GetVJDButtonNumber && g_api.GetVJDContPovNumber &&
           g_api.GetVJDDiscPovNumber && g_api.GetVJDAxisExist &&
           g_api.GetVJDAxisMax && g_api.SetAxis && g_api.SetBtn &&
           g_api.SetContPov && g_api.SetDiscPov;
}

static bool load_vjoy_library(void)
{
    if (g_api.dll)
        return true;
    if (g_load_attempted)
        return false;

    g_load_attempted = true;

    /* Test seam: MACROS_DISABLE_VJOY forces the not-available branch so the
     * vJoy-missing graceful-degrade path can be exercised on a vJoy-equipped
     * dev box. See test_vjoy_disabled() in test_engine.c. */
    if (GetEnvironmentVariableA("MACROS_DISABLE_VJOY", NULL, 0) > 0) {
        g_state.available = false;
        return false;
    }

    char value[MAX_PATH];
    char path[MAX_PATH];

#ifdef _WIN64
    const char *dll_value = "DllX64Location";
#else
    const char *dll_value = "DllX86Location";
#endif

    REGSAM views[] = { KEY_WOW64_64KEY, KEY_WOW64_32KEY, 0 };
    for (int i = 0; i < 3 && !g_api.dll; i++) {
        if (query_reg_string(views[i], dll_value, value, sizeof(value)) &&
            append_dll_name(value, path, sizeof(path))) {
            g_api.dll = try_load_path(path);
        }
    }

    const char *env_names[] = { "ProgramW6432", "ProgramFiles", "ProgramFiles(x86)" };
    const char *suffixes[] = {
        "\\vJoy\\x64\\vJoyInterface.dll",
        "\\vJoy\\x86\\vJoyInterface.dll",
        "\\vJoy\\vJoyInterface.dll"
    };

    for (int e = 0; e < 3 && !g_api.dll; e++) {
        DWORD len = GetEnvironmentVariableA(env_names[e], value, sizeof(value));
        if (len == 0 || len >= sizeof(value))
            continue;

        for (int s = 0; s < 3 && !g_api.dll; s++) {
            if (strlen(value) + strlen(suffixes[s]) >= sizeof(path))
                continue;
            strcpy(path, value);
            strcat(path, suffixes[s]);
            g_api.dll = try_load_path(path);
        }
    }

    if (!g_api.dll)
        g_api.dll = try_load_path("vJoyInterface.dll");

    if (!g_api.dll) {
        g_state.available = false;
        return false;
    }

    g_state.available = true;
    if (!load_functions()) {
        FreeLibrary(g_api.dll);
        memset(&g_api, 0, sizeof(g_api));
        g_state.available = false;
        return false;
    }

    return true;
}

static void query_axis(UINT usage, uint32_t bit, int index)
{
    if (g_api.GetVJDAxisExist((UINT)g_state.device_id, usage)) {
        LONG max = 0;
        g_state.axis_exists_mask |= bit;
        if (g_api.GetVJDAxisMax((UINT)g_state.device_id, usage, &max))
            g_axis_max[index] = max;
    }
}

static bool ensure_ready_locked(void)
{
    if (g_state.ready)
        return true;

    g_state.ready = false;
    g_state.enabled = false;
    g_state.button_count = 0;
    g_state.cont_pov_count = 0;
    g_state.disc_pov_count = 0;
    g_state.axis_exists_mask = 0;
    memset(g_axis_max, 0, sizeof(g_axis_max));

    if (!load_vjoy_library())
        return false;

    g_state.enabled = g_api.vJoyEnabled() ? true : false;
    if (!g_state.enabled)
        return false;

    g_state.status = (uint32_t)g_api.GetVJDStatus((UINT)g_state.device_id);
    if (g_state.status == VJD_STAT_FREE) {
        if (!g_api.AcquireVJD((UINT)g_state.device_id))
            return false;
        g_state.status = VJD_STAT_OWN;
    } else if (g_state.status != VJD_STAT_OWN) {
        return false;
    }

    g_state.button_count =
        (uint32_t)g_api.GetVJDButtonNumber((UINT)g_state.device_id);
    g_state.cont_pov_count =
        (uint32_t)g_api.GetVJDContPovNumber((UINT)g_state.device_id);
    g_state.disc_pov_count =
        (uint32_t)g_api.GetVJDDiscPovNumber((UINT)g_state.device_id);

    query_axis(HID_USAGE_X, AXIS_BIT_X, 0);
    query_axis(HID_USAGE_Y, AXIS_BIT_Y, 1);
    query_axis(HID_USAGE_Z, AXIS_BIT_Z, 2);
    query_axis(HID_USAGE_RX, AXIS_BIT_RX, 3);
    query_axis(HID_USAGE_RY, AXIS_BIT_RY, 4);
    query_axis(HID_USAGE_RZ, AXIS_BIT_RZ, 5);
    query_axis(HID_USAGE_SL0, AXIS_BIT_SL0, 6);
    query_axis(HID_USAGE_SL1, AXIS_BIT_SL1, 7);

    g_api.ResetVJD((UINT)g_state.device_id);
    g_state.ready = true;
    return true;
}

static LONG map_thumb_axis(int16_t value, LONG axis_max)
{
    if (axis_max <= 0)
        return 0;
    int64_t shifted = (int64_t)value + 32768;
    return (LONG)((shifted * axis_max + 32767) / 65535);
}

static LONG map_trigger_axis(uint8_t value, LONG axis_max)
{
    if (axis_max <= 0)
        return 0;
    return (LONG)(((int64_t)value * axis_max + 127) / 255);
}

static void set_axis_if_present(uint32_t bit, UINT usage, LONG value)
{
    if ((g_state.axis_exists_mask & bit) != 0)
        g_api.SetAxis(value, (UINT)g_state.device_id, usage);
}

static void set_button_if_present(UCHAR button, bool pressed)
{
    if (button <= g_state.button_count)
        g_api.SetBtn(pressed ? TRUE : FALSE, (UINT)g_state.device_id, button);
}

static void apply_pov(uint16_t buttons)
{
    bool up = (buttons & XINPUT_GAMEPAD_DPAD_UP) != 0;
    bool down = (buttons & XINPUT_GAMEPAD_DPAD_DOWN) != 0;
    bool left = (buttons & XINPUT_GAMEPAD_DPAD_LEFT) != 0;
    bool right = (buttons & XINPUT_GAMEPAD_DPAD_RIGHT) != 0;

    if (g_state.cont_pov_count > 0) {
        DWORD angle = (DWORD)-1;
        if (up && right) angle = 4500;
        else if (right && down) angle = 13500;
        else if (down && left) angle = 22500;
        else if (left && up) angle = 31500;
        else if (up) angle = 0;
        else if (right) angle = 9000;
        else if (down) angle = 18000;
        else if (left) angle = 27000;
        g_api.SetContPov(angle, (UINT)g_state.device_id, 1);
    } else if (g_state.disc_pov_count > 0) {
        int dir = -1;
        if (up) dir = 0;
        else if (right) dir = 1;
        else if (down) dir = 2;
        else if (left) dir = 3;
        g_api.SetDiscPov(dir, (UINT)g_state.device_id, 1);
    }
}

bool vjoy_dispatch_controller(const ControllerState *state)
{
    if (!state || !Engine_IsInitialized())
        return false;

    EnterCriticalSection(&g_engine_cs);
    bool ready = ensure_ready_locked();
    if (!ready) {
        LeaveCriticalSection(&g_engine_cs);
        return false;
    }

    set_axis_if_present(AXIS_BIT_X, HID_USAGE_X,
                        map_thumb_axis(state->left_thumb_x, g_axis_max[0]));
    set_axis_if_present(AXIS_BIT_Y, HID_USAGE_Y,
                        map_thumb_axis(state->left_thumb_y, g_axis_max[1]));
    set_axis_if_present(AXIS_BIT_RX, HID_USAGE_RX,
                        map_thumb_axis(state->right_thumb_x, g_axis_max[3]));
    set_axis_if_present(AXIS_BIT_RY, HID_USAGE_RY,
                        map_thumb_axis(state->right_thumb_y, g_axis_max[4]));

    if ((g_state.axis_exists_mask & AXIS_BIT_Z) != 0)
        g_api.SetAxis(map_trigger_axis(state->left_trigger, g_axis_max[2]),
                      (UINT)g_state.device_id, HID_USAGE_Z);
    else if ((g_state.axis_exists_mask & AXIS_BIT_SL0) != 0)
        g_api.SetAxis(map_trigger_axis(state->left_trigger, g_axis_max[6]),
                      (UINT)g_state.device_id, HID_USAGE_SL0);

    if ((g_state.axis_exists_mask & AXIS_BIT_RZ) != 0)
        g_api.SetAxis(map_trigger_axis(state->right_trigger, g_axis_max[5]),
                      (UINT)g_state.device_id, HID_USAGE_RZ);
    else if ((g_state.axis_exists_mask & AXIS_BIT_SL1) != 0)
        g_api.SetAxis(map_trigger_axis(state->right_trigger, g_axis_max[7]),
                      (UINT)g_state.device_id, HID_USAGE_SL1);

    apply_pov(state->buttons);

    set_button_if_present(1, (state->buttons & XINPUT_GAMEPAD_A) != 0);
    set_button_if_present(2, (state->buttons & XINPUT_GAMEPAD_B) != 0);
    set_button_if_present(3, (state->buttons & XINPUT_GAMEPAD_X) != 0);
    set_button_if_present(4, (state->buttons & XINPUT_GAMEPAD_Y) != 0);
    set_button_if_present(5, (state->buttons & XINPUT_GAMEPAD_LEFT_SHOULDER) != 0);
    set_button_if_present(6, (state->buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER) != 0);
    set_button_if_present(7, (state->buttons & XINPUT_GAMEPAD_BACK) != 0);
    set_button_if_present(8, (state->buttons & XINPUT_GAMEPAD_START) != 0);
    set_button_if_present(9, (state->buttons & XINPUT_GAMEPAD_LEFT_THUMB) != 0);
    set_button_if_present(10, (state->buttons & XINPUT_GAMEPAD_RIGHT_THUMB) != 0);

    LeaveCriticalSection(&g_engine_cs);
    return true;
}

ENGINE_API bool Engine_SetVJoyDeviceId(uint32_t device_id)
{
    if (!Engine_IsInitialized() || device_id < 1 || device_id > VJD_MAXDEV)
        return false;

    EnterCriticalSection(&g_engine_cs);
    if (g_state.device_id != device_id) {
        if (g_state.ready && g_api.ResetVJD && g_api.RelinquishVJD) {
            g_api.ResetVJD((UINT)g_state.device_id);
            g_api.RelinquishVJD((UINT)g_state.device_id);
        }
        g_state.device_id = device_id;
        g_state.ready = false;
        g_state.status = VJD_STAT_UNKN;
    }
    LeaveCriticalSection(&g_engine_cs);
    return true;
}

ENGINE_API bool Engine_GetVJoyState(VJoyState *state)
{
    if (!state || !Engine_IsInitialized())
        return false;

    EnterCriticalSection(&g_engine_cs);
    ensure_ready_locked();
    *state = g_state;
    LeaveCriticalSection(&g_engine_cs);
    return true;
}

void vjoy_cleanup(void)
{
    EnterCriticalSection(&g_engine_cs);
    if (g_state.ready && g_api.ResetVJD && g_api.RelinquishVJD) {
        g_api.ResetVJD((UINT)g_state.device_id);
        g_api.RelinquishVJD((UINT)g_state.device_id);
    }

    if (g_api.dll)
        FreeLibrary(g_api.dll);

    memset(&g_api, 0, sizeof(g_api));
    memset(g_axis_max, 0, sizeof(g_axis_max));
    g_load_attempted = false;
    g_state.available = false;
    g_state.enabled = false;
    g_state.ready = false;
    g_state.status = VJD_STAT_UNKN;
    g_state.button_count = 0;
    g_state.cont_pov_count = 0;
    g_state.disc_pov_count = 0;
    g_state.axis_exists_mask = 0;
    LeaveCriticalSection(&g_engine_cs);
}
