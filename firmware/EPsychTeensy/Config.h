// Config.h — build-time configuration for EPsychTeensy.
//
// Everything a rig might need to change lives here: pin assignments, buffer
// sizes, and the scheduler rate. Nothing below this file should hard-code a
// pin number.
//
// Target: Teensy 4.0 or 4.1, Arduino IDE + Teensyduino, USB Type = "Serial".

#pragma once

#include <Arduino.h>

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

#define FW_VERSION      "1.0.0"

// Wire protocol version. hw.Teensy.PROTOCOL_VERSION must match; a mismatch is
// reported at connect because a changed grammar fails as garbled replies
// rather than as a clean error.
#define PROTO_VERSION   1

#if defined(ARDUINO_TEENSY41)
  #define BOARD_NAME "Teensy4.1"
#elif defined(ARDUINO_TEENSY40)
  #define BOARD_NAME "Teensy4.0"
#else
  #define BOARD_NAME "TeensyUnknown"
  #warning "EPsychTeensy targets Teensy 4.0/4.1. Other boards are untested."
#endif

// Box identifier. Appears in the x_NewTrial_<N> / x_ResetTrig_<N> /
// x_TrialComplete_<N> names that epsych.Runtime requires.
//
// One board serves one box. That keeps the conventional analysis names
// (RespCode, RespLatency, InTrial) unsuffixed, which is what gui.History and
// psychophysics.Detection look for. Two boxes means two boards.
#define BOX_ID          1

// ---------------------------------------------------------------------------
// Scheduler
// ---------------------------------------------------------------------------

// Rate of the single IntervalTimer ISR that samples inputs, debounces them,
// advances output pulses, and steps the trial state machine. This is the
// resolution of every on-device timestamp and pulse edge. Reported to MATLAB
// as TICKHZ and stored as the module's Fs.
//
// 10 kHz (100 us) is comfortably faster than any behavioral event and leaves
// the CPU almost entirely free on a 600 MHz Teensy 4.
#define TICK_HZ         10000
#define TICK_US         (1000000UL / TICK_HZ)

// ---------------------------------------------------------------------------
// Buffers
// ---------------------------------------------------------------------------

// Longest command line accepted. Must be >= hw.Teensy.MAX_LINE_LENGTH, which
// is what the MATLAB side chunks batched SETM writes below.
#define LINE_BUFFER_LEN 256

// Timestamped input events retained between drains. At a 10 ms poll interval
// this is far more headroom than a behaving animal can fill; an overflow drops
// the OLDEST event and raises a flag reported in SNAP.
#define EVENT_QUEUE_LEN 256

// ---------------------------------------------------------------------------
// Pin map
// ---------------------------------------------------------------------------
//
// Inputs are read with INPUT_PULLUP, so a switch, lickometer, or open-collector
// sensor shorts the pin to ground. ACTIVE_LOW below converts that to logical
// true = "animal responding". Set ACTIVE_LOW to 0 for a sensor that drives the
// pin high.

#define PIN_RESPONSE    2   // primary response: lick spout, nose poke, lever
#define PIN_RESPONSE2   3   // second response channel (2AFC), or a beam break

#define PIN_REWARD      4   // reward valve / pump gate
#define PIN_PUNISH      5   // air puff, shock gate, or house-light-off
#define PIN_CUE         6   // cue LED or stimulus gate out
#define PIN_SYNC        7   // TTL sync pulse to the ephys system
#define PIN_HOUSELIGHT  8   // house light

#define RESPONSE_ACTIVE_LOW  1

// The onboard LED mirrors InTrial, so a rig can be diagnosed without a host.
#define PIN_STATUS_LED  LED_BUILTIN

// ---------------------------------------------------------------------------
// Defaults
// ---------------------------------------------------------------------------

// Contact bounce rejection for digital inputs. An input must hold a new level
// for this long before an edge is reported. 5 ms clears typical lickometer and
// microswitch bounce without hiding real licks (which cannot exceed ~10 Hz).
#define DEFAULT_DEBOUNCE_MS   5.0f

#define DEFAULT_PRE_WINDOW_MS   0.0f
#define DEFAULT_CUE_MS        200.0f
#define DEFAULT_RESP_DELAY_MS   0.0f
#define DEFAULT_RESP_WIN_MS  2000.0f
#define DEFAULT_POST_WIN_MS     0.0f
#define DEFAULT_ITI_MS       1000.0f
#define DEFAULT_REWARD_MS      50.0f
#define DEFAULT_PUNISH_MS     200.0f
#define DEFAULT_TIMEOUT_MS      0.0f
#define DEFAULT_SYNC_MS         1.0f
#define DEFAULT_RESP_THRESH     1
