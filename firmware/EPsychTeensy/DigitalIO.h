// DigitalIO.h — debounced inputs with latches, and timed outputs.
//
// Both halves are driven from the scheduler ISR, so an output pulse width is
// accurate to one tick (100 us) regardless of what the host is doing, and an
// input edge is stamped the moment the debounce interval closes.

#pragma once

#include <Arduino.h>
#include "Config.h"

// Configure pins and clear all state.
void dioBegin();

// Sample inputs, update debounce state and latches, and advance any output
// pulses. Called once per scheduler tick from the ISR.
void dioTickISR();

// Change the debounce interval for all inputs.
void dioSetDebounce(float ms);

// Start a one-shot pulse on an output pin. A pulse already running on that pin
// is restarted rather than queued: the caller asked for the output to be
// active for durationMs from now, and extending it is the least surprising
// reading of a repeated request.
void dioPulse(uint8_t pin, float durationMs);

// True while any pulse is active on the pin.
bool dioPulseActive(uint8_t pin);

// Clear the sticky response latch and the response counter.
void dioClearLatch();

// Stop every output pulse immediately and drive the pins low.
void dioAllOff();
