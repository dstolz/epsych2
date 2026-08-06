// Clock.h — rollover-safe microsecond timebase.
//
// Arduino's micros() is a uint32 that wraps every ~71.6 minutes. A behavioral
// session routinely outlives that, and the failure is nasty: timestamps jump
// backwards mid-session and every latency computed from them is silently wrong,
// with nothing logged. So every timestamp in this firmware comes from
// micros64() instead.
//
// The extension works by watching for the low word to go backwards. That
// requires being called at least once per wrap period, which the 10 kHz
// scheduler ISR guarantees many times over.

#pragma once

#include <Arduino.h>
#include "Critical.h"

namespace clk {

inline volatile uint32_t g_lastLow = 0;
inline volatile uint32_t g_high = 0;

// Advance the rollover counter. Called from the scheduler ISR only.
inline void tickISR() {
    uint32_t low = micros();
    if (low < g_lastLow) {
        g_high++;   // the low word wrapped
    }
    g_lastLow = low;
}

// Current time in microseconds since boot, safe across rollover.
//
// Reads the two halves under a critical section: without it a wrap landing
// between the two reads would pair a new low word with an old high word and
// report a time ~71 minutes in the past.
inline uint64_t micros64() {
    // critEnter/critExit rather than noInterrupts/interrupts: this is called
    // from the scheduler ISR as well as from loop().
    uint32_t p = critEnter();
    uint32_t high = g_high;
    uint32_t low  = micros();
    // If the wrap happened after the ISR's last observation but before this
    // read, account for it here rather than reporting a stale high word.
    if (low < g_lastLow) {
        high++;
    }
    critExit(p);
    return ((uint64_t)high << 32) | low;
}

// Milliseconds -> scheduler ticks, rounded to the nearest tick and clamped to
// at least one tick so a nonzero duration never becomes instantaneous.
inline uint32_t msToTicks(float ms) {
    if (ms <= 0.0f) return 0;
    uint32_t t = (uint32_t)(ms * (TICK_HZ / 1000.0f) + 0.5f);
    return t == 0 ? 1 : t;
}

}  // namespace clk
