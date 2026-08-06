// EventQueue.h — single-producer / single-consumer ring of timestamped events.
//
// Produced in the scheduler ISR, consumed in loop() when the host sends EVT?.
// That split is the whole point: an input edge is stamped with microsecond
// resolution the instant it happens, and delivery to MATLAB can lag by a
// timer tick without costing any timing precision.
//
// Lock-free by construction. The producer only advances head_, the consumer
// only advances tail_, and both are volatile single words, so neither needs a
// critical section on a 32-bit MCU.

#pragma once

#include <Arduino.h>
#include "Config.h"
#include "Critical.h"

struct Event {
    uint64_t us;      // clk::micros64() at the edge
    uint8_t  param;   // index into PARAMS
    int32_t  value;   // new value
};

class EventQueue {
public:
    void begin() {
        head_ = 0;
        tail_ = 0;
        overflowed_ = false;
    }

    // Append an event. Called from the ISR.
    //
    // A full queue drops the OLDEST event, not the newest. When a queue backs
    // up it is because the host stopped draining, and in that situation the
    // recent past explains the current state far better than a stale prefix
    // does. The drop is flagged so SNAP can report it rather than hide it.
    void push(uint8_t param, int32_t value, uint64_t us) {
        uint32_t next = advance_(head_);
        if (next == tail_) {
            tail_ = advance_(tail_);
            overflowed_ = true;
        }
        buf_[head_].us    = us;
        buf_[head_].param = param;
        buf_[head_].value = value;
        head_ = next;
    }

    bool pop(Event& out) {
        if (tail_ == head_) return false;
        uint32_t p = critEnter();
        out = buf_[tail_];
        tail_ = advance_(tail_);
        critExit(p);
        return true;
    }

    uint32_t count() const {
        uint32_t h = head_, t = tail_;
        return (h >= t) ? (h - t) : (EVENT_QUEUE_LEN - t + h);
    }

    bool overflowed() const { return overflowed_; }

    void clear() {
        uint32_t p = critEnter();
        tail_ = head_;
        overflowed_ = false;
        critExit(p);
    }

private:
    static uint32_t advance_(uint32_t i) {
        return (i + 1) % EVENT_QUEUE_LEN;
    }

    Event buf_[EVENT_QUEUE_LEN];
    volatile uint32_t head_ = 0;
    volatile uint32_t tail_ = 0;
    volatile bool overflowed_ = false;
};

extern EventQueue g_events;
