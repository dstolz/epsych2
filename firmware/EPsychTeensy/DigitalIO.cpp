// DigitalIO.cpp — debounced inputs with latches, and timed outputs.

#include "DigitalIO.h"
#include "Params.h"
#include "Clock.h"
#include "Critical.h"
#include "EventQueue.h"
#include "TrialFSM.h"

namespace {

// --- inputs ---------------------------------------------------------------

struct InputChan {
    uint8_t pin;
    uint8_t paramIdx;
    uint8_t stable;      // current debounced level
    uint8_t candidate;   // level currently being timed
    uint32_t heldTicks;  // how long candidate has held
};

InputChan g_in[] = {
    { PIN_RESPONSE,  PX_RESP,  0, 0, 0 },
    { PIN_RESPONSE2, PX_RESP2, 0, 0, 0 },
};
constexpr uint8_t N_IN = sizeof(g_in) / sizeof(g_in[0]);

volatile uint32_t g_debounceTicks = 1;

// --- outputs --------------------------------------------------------------

struct OutputChan {
    uint8_t pin;
    volatile uint32_t remaining;  // ticks left in the current pulse; 0 = idle
};

OutputChan g_out[] = {
    { PIN_REWARD, 0 },
    { PIN_PUNISH, 0 },
    { PIN_CUE,    0 },
    { PIN_SYNC,   0 },
};
constexpr uint8_t N_OUT = sizeof(g_out) / sizeof(g_out[0]);

int outIndex(uint8_t pin) {
    for (uint8_t i = 0; i < N_OUT; i++) {
        if (g_out[i].pin == pin) return (int)i;
    }
    return -1;
}

inline uint8_t readLevel(uint8_t pin) {
    uint8_t raw = digitalReadFast(pin) ? 1 : 0;
#if RESPONSE_ACTIVE_LOW
    return raw ? 0 : 1;   // INPUT_PULLUP: shorted to ground means "responding"
#else
    return raw;
#endif
}

}  // namespace

void dioBegin() {
    for (uint8_t i = 0; i < N_IN; i++) {
        pinMode(g_in[i].pin, INPUT_PULLUP);
        g_in[i].stable = readLevel(g_in[i].pin);
        g_in[i].candidate = g_in[i].stable;
        g_in[i].heldTicks = 0;
        gI[g_in[i].paramIdx] = g_in[i].stable;
    }

    for (uint8_t i = 0; i < N_OUT; i++) {
        pinMode(g_out[i].pin, OUTPUT);
        digitalWriteFast(g_out[i].pin, LOW);
        g_out[i].remaining = 0;
    }

    pinMode(PIN_HOUSELIGHT, OUTPUT);
    digitalWriteFast(PIN_HOUSELIGHT, LOW);

    pinMode(PIN_STATUS_LED, OUTPUT);
    digitalWriteFast(PIN_STATUS_LED, LOW);

    dioSetDebounce(DEFAULT_DEBOUNCE_MS);
}

void dioSetDebounce(float ms) {
    uint32_t t = clk::msToTicks(ms);
    g_debounceTicks = (t == 0) ? 1 : t;
}

void dioTickISR() {
    // --- inputs -----------------------------------------------------------
    for (uint8_t i = 0; i < N_IN; i++) {
        InputChan& c = g_in[i];
        uint8_t raw = readLevel(c.pin);

        if (raw != c.candidate) {
            // A new level: restart the debounce interval rather than accepting
            // it. Contact bounce shows up here as a candidate that keeps
            // changing and never accumulates enough held ticks.
            c.candidate = raw;
            c.heldTicks = 0;
            continue;
        }

        if (raw == c.stable) {
            c.heldTicks = 0;
            continue;
        }

        if (++c.heldTicks < g_debounceTicks) {
            continue;
        }

        // The edge is real. Stamp it now; note the timestamp marks the moment
        // the debounce interval closed, so it lags the physical edge by
        // DebounceMs. That is a fixed, known offset rather than jitter.
        c.stable = raw;
        c.heldTicks = 0;
        gI[c.paramIdx] = c.stable;
        g_events.push(c.paramIdx, c.stable, clk::micros64());

        if (c.pin == PIN_RESPONSE && c.stable) {
            gI[PX_RESP_LATCH] = 1;
            gI[PX_RESP_COUNT] = gI[PX_RESP_COUNT] + 1;
            fsmOnResponseISR(clk::micros64());
        }
    }

    // --- outputs ----------------------------------------------------------
    for (uint8_t i = 0; i < N_OUT; i++) {
        if (g_out[i].remaining == 0) continue;
        if (--g_out[i].remaining == 0) {
            digitalWriteFast(g_out[i].pin, LOW);
        }
    }
}

void dioPulse(uint8_t pin, float durationMs) {
    int idx = outIndex(pin);
    if (idx < 0) return;

    uint32_t ticks = clk::msToTicks(durationMs);
    if (ticks == 0) return;   // a zero-length pulse is a no-op, not a latch-on

    // Reachable from the scheduler ISR (TrialFSM delivers reward from there),
    // so the section must be nesting-safe.
    uint32_t p = critEnter();
    g_out[idx].remaining = ticks;
    digitalWriteFast(pin, HIGH);
    critExit(p);
}

bool dioPulseActive(uint8_t pin) {
    int idx = outIndex(pin);
    return idx >= 0 && g_out[idx].remaining != 0;
}

void dioClearLatch() {
    uint32_t p = critEnter();
    gI[PX_RESP_LATCH] = 0;
    gI[PX_RESP_COUNT] = 0;
    critExit(p);
}

void dioAllOff() {
    uint32_t p = critEnter();
    for (uint8_t i = 0; i < N_OUT; i++) {
        g_out[i].remaining = 0;
        digitalWriteFast(g_out[i].pin, LOW);
    }
    critExit(p);
}
