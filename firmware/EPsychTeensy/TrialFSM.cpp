// TrialFSM.cpp — the on-device trial state machine.

#include "TrialFSM.h"
#include "Params.h"
#include "Config.h"
#include "Clock.h"
#include "Critical.h"
#include "DigitalIO.h"
#include "EventQueue.h"
#include "BitMask.h"

namespace {

volatile FsmState g_state = FSM_IDLE;
volatile uint32_t g_remaining = 0;    // ticks left in the current state

volatile uint64_t g_cueOnsetUs = 0;   // t0 for RespLatency
volatile uint32_t g_winResponses = 0; // responses inside the response window
volatile bool     g_earlyResponse = false;
volatile bool     g_lateResponse = false;
volatile bool     g_responded = false;

// Enter a state with a duration in milliseconds. A zero duration falls through
// on the next tick rather than lasting forever, which is what lets a protocol
// switch a phase off by setting its duration to 0.
void enter(FsmState s, float ms) {
    g_state = s;
    g_remaining = clk::msToTicks(ms);
}

// Compute RespCode and drive the contingency outputs.
//
// Bit indices come from bm::, which mirrors epsych.BitMask. The trial-type and
// response-period bits are included so psychophysics.Detection and gui.History
// can slice the session without a separate column.
void resolveOutcome() {
    uint32_t mask = 0;
    int32_t trialType = gI[PX_TRIAL_TYPE];

    bm::set(mask, bm::ResponseWindow);
    mask |= bm::trialType(trialType);

    if (g_earlyResponse) bm::set(mask, bm::PreResponseWindow);
    if (g_lateResponse)  bm::set(mask, bm::PostResponseWindow);

    float timeoutMs = 0.0f;

    // TrialType 0 is the signal/Go condition; anything else is a catch/NoGo.
    // Keeping the split here (rather than spread through the states) is what
    // makes a different paradigm a change to one function.
    if (trialType == 0) {
        if (g_responded) {
            bm::set(mask, bm::Hit);
            if (gI[PX_AUTO_REWARD]) {
                bm::set(mask, bm::Reward);
                dioPulse(PIN_REWARD, gF[PX_REWARD_DUR]);
            }
        } else {
            bm::set(mask, bm::Miss);
        }
    } else {
        if (g_responded) {
            bm::set(mask, bm::FalseAlarm);
            bm::set(mask, bm::Punish);
            dioPulse(PIN_PUNISH, gF[PX_PUNISH_DUR]);
            timeoutMs = gF[PX_TIMEOUT_DUR];
        } else {
            bm::set(mask, bm::CorrectReject);
        }
    }

    gI[PX_RESP_CODE] = (int32_t)mask;
    g_events.push(PX_RESP_CODE, (int32_t)mask, clk::micros64());

    if (timeoutMs > 0.0f) {
        // House light off marks the timeout, the usual convention.
        digitalWriteFast(PIN_HOUSELIGHT, LOW);
        enter(FSM_TIMEOUT, timeoutMs);
    } else {
        enter(FSM_ITI, gF[PX_ITI_DUR]);
    }
}

// Finish the trial and hand control back to the host.
//
// Results are latched here and left untouched until the next ResetTrig, which
// is what makes it safe for the host to read them across more than one device
// snapshot.
void finishTrial() {
    gI[PX_IN_TRIAL] = 0;
    gI[PX_TRIG_STATE] = 0;
    digitalWriteFast(PIN_STATUS_LED, LOW);

    g_state = FSM_IDLE;
    g_remaining = 0;

    gI[PX_TRIAL_COMPLETE] = 1;
    g_events.push(PX_TRIAL_COMPLETE, 1, clk::micros64());
}

}  // namespace

void fsmBegin() {
    g_state = FSM_IDLE;
    g_remaining = 0;
    g_responded = false;
    g_earlyResponse = false;
    g_lateResponse = false;
    g_winResponses = 0;
}

FsmState fsmState() {
    return g_state;
}

