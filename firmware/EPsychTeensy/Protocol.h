// Protocol.h — the ASCII command interface.
//
// Grammar: one LF-terminated command per line, one reply line per command (or
// one BEGIN/END block). Once running, the firmware emits nothing it was not
// asked for. That is a deliberate constraint, not an omission: it keeps the
// host's request/response model valid, so hw.Teensy can write a command and
// read exactly one line without having to demultiplex asynchronous event lines
// out of the stream.
//
// The single exception is the boot greeting ("EPsychTeensy ready"), sent from
// setup() before any command can have arrived, which is how port auto-detection
// recognizes the board. The host flushes it before handshaking.
//
// Input events are still stamped on-device to the microsecond; only their
// DELIVERY is polled. The host sees latched state cheaply in every SNAP and
// pulls the precise timestamped history with EVT?.
//
//   ID?                  -> ID EPsychTeensy PROTO=.. FW=.. BOARD=.. SN=.. BOXES=.. TICKHZ=..
//   DESC?                -> DESC BEGIN / P <name> <acc> <type> <flags> <min> <max> <unit> / DESC END
//   GET <name>           -> VAL <name> <value>
//   SET <name> <value>   -> OK
//   SETM <n>=<v> ...     -> OK
//   SNAP                 -> SNAP <us> MODE=<n> NEVT=<k> OVF=<0|1> <name>=<v> ...
//   TRG <name>           -> OK <us>
//   MODE <n> | MODE?     -> OK | MODE <n>
//   EVT?                 -> EVT BEGIN / E <us> <name> <value> / EVT END
//   SYNC                 -> SYNC <us>
//   RESET                -> OK
//   HELP                 -> HELP BEGIN / ... / HELP END
//
// Errors are always "ERR <code> <text>":
//   1 parse   2 unknown parameter   3 access violation   4 bad value

#pragma once

#include <Arduino.h>

void protoBegin();

// Drain available serial bytes and dispatch any complete lines. Called from
// loop(); never blocks.
void protoPoll();

// Current device state as an hw.DeviceState integer.
int8_t protoMode();
