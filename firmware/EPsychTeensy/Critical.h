// Critical.h — nesting-safe critical sections.
//
// Arduino's noInterrupts()/interrupts() pair is wrong for any code reachable
// from both loop() and an ISR: the trailing interrupts() enables interrupts
// unconditionally, so calling such a function from inside the scheduler ISR
// re-enables interrupts partway through and lets the same ISR re-enter itself.
// With a 10 kHz timer and a trial state machine holding the state, that is a
// rare, timing-dependent corruption — the worst kind to debug.
//
// Saving and restoring PRIMASK instead makes the section a no-op when
// interrupts are already disabled, so the same helper is safe from either
// context.
//
// Usage:
//     uint32_t p = critEnter();
//     ... touch shared state ...
//     critExit(p);

#pragma once

#include <Arduino.h>

inline uint32_t critEnter() {
    uint32_t primask = __get_PRIMASK();
    __disable_irq();
    return primask;
}

inline void critExit(uint32_t primask) {
    __set_PRIMASK(primask);
}
