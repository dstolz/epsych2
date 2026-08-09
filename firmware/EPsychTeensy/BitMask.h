// BitMask.h — mirrors epsych.BitMask so RespCode decodes on the host.
//
// epsych.BitMask stores 1-BASED bit indices, and
// epsych.BitMask.Bits2Mask builds a mask with
//     sum(bitshift(uint32(1), b - 1))
// so bit index b maps to (1u << (b - 1)) and Hit becomes 0x1, not 0x2. Getting
// that off by one silently shifts every outcome to its neighbour, which reads
// as a plausible-but-wrong psychometric curve rather than as an error.
//
// Keep this table in sync with obj/+epsych/@BitMask/BitMask.m.

#pragma once

#include <Arduino.h>

namespace bm {

enum Bit : uint8_t {
    Undefined          = 0,
    Hit                = 1,
    Miss               = 2,
    CorrectReject      = 3,
    FalseAlarm         = 4,
    Abort              = 5,
    Reward             = 6,
    Punish             = 7,
    PreResponseWindow  = 8,
    ResponseWindow     = 9,
    PostResponseWindow = 10,
    TrialType_0        = 11,   // TrialType_0..5 occupy bits 11..16
    Choice_0           = 17,   // Choice_0..5    occupy bits 17..22
    Option_A           = 23,   // Option_A..I    occupy bits 23..31
};

// Mask for a single bit index. Undefined (0) contributes nothing.
inline uint32_t of(uint8_t bitIndex) {
    if (bitIndex == 0 || bitIndex > 31) return 0;
    return (uint32_t)1 << (bitIndex - 1);
}

inline void set(uint32_t& mask, uint8_t bitIndex) {
    mask |= of(bitIndex);
}

// Mask for TrialType n (0..5).
inline uint32_t trialType(int32_t n) {
    if (n < 0 || n > 5) return 0;
    return of((uint8_t)(TrialType_0 + n));
}

}  // namespace bm
