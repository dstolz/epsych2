// TrialFSM.h — the on-device trial state machine.
//
// This is what makes the board worth having. The whole trial — pre-window,
// cue, response window, contingency, reward delivery, timeout, ITI — runs in
// the scheduler ISR, so the interval between a lick and the valve opening is
// bounded by one tick (100 us) and owes nothing to MATLAB timer jitter, USB
// scheduling, or whatever else the host is doing.
//
// MATLAB's role is to configure the trial, pulse x_NewTrial_<N>, and poll
// x_TrialComplete_<N>. The handshake is deliberately the one epsych.Runtime
// already implements:
//
//   dispatchNextTrial: trigger(x_ResetTrig) -> k writes -> trigger(x_NewTrial)
//   every 10 ms tick:  read x_TrialComplete; nonzero -> read all results
//
// The device owns clearing TrialComplete. Nothing in MATLAB writes it back to
// zero; the only mechanism is the ResetTrig pulse at the FRONT of the next
// dispatch, which is why reset must come before the parameter writes.

#pragma once

#include <Arduino.h>

enum FsmState : uint8_t {
    FSM_IDLE = 0,
    FSM_PRE_WINDOW,
    FSM_CUE,
    FSM_RESP_DELAY,
    FSM_RESP_WINDOW,
    FSM_POST_WINDOW,
    FSM_TIMEOUT,
    FSM_ITI,
};

void fsmBegin();

// Advance the state machine one tick. Called from the scheduler ISR.
void fsmTickISR();

// Begin a trial. Invoked by the x_NewTrial_<N> trigger.
//
// Safe to call mid-trial: the operator "force trial" path in
// ep_TimerFcn_RunTime can dispatch a new trial without waiting for the current
// one to complete, so this restarts cleanly rather than corrupting state.
void fsmStartTrial();

// Abort any running trial and clear TrialComplete, the input latches, and the
// event queue. Invoked by the x_ResetTrig_<N> trigger.
void fsmReset();

// Record a debounced response edge. Called from the scheduler ISR.
void fsmOnResponseISR(uint64_t us);

FsmState fsmState();