void fsmStartTrial() {
    uint32_t p = critEnter();

    dioAllOff();
    dioClearLatch();

    gI[PX_TRIAL_COMPLETE] = 0;
    gI[PX_IN_TRIAL] = 1;
    gI[PX_TRIG_STATE] = 1;
    gI[PX_TRIAL_NUM] = gI[PX_TRIAL_NUM] + 1;
    gI[PX_RESP_CODE] = 0;
    gF[PX_RESP_LATENCY] = -1.0f;   // -1 means "no response", not "0 ms"

    g_responded = false;
    g_earlyResponse = false;
    g_lateResponse = false;
    g_winResponses = 0;
    g_cueOnsetUs = 0;

    digitalWriteFast(PIN_STATUS_LED, HIGH);

    // A sync pulse at trial onset is what aligns this trial to the ephys
    // recording, so it is emitted before anything else can delay it.
    dioPulse(PIN_SYNC, gF[PX_SYNC_DUR]);

    uint64_t us = clk::micros64();
    g_events.push(PX_NEW_TRIAL, 1, us);

    enter(FSM_PRE_WINDOW, gF[PX_PRE_WINDOW_DUR]);

    critExit(p);
}

void fsmReset() {
    uint32_t p = critEnter();

    dioAllOff();
    dioClearLatch();

    g_state = FSM_IDLE;
    g_remaining = 0;
    g_responded = false;
    g_earlyResponse = false;
    g_lateResponse = false;
    g_winResponses = 0;

    gI[PX_TRIAL_COMPLETE] = 0;
    gI[PX_IN_TRIAL] = 0;
    gI[PX_TRIG_STATE] = 0;

    digitalWriteFast(PIN_STATUS_LED, LOW);

    g_events.clear();

    critExit(p);
}

void fsmOnResponseISR(uint64_t us) {
    switch (g_state) {
        case FSM_RESP_WINDOW:
            if (g_winResponses == 0) {
                // Latency is measured from cue onset, the stimulus the animal
                // is responding to, not from the response window opening.
                gF[PX_RESP_LATENCY] = (float)((double)(us - g_cueOnsetUs) / 1000.0);
            }
            g_winResponses++;
            if ((int32_t)g_winResponses >= gI[PX_RESP_THRESH]) {
                g_responded = true;
                // End the window immediately. Waiting out the remainder would
                // add up to RespWinDur to the reward latency and throw away
                // the timing precision this firmware exists to provide.
                g_remaining = 0;
            }
            break;

        case FSM_PRE_WINDOW:
        case FSM_CUE:
        case FSM_RESP_DELAY:
            g_earlyResponse = true;
            break;

        case FSM_POST_WINDOW:
            g_lateResponse = true;
            break;

        default:
            break;   // responses outside a trial are logged as events only
    }
}

void fsmTickISR() {
    if (g_state == FSM_IDLE) return;

    if (g_remaining > 0) {
        g_remaining--;
        return;
    }

    switch (g_state) {
        case FSM_PRE_WINDOW:
            g_cueOnsetUs = clk::micros64();
            if (gF[PX_CUE_DUR] > 0.0f) {
                dioPulse(PIN_CUE, gF[PX_CUE_DUR]);
            }
            g_events.push(PX_TRG_CUE, 1, g_cueOnsetUs);
            enter(FSM_CUE, gF[PX_CUE_DUR]);
            break;

        case FSM_CUE:
            enter(FSM_RESP_DELAY, gF[PX_RESP_WIN_DELAY]);
            break;

        case FSM_RESP_DELAY:
            enter(FSM_RESP_WINDOW, gF[PX_RESP_WIN_DUR]);
            break;

        case FSM_RESP_WINDOW:
            enter(FSM_POST_WINDOW, gF[PX_POST_WIN_DUR]);
            break;

        case FSM_POST_WINDOW:
            resolveOutcome();
            break;

        case FSM_TIMEOUT:
            digitalWriteFast(PIN_HOUSELIGHT, gI[PX_HOUSE_LIGHT] ? HIGH : LOW);
            enter(FSM_ITI, gF[PX_ITI_DUR]);
            break;

        case FSM_ITI:
            finishTrial();
            break;

        default:
            finishTrial();
            break;
    }
}
