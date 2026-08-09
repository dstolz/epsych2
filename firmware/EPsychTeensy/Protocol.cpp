// Protocol.cpp — the ASCII command interface.

#include "Protocol.h"
#include "Params.h"
#include "Config.h"
#include "Clock.h"
#include "DigitalIO.h"
#include "EventQueue.h"
#include "TrialFSM.h"

#include <string.h>
#include <stdlib.h>
#include <stdio.h>

namespace {

char  g_line[LINE_BUFFER_LEN];
size_t g_len = 0;
bool  g_overrun = false;

// hw.DeviceState: Idle 0, Standby 1, Preview 2, Record 3, Stop 4, Pause 5, Error -1.
int8_t g_mode = 0;

void err(int code, const char* text) {
    Serial.print("ERR ");
    Serial.print(code);
    Serial.print(' ');
    Serial.println(text);
}

void printU64(uint64_t v) {
    // Neither Print::print nor %llu is reliable across toolchains here, so
    // build the digits by hand.
    char buf[21];
    int i = 20;
    buf[i] = '\0';
    if (v == 0) {
        buf[--i] = '0';
    } else {
        while (v > 0 && i > 0) {
            buf[--i] = (char)('0' + (v % 10));
            v /= 10;
        }
    }
    Serial.print(&buf[i]);
}

void cmdId() {
    Serial.print("ID EPsychTeensy PROTO=");
    Serial.print(PROTO_VERSION);
    Serial.print(" FW=" FW_VERSION " BOARD=" BOARD_NAME " SN=");

    // Teensy 4.x exposes a unique 64-bit chip ID through the OCOTP fuses. It
    // is what lets AutoDetect tell two identical boards apart in one rig.
    Serial.print(HW_OCOTP_MAC1 & 0xFFFF, HEX);
    Serial.print(HW_OCOTP_MAC0, HEX);

    Serial.print(" BOXES=" BOX_SUFFIX " TICKHZ=");
    Serial.println(TICK_HZ);
}

void cmdDesc() {
    Serial.println("DESC BEGIN");
    for (uint8_t i = 0; i < NUM_PARAMS; i++) {
        const ParamDef& d = PARAMS[i];

        const char* acc = (d.access == A_R) ? "R" : (d.access == A_W ? "W" : "RW");
        const char* typ = (d.type == P_F) ? "F" : (d.type == P_I ? "I" : "B");

        char flags[4];
        uint8_t n = 0;
        if (d.flags & F_TRIG)   flags[n++] = 'T';
        if (d.flags & F_HIDDEN) flags[n++] = 'H';
        if (n == 0) flags[n++] = '-';
        flags[n] = '\0';

        char lo[24], hi[24];
        snprintf(lo, sizeof(lo), "%.6g", (double)d.minVal);
        snprintf(hi, sizeof(hi), "%.6g", (double)d.maxVal);

        Serial.print("P ");
        Serial.print(d.name);   Serial.print(' ');
        Serial.print(acc);      Serial.print(' ');
        Serial.print(typ);      Serial.print(' ');
        Serial.print(flags);    Serial.print(' ');
        Serial.print(lo);       Serial.print(' ');
        Serial.print(hi);       Serial.print(' ');
        Serial.println(d.unit);
    }
    Serial.println("DESC END");
}

void cmdGet(const char* name) {
    if (!name) { err(1, "GET needs a name"); return; }

    int idx = paramFind(name);
    if (idx < 0) { err(2, name); return; }
    if (PARAMS[idx].access == A_W) { err(3, name); return; }

    char val[32];
    paramFormat((uint8_t)idx, val, sizeof(val));

    Serial.print("VAL ");
    Serial.print(name);
    Serial.print(' ');
    Serial.println(val);
}

// Apply one name/value assignment. Returns 0 on success or an error code.
int applySet(const char* name, const char* valueText) {
    int idx = paramFind(name);
    if (idx < 0) return 2;
    if (PARAMS[idx].access == A_R) return 3;

    char* end = nullptr;
    float v = strtof(valueText, &end);
    if (end == valueText) return 4;

    paramSet((uint8_t)idx, v);
    return 0;
}

void cmdSet(char* rest) {
    char* name = strtok(rest, " ");
    char* val  = strtok(nullptr, " ");
    if (!name || !val) { err(1, "SET needs a name and a value"); return; }

    int rc = applySet(name, val);
    if (rc == 0) Serial.println("OK");
    else if (rc == 2) err(2, name);
    else if (rc == 3) err(3, name);
    else err(4, name);
}

// Batched write: "SETM a=1 b=2 c=3". This is where a trial's parameters land,
// collapsing k host round-trips into one.
//
// Applied strictly left to right and aborted at the first bad token, so a
// malformed batch cannot leave a trial half-configured without saying so.
void cmdSetM(char* rest) {
    char* tok = strtok(rest, " ");
    if (!tok) { err(1, "SETM needs assignments"); return; }

    while (tok) {
        char* eq = strchr(tok, '=');
        if (!eq) { err(1, tok); return; }
        *eq = '\0';

        int rc = applySet(tok, eq + 1);
        if (rc == 2) { err(2, tok); return; }
        if (rc == 3) { err(3, tok); return; }
        if (rc == 4) { err(4, tok); return; }

        tok = strtok(nullptr, " ");
    }
    Serial.println("OK");
}

// One line carrying every readable value plus the mode and the pending event
// count. This is what lets the host read all of a trial's results in a single
// round-trip instead of one per parameter.
void cmdSnap() {
    Serial.print("SNAP ");
    printU64(clk::micros64());

    Serial.print(" MODE=");
    Serial.print(g_mode);
    Serial.print(" NEVT=");
    Serial.print(g_events.count());
    Serial.print(" OVF=");
    Serial.print(g_events.overflowed() ? 1 : 0);

    char val[32];
    for (uint8_t i = 0; i < NUM_PARAMS; i++) {
        if (!paramIsReadable(i)) continue;
        paramFormat(i, val, sizeof(val));
        Serial.print(' ');
        Serial.print(PARAMS[i].name);
        Serial.print('=');
        Serial.print(val);
    }
    Serial.println();
}

void cmdTrigger(const char* name) {
    if (!name) { err(1, "TRG needs a name"); return; }

    int idx = paramFind(name);
    if (idx < 0) { err(2, name); return; }
    if (!paramIsTrigger((uint8_t)idx)) { err(3, name); return; }

    uint64_t us = clk::micros64();

    switch (idx) {
        case PX_NEW_TRIAL:  fsmStartTrial(); break;
        case PX_RESET_TRIG: fsmReset();      break;

        case PX_TRG_REWARD: dioPulse(PIN_REWARD, gF[PX_REWARD_DUR]); break;
        case PX_TRG_PUNISH: dioPulse(PIN_PUNISH, gF[PX_PUNISH_DUR]); break;
        case PX_TRG_CUE:    dioPulse(PIN_CUE,    gF[PX_CUE_DUR]);    break;
        case PX_TRG_SYNC:   dioPulse(PIN_SYNC,   gF[PX_SYNC_DUR]);   break;

        default: break;
    }

    Serial.print("OK ");
    printU64(us);
    Serial.println();
}

void cmdMode(const char* arg) {
    if (!arg) { err(1, "MODE needs a state"); return; }

    long m = strtol(arg, nullptr, 10);
    if (m < -1 || m > 5) { err(4, "mode out of range"); return; }

    g_mode = (int8_t)m;

    // Leaving the running states puts the hardware in a safe condition rather
    // than freezing mid-trial with a valve open.
    if (g_mode == 0 || g_mode == 4 || g_mode == -1) {
        fsmReset();
        dioAllOff();
    }

    Serial.println("OK");
}

void cmdEvents() {
    Serial.println("EVT BEGIN");
    Event e;
    while (g_events.pop(e)) {
        Serial.print("E ");
        printU64(e.us);
        Serial.print(' ');
        Serial.print(e.param < NUM_PARAMS ? PARAMS[e.param].name : "?");
        Serial.print(' ');
        Serial.println(e.value);
    }
    Serial.println("EVT END");
}

void cmdHelp() {
    Serial.println("HELP BEGIN");
    Serial.println("ID?                identify board");
    Serial.println("DESC?              parameter descriptor block");
    Serial.println("GET <name>         read one parameter");
    Serial.println("SET <name> <v>     write one parameter");
    Serial.println("SETM <n>=<v> ...   batched write");
    Serial.println("SNAP               all readable values in one line");
    Serial.println("TRG <name>         fire a trigger");
    Serial.println("MODE <n> | MODE?   device state (hw.DeviceState)");
    Serial.println("EVT?               drain timestamped events");
    Serial.println("SYNC               board clock in microseconds");
    Serial.println("RESET              abort trial, clear latches and events");
    Serial.println("HELP END");
}

void dispatch(char* line) {
    char* cmd = strtok(line, " ");
    if (!cmd) return;

    if      (!strcmp(cmd, "ID?"))    cmdId();
    else if (!strcmp(cmd, "DESC?"))  cmdDesc();
    else if (!strcmp(cmd, "SNAP"))   cmdSnap();
    else if (!strcmp(cmd, "EVT?"))   cmdEvents();
    else if (!strcmp(cmd, "MODE?"))  { Serial.print("MODE "); Serial.println(g_mode); }
    else if (!strcmp(cmd, "HELP"))   cmdHelp();
    else if (!strcmp(cmd, "GET"))    cmdGet(strtok(nullptr, " "));
    else if (!strcmp(cmd, "TRG"))    cmdTrigger(strtok(nullptr, " "));
    else if (!strcmp(cmd, "MODE"))   cmdMode(strtok(nullptr, " "));
    else if (!strcmp(cmd, "SET"))    cmdSet(strtok(nullptr, ""));
    else if (!strcmp(cmd, "SETM"))   cmdSetM(strtok(nullptr, ""));
    else if (!strcmp(cmd, "SYNC"))   { Serial.print("SYNC "); printU64(clk::micros64()); Serial.println(); }
    else if (!strcmp(cmd, "RESET"))  { fsmReset(); dioAllOff(); Serial.println("OK"); }
    else                             err(1, cmd);
}

}  // namespace

void protoBegin() {
    g_len = 0;
    g_overrun = false;
    g_mode = 0;
}

int8_t protoMode() {
    return g_mode;
}

void protoPoll() {
    while (Serial.available() > 0) {
        char c = (char)Serial.read();

        if (c == '\r') continue;

        if (c != '\n') {
            if (g_len < LINE_BUFFER_LEN - 1) {
                g_line[g_len++] = c;
            } else {
                // Keep consuming to the end of the line, then report it. Silently
                // truncating would turn an over-long SETM into a partial write
                // that looks like it succeeded.
                g_overrun = true;
            }
            continue;
        }

        g_line[g_len] = '\0';

        if (g_overrun) {
            err(1, "line too long");
        } else if (g_len > 0) {
            dispatch(g_line);
        }

        g_len = 0;
        g_overrun = false;
    }
}
