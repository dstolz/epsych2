// EPsychTeensy — behavioral I/O firmware for the EPsych hw.Teensy backend.
//
// Board:  Teensy 4.0 or 4.1
// Tools:  Arduino IDE + Teensyduino, USB Type = "Serial"
// Host:   obj/+hw/@Teensy in the epsych2 repository
//
// Division of labour:
//   - A single 10 kHz IntervalTimer ISR owns everything with a deadline:
//     sampling and debouncing inputs, timing output pulses, and stepping the
//     trial state machine. Nothing here allocates, blocks, or touches Serial.
//   - loop() owns only the serial protocol: read lines, dispatch, reply.
//
// That split is why a lick can open the reward valve within one tick (100 us)
// no matter what the host is doing. MATLAB configures the trial and collects
// the result; it is never in the timing path.
//
// See firmware/EPsychTeensy/README.md for wiring and the command grammar.

#include "Config.h"
#include "Clock.h"
#include "Params.h"
#include "DigitalIO.h"
#include "EventQueue.h"
#include "TrialFSM.h"
#include "Protocol.h"

EventQueue g_events;

IntervalTimer g_scheduler;

// The one periodic ISR. Order matters: the clock is extended first so every
// timestamp taken later in this tick is consistent, inputs are sampled before
// the state machine so a response lands in the state it actually occurred in,
// and outputs are advanced last so a pulse started this tick gets its full
// width.
void schedulerISR() {
    clk::tickISR();
    dioTickISR();
    fsmTickISR();
}

void setup() {
    Serial.begin(115200);   // ignored by native USB, which always runs full speed

    paramsBegin();
    g_events.begin();
    dioBegin();
    fsmBegin();
    protoBegin();

    g_scheduler.begin(schedulerISR, TICK_US);

    // Highest priority: a missed tick is a missed millisecond of trial timing,
    // which matters more than anything else this firmware does. USB servicing
    // runs below it and only affects how quickly the host is answered.
    g_scheduler.priority(0);

    // The greeting is how hw.Teensy.findBoardPort identifies this board while
    // scanning ports. It is the one line sent without being asked for, and it
    // is sent before the host can have issued a command.
    Serial.println("EPsychTeensy ready");
}

void loop() {
    protoPoll();
}
