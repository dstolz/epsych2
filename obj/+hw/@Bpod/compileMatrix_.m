function payload = compileMatrix_(obj)
% payload = compileMatrix_(obj)
% Encode the permuted state matrix in obj.lastMatrix_ into the uint8 payload
% that follows the 'P' opcode.
%
% PURE: struct in, bytes out, no I/O and no state mutation. That is the whole
% point of separating it from sendStateMatrix — it is what lets a test compare
% these bytes against a golden vector captured from Bpod's own
% SendStateMatrix on a real rig. See the verification note at the top of
% sendStateMatrix.m. Do not add a write, a read, or a property assignment
% here.
%
% Its input is obj.lastMatrix_ rather than an argument because the classdef
% pins the signature to (obj). sendStateMatrix stores the permuted matrix
% there immediately before calling this.
%
% Wire format, in the order the firmware reads it
% (Bpod_MainModule_0_6.ino:279-311):
%   [opcode 'P']            written by sendStateMatrix, NOT included here
%   nStates                 1 byte
%   InputStateMatrix        nStates x 40 bytes, ROW MAJOR
%   OutputStateMatrix       nStates x 17 bytes, ROW MAJOR
%   GlobalTimerMatrix       nStates x  5 bytes, ROW MAJOR
%   GlobalCounterMatrix     nStates x  5 bytes, ROW MAJOR
%   GlobalCounterEvents     5 bytes
%   PortInputsEnabled       8 bytes
%   WireInputsEnabled       4 bytes
%   StateTimers             nStates uint32, little-endian
%   GlobalTimers            5 uint32
%   GlobalCounterThresholds 5 uint32
%
% Three conversions are easy to get wrong and impossible to detect afterwards:
%   - BASE 0. Every transition matrix has 1 subtracted; the output matrix does
%     NOT (its columns hold values, not state indices).
%   - ROW MAJOR. MATLAB stores column major, so each transition and output
%     matrix is transposed before linearisation. The transpose is skipped for
%     a single-state matrix, where `1:end` on a row vector already yields a
%     row. Upstream's comment calls this inelegant; it is also load bearing.
%   - TICK SCALING. Timers are authored in seconds and transmitted as uint32
%     firmware ticks.
%
% Returns:
%   payload - 1 x N uint8, the bytes after the 'P' opcode.
%
% See also: hw.Bpod.sendStateMatrix, hw.Bpod.newStateMatrix

sma = obj.lastMatrix_;

if isempty(sma) || ~isstruct(sma)
    error('hw:Bpod:NoMatrixToCompile', ...
        'No state matrix to compile. sendStateMatrix stores one before calling compileMatrix_.');
end

nStates = sma.nStates;

% Cheap consistency check on the permutation sendStateMatrix performed. A
% mismatch means a state was referenced but never made it into the manifest,
% which would truncate every row of the upload.
if nStates ~= numel(sma.StateNames) || nStates ~= size(sma.InputMatrix, 1)
    error('hw:Bpod:MatrixShapeMismatch', ...
        ['State matrix is inconsistent: nStates = %d, %d state names, %d matrix ' ...
         'rows. The matrix was not permuted by sendStateMatrix.'], ...
        nStates, numel(sma.StateNames), size(sma.InputMatrix, 1));
end

%% Format input, output and wave matrices into linear byte vectors for transfer
% The nStates > 1 guard prevents 1:end from returning a column vector for one
% state (it returns a row for a matrix).
if nStates > 1
    RotMatrix = (sma.InputMatrix - 1)';  % subtract 1 to convert to c++ (base 0)
else
    RotMatrix = (sma.InputMatrix - 1);
end
InputMatrix = uint8(RotMatrix(1:end));

if nStates > 1
    RotMatrix = sma.OutputMatrix';       % values, not state indices: no -1
else
    RotMatrix = sma.OutputMatrix;
end
OutputMatrix = uint8(RotMatrix(1:end));

if nStates > 1
    RotMatrix = (sma.GlobalTimerMatrix - 1)';
else
    RotMatrix = (sma.GlobalTimerMatrix - 1);
end
GlobalTimerMatrix = uint8(RotMatrix(1:end));

if nStates > 1
    RotMatrix = (sma.GlobalCounterMatrix - 1)';
else
    RotMatrix = (sma.GlobalCounterMatrix - 1);
end
GlobalCounterMatrix = uint8(RotMatrix(1:end));

% 1-based index into EVENT_NAMES becomes the firmware's 0-based event code.
% The unattached sentinel 255 becomes 254, which is the value the firmware
% tests against (`GlobalCounterAttachedEvents[x] < 254`).
GlobalCounterAttachedEvents = uint8(sma.GlobalCounterEvents - 1);
GlobalCounterThresholds = uint32(sma.GlobalCounterThresholds);

%% Format timers (doubles in seconds) into 32 bit int vectors of firmware ticks
% Builds before 6 counted microseconds; 6 and later count 100 us ticks.
build = obj.FirmwareBuild;
if build == 0
    % Never handshook, so the build is unknown. Compiling offline (a golden
    % vector test, or a protocol built before connecting) must not silently
    % pick the pre-6 microsecond scaling and produce timers 100x too long.
    build = 6;
    vprintf(2, ['Bpod: firmware build unknown while compiling; assuming build %d ' ...
        'and %g tick/s scaling'], build, obj.TICK_HZ);
end
if build < 6
    TimeScaleFactor = 1000000;
else
    TimeScaleFactor = obj.TICK_HZ;
end

stateTicks = sma.StateTimers * TimeScaleFactor;
globalTicks = sma.GlobalTimers * TimeScaleFactor;

% uint32 saturates silently in both directions, turning an Inf or a negative
% timer into a state that never advances or one that expires instantly.
tickCeiling = double(intmax('uint32'));
if any(stateTicks < 0) || any(stateTicks > tickCeiling) ...
        || any(globalTicks < 0) || any(globalTicks > tickCeiling)
    vprintf(0, 1, ['Bpod: one or more timers fall outside the uint32 tick range ' ...
        '(0 to %g s at %g tick/s) and were CLAMPED. Check the state timers.'], ...
        tickCeiling / TimeScaleFactor, TimeScaleFactor);
end

StateTimers = uint32(stateTicks);
GlobalTimers = uint32(globalTicks);

%% Add input channel configuration
% Bpod reads this from BpodSystem.InputsEnabled; hw.Bpod carries it on the
% matrix. See newStateMatrix for why it defaults to all-enabled.
InputChannelConfig = uint8([sma.PortsEnabled sma.WiresEnabled]);

%% Create vectors of 8-bit and 32-bit data
EightBitMatrix = [uint8(nStates), InputMatrix, OutputMatrix, GlobalTimerMatrix, ...
    GlobalCounterMatrix, GlobalCounterAttachedEvents, InputChannelConfig];
ThirtyTwoBitMatrix = [StateTimers, GlobalTimers, GlobalCounterThresholds];

payload = [EightBitMatrix, typecast(ThirtyTwoBitMatrix, 'uint8')];

% The firmware reads a fixed count derived from nStates and blocks until it
% arrives, so a short payload wedges the device rather than failing loudly.
expected = 1 + nStates*(40 + 17 + 5 + 5) + 5 + 8 + 4 + 4*(nStates + 10);
if numel(payload) ~= expected
    error('hw:Bpod:PayloadLength', ...
        'Compiled payload is %d bytes; the firmware expects %d for %d states.', ...
        numel(payload), expected, nStates);
end

vprintf(3, 'Bpod: compiled a %d-state matrix into %d bytes', nStates, numel(payload));
end
