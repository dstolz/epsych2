// Params.h — the parameter registry.
//
// One table drives DESC?, GET, SET, SETM and SNAP. Adding a parameter is a
// single row here plus an enum entry, rather than an edit in four switch
// statements that can drift apart.
//
// Naming follows EPsych conventions so the host side needs no special cases:
//   x_NewTrial_<N>, x_ResetTrig_<N>, x_TrialComplete_<N>
//       required by epsych.Runtime; the first two are triggers, the third is
//       polled every timer tick.
//   RespCode, RespLatency, InTrial, TrialType
//       what the shipped analyses and GUIs look for.
//   _TrigState~<N>, _TrialNum~<N>
//       the exact literals gui.OnlinePlot uses for trial-onset detection.
//   A leading '!' marks a trigger; leading '_', '~' or '#' marks hidden.

#pragma once

#include <Arduino.h>
#include "Config.h"

// Stringify BOX_ID so the required names carry the box number.
#define EPT_STR(x)  #x
#define EPT_XSTR(x) EPT_STR(x)
#define BOX_SUFFIX  EPT_XSTR(BOX_ID)

enum PType : uint8_t { P_F = 0, P_I = 1, P_B = 2 };
enum PAccess : uint8_t { A_R = 0, A_W = 1, A_RW = 2 };
enum PFlags : uint8_t { F_NONE = 0, F_TRIG = 1, F_HIDDEN = 2 };

struct ParamDef {
    const char* name;
    uint8_t     access;
    uint8_t     type;
    uint8_t     flags;
    float       minVal;
    float       maxVal;
    const char* unit;
};

// Parameter indices. Order must match PARAMS[] in Params.cpp.
enum ParamIndex : uint8_t {
    // --- required by epsych.Runtime -------------------------------------
    PX_NEW_TRIAL = 0,
    PX_RESET_TRIG,
    PX_TRIAL_COMPLETE,

    // --- trial results ---------------------------------------------------
    PX_RESP_CODE,
    PX_RESP_LATENCY,
    PX_IN_TRIAL,
    PX_TRIAL_TYPE,

    // --- live input state -------------------------------------------------
    PX_RESP,
    PX_RESP2,
    PX_RESP_LATCH,
    PX_RESP_COUNT,

    // --- gui.OnlinePlot hooks (hidden) -----------------------------------
    PX_TRIG_STATE,
    PX_TRIAL_NUM,

    // --- trial timing (ms) ------------------------------------------------
    PX_PRE_WINDOW_DUR,
    PX_CUE_DUR,
    PX_RESP_WIN_DELAY,
    PX_RESP_WIN_DUR,
    PX_POST_WIN_DUR,
    PX_ITI_DUR,

    // --- contingency ------------------------------------------------------
    PX_REWARD_DUR,
    PX_PUNISH_DUR,
    PX_TIMEOUT_DUR,
    PX_SYNC_DUR,
    PX_RESP_THRESH,
    PX_AUTO_REWARD,
    PX_DEBOUNCE_MS,

    // --- manual output control -------------------------------------------
    PX_TRG_REWARD,
    PX_TRG_PUNISH,
    PX_TRG_CUE,
    PX_TRG_SYNC,
    PX_HOUSE_LIGHT,

    NUM_PARAMS
};

extern const ParamDef PARAMS[NUM_PARAMS];

// Value storage, parallel to PARAMS. Two arrays rather than a union: it costs
// a few hundred bytes on a 1 MB part and removes any question of aliasing
// between the scheduler ISR and loop().
extern volatile float   gF[NUM_PARAMS];
extern volatile int32_t gI[NUM_PARAMS];

// Initialize every parameter to its documented default.
void paramsBegin();

// Resolve a name to an index, or -1 when unknown.
int paramFind(const char* name);

// Read a parameter as a float, whatever its declared type.
float paramGetF(uint8_t idx);

// Write a parameter from a float, coercing to its declared type. Applies
// Min/Max clamping and any side effect the parameter has (e.g. HouseLight
// drives its pin immediately).
void paramSet(uint8_t idx, float value);

// Format a parameter's current value into buf. Integers are printed exactly:
// RespCode is a uint32 bitmask whose high bits do not survive a float32.
void paramFormat(uint8_t idx, char* buf, size_t len);

inline bool paramIsTrigger(uint8_t idx) { return PARAMS[idx].flags & F_TRIG; }
inline bool paramIsReadable(uint8_t idx) { return PARAMS[idx].access != A_W; }
