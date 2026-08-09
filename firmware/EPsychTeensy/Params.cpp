// Params.cpp — the parameter table and its accessors.

#include "Params.h"
#include "DigitalIO.h"

#include <string.h>
#include <stdio.h>
#include <math.h>

volatile float   gF[NUM_PARAMS];
volatile int32_t gI[NUM_PARAMS];

// Order must match enum ParamIndex exactly.
const ParamDef PARAMS[NUM_PARAMS] = {
    // name                            access type  flags            min      max     unit
    { "x_NewTrial_"      BOX_SUFFIX, A_RW, P_B, F_TRIG,             0,       1,    "-"  },
    { "x_ResetTrig_"     BOX_SUFFIX, A_RW, P_B, F_TRIG,             0,       1,    "-"  },
    { "x_TrialComplete_" BOX_SUFFIX, A_R,  P_B, F_NONE,             0,       1,    "-"  },

    { "RespCode",                    A_R,  P_I, F_NONE,             0, 2147483647, "-"  },
    { "RespLatency",                 A_R,  P_F, F_NONE,            -1,  600000,    "ms" },
    { "InTrial",                     A_R,  P_B, F_NONE,             0,       1,    "-"  },
    { "TrialType",                   A_RW, P_I, F_NONE,             0,       5,    "-"  },

    { "Resp",                        A_R,  P_B, F_NONE,             0,       1,    "-"  },
    { "Resp2",                       A_R,  P_B, F_NONE,             0,       1,    "-"  },
    { "RespLatch",                   A_R,  P_B, F_NONE,             0,       1,    "-"  },
    { "RespCount",                   A_R,  P_I, F_NONE,             0,  1000000,    "-"  },

    { "_TrigState~"      BOX_SUFFIX, A_R,  P_B, F_HIDDEN,           0,       1,    "-"  },
    { "_TrialNum~"       BOX_SUFFIX, A_R,  P_I, F_HIDDEN,           0, 1000000,    "-"  },

    { "PreWindowDur",                A_RW, P_F, F_NONE,             0,  600000,    "ms" },
    { "CueDur",                      A_RW, P_F, F_NONE,             0,  600000,    "ms" },
    { "RespWinDelay",                A_RW, P_F, F_NONE,             0,  600000,    "ms" },
    { "RespWinDur",                  A_RW, P_F, F_NONE,             0,  600000,    "ms" },
    { "PostWinDur",                  A_RW, P_F, F_NONE,             0,  600000,    "ms" },
    { "ITIDur",                      A_RW, P_F, F_NONE,             0,  600000,    "ms" },

    { "RewardDur",                   A_RW, P_F, F_NONE,             0,   60000,    "ms" },
    { "PunishDur",                   A_RW, P_F, F_NONE,             0,   60000,    "ms" },
    { "TimeoutDur",                  A_RW, P_F, F_NONE,             0,  600000,    "ms" },
    { "SyncDur",                     A_RW, P_F, F_NONE,             0,    1000,    "ms" },
    { "RespCountThresh",             A_RW, P_I, F_NONE,             1,    1000,    "-"  },
    { "AutoReward",                  A_RW, P_B, F_NONE,             0,       1,    "-"  },
    { "DebounceMs",                  A_RW, P_F, F_NONE,             0,    1000,    "ms" },

    { "!Reward",                     A_RW, P_B, F_TRIG,             0,       1,    "-"  },
    { "!Punish",                     A_RW, P_B, F_TRIG,             0,       1,    "-"  },
    { "!Cue",                        A_RW, P_B, F_TRIG,             0,       1,    "-"  },
    { "!SyncPulse",                  A_RW, P_B, F_TRIG,             0,       1,    "-"  },
    { "HouseLight",                  A_RW, P_B, F_NONE,             0,       1,    "-"  },
};

void paramsBegin() {
    for (uint8_t i = 0; i < NUM_PARAMS; i++) {
        gF[i] = 0.0f;
        gI[i] = 0;
    }

    gF[PX_PRE_WINDOW_DUR] = DEFAULT_PRE_WINDOW_MS;
    gF[PX_CUE_DUR]        = DEFAULT_CUE_MS;
    gF[PX_RESP_WIN_DELAY] = DEFAULT_RESP_DELAY_MS;
    gF[PX_RESP_WIN_DUR]   = DEFAULT_RESP_WIN_MS;
    gF[PX_POST_WIN_DUR]   = DEFAULT_POST_WIN_MS;
    gF[PX_ITI_DUR]        = DEFAULT_ITI_MS;

    gF[PX_REWARD_DUR]     = DEFAULT_REWARD_MS;
    gF[PX_PUNISH_DUR]     = DEFAULT_PUNISH_MS;
    gF[PX_TIMEOUT_DUR]    = DEFAULT_TIMEOUT_MS;
    gF[PX_SYNC_DUR]       = DEFAULT_SYNC_MS;
    gF[PX_DEBOUNCE_MS]    = DEFAULT_DEBOUNCE_MS;

    gI[PX_RESP_THRESH]    = DEFAULT_RESP_THRESH;
    gI[PX_AUTO_REWARD]    = 1;

    // No trial has run yet. -1 distinguishes "never responded" from a genuine
    // zero-millisecond latency, which a Miss would otherwise be confused with.
    gF[PX_RESP_LATENCY]   = -1.0f;
}

int paramFind(const char* name) {
    for (uint8_t i = 0; i < NUM_PARAMS; i++) {
        if (strcmp(PARAMS[i].name, name) == 0) return (int)i;
    }
    return -1;
}

float paramGetF(uint8_t idx) {
    if (PARAMS[idx].type == P_F) return gF[idx];
    return (float)gI[idx];
}

void paramSet(uint8_t idx, float value) {
    const ParamDef& d = PARAMS[idx];

    if (!isfinite(value)) return;
    if (value < d.minVal) value = d.minVal;
    if (value > d.maxVal) value = d.maxVal;

    if (d.type == P_F) {
        gF[idx] = value;
    } else {
        gI[idx] = (int32_t)lroundf(value);
        if (d.type == P_B) gI[idx] = (gI[idx] != 0) ? 1 : 0;
    }

    // Side effects for parameters that are more than storage.
    switch (idx) {
        case PX_HOUSE_LIGHT:
            digitalWriteFast(PIN_HOUSELIGHT, gI[PX_HOUSE_LIGHT] ? HIGH : LOW);
            break;
        case PX_DEBOUNCE_MS:
            dioSetDebounce(gF[PX_DEBOUNCE_MS]);
            break;
        default:
            break;
    }
}

void paramFormat(uint8_t idx, char* buf, size_t len) {
    if (PARAMS[idx].type == P_F) {
        // %.6g matches what the MATLAB side writes, so a value round-trips
        // through SET/GET unchanged.
        snprintf(buf, len, "%.6g", (double)gF[idx]);
    } else {
        // Printed as an exact integer: RespCode is a uint32 bitmask and a
        // float32 cannot represent its high bits.
        snprintf(buf, len, "%ld", (long)gI[idx]);
    }
}
