function abortMatrix(obj)
% abortMatrix(obj)
% Abort a running state matrix and drain the burst the firmware sends in reply.
%
% Draining is not optional. In the firmware the `if (MatrixFinished)` block sits
% OUTSIDE `if (RunningStateMatrix)`, so 'X' does not simply stop the machine: the
% same 100 us ISR pass still emits the full end-of-trial burst -
%
%   [1 1 255]            framed matrix-end sentinel
%   uint32 trialStartMs  epilogue header, little-endian
%   uint32 matrixStartUs
%   uint16 nEvents
%   uint32 x nEvents     event timestamps, in 100 us ticks
%
% - and 'X' also calls setStateOutputs(0) first, which can push an unsolicited
% [2 softCode] message ahead of the sentinel. Bytes left unread are parsed as
% opcodes at the start of the NEXT run and corrupt its first trial. That really
% does survive: epsych.Runtime.delete deliberately leaves interfaces connected
% for reuse, so the stale bytes outlive the session that produced them.
%
% The partial trial's timestamps are recovered when they arrive, so an aborted
% trial still reports the events it did collect. On a drain failure the input
% buffer is flushed, which is the only remaining way to protect the next run.
%
% Safe to call when nothing is running, when the epilogue is already in flight
% (the pump saw the sentinel but not the timestamps), and when offline.
%
% Parameters:
%   obj - hw.Bpod instance.
%
% See also: hw.Bpod.pump, hw.Bpod.sendStateMatrix, documentation/hw/hw_Bpod.md

wasRunning  = obj.matrixRunning_;
wasAwaiting = obj.awaitingEpilogue_;

% Offline: nothing on the wire to drain. Reached from delete() through
% close_interface, where the port may already be gone.
if ~obj.linkReady_ || isempty(obj.HW)
    local_clearRunState(obj);
    return
end

if ~wasRunning && ~wasAwaiting
    % Nothing in flight. Still clear the parser state: an earlier drain that
    % timed out can leave a partial message sitting in rxBuf_.
    local_clearRunState(obj);
    return
end

if wasRunning
    try
        obj.write_(uint8('X'));
        vprintf(2, 'Bpod: aborting the running state matrix');
    catch ME
        vprintf(0, 1, 'Bpod: could not send the abort command: %s', ME.message);
    end
end

[ts, drained] = local_drainEpilogue(obj, wasAwaiting);

if drained
    if ~isempty(ts)
        % Firmware timestamps count 100 us ticks from matrix start.
        obj.eventTimes_ = ts(:).' / obj.TICK_HZ;
        if numel(obj.eventCodes_) ~= numel(ts)
            % Legitimate past MAX_TIMESTAMPS: the device stops recording
            % timestamps at 10000 events but keeps reporting the events.
            vprintf(2, 'Bpod: aborted trial has %d event(s) but %d timestamp(s)', ...
                numel(obj.eventCodes_), numel(ts));
        end
    end
else
    vprintf(0, 1, ['Bpod: could not drain the state matrix epilogue after an abort. ' ...
        'Flushing the serial input so the leftover bytes cannot be read as opcodes ' ...
        'at the start of the next trial.']);
    try
        obj.flushInput_();
    catch ME
        vprintf(0, 1, ME);
    end
end

% The trial is over either way. Marking it complete keeps the runtime from
% waiting forever on an x_TrialComplete_ that the device will never raise.
obj.trialAborted_  = true;
obj.trialComplete_ = true;

local_clearRunState(obj);
local_forgetOutputRecord(obj);

end


function local_clearRunState(obj)
% local_clearRunState(obj)
% Drop every scrap of run and parser state.
obj.matrixRunning_     = false;
obj.awaitingEpilogue_  = false;
obj.pendingEventCount_ = 0;
obj.epiHdr_            = [];
obj.epilogueTic_       = [];
obj.rxBuf_             = uint8([]);
end


function local_forgetOutputRecord(obj)
% local_forgetOutputRecord(obj)
% Invalidate writeOutputs_'s last-written masks.
%
% 'X' runs the firmware's MatrixFinished block, which zeroes valves, PWM, BNC
% and wire. Anything on record about those lines is now wrong, so the next
% writeOutputs_ has to be unconditional. Mirrors local_forgetRecord in
% writeOutputs_.m; the two cannot share a helper because each method lives in
% its own file.
if isstruct(obj.inputCache_) && isfield(obj.inputCache_, 'lastOutputWrite_')
    obj.inputCache_ = rmfield(obj.inputCache_, 'lastOutputWrite_');
end
end


function [ts, ok] = local_drainEpilogue(obj, alreadyAwaiting)
% [ts, ok] = local_drainEpilogue(obj, alreadyAwaiting)
% Consume everything the device emits through the end of the epilogue.
%
% Parameters:
%   obj             - hw.Bpod instance.
%   alreadyAwaiting - true when the pump has already consumed the sentinel.
%
% Returns:
%   ts - Recovered timestamps in 100 us ticks. Empty when none were sent.
%   ok - True when the epilogue was fully consumed.

ts = [];
ok = false;

% Start from whatever the pump left unparsed; those bytes belong to this burst.
buf = uint8(obj.rxBuf_(:).');
obj.rxBuf_ = uint8([]);

deadline = tic;
budget = max(obj.Timeout, 0.25);

nTs = 0;
needSentinel = ~alreadyAwaiting;
needHeader = true;

if alreadyAwaiting && ~isempty(obj.epiHdr_)
    % The pump already read the header. It never consumes a partial message,
    % so the whole timestamp block is still on the wire.
    needHeader = false;
    nTs = local_pendingCount(obj);
    if nTs <= 0
        % The pump holds a header but no usable count, so how many timestamp
        % bytes are outstanding is unknown. Report failure and let the caller
        % flush rather than guess and leave a partial block behind.
        vprintf(0, 1, 'Bpod: epilogue header is parsed but its timestamp count is unreadable');
        return
    end
end

% --- Sentinel ------------------------------------------------------------
% Parse structurally rather than scanning for the [1 1 255] pattern: a real
% event message can contain those byte values as payload.
while needSentinel
    [buf, got] = local_ensure(obj, buf, 2, deadline, budget);
    if ~got
        return
    end

    switch buf(1)
        case 1  % framed event message: [1 nEvents ev...]
            n = double(buf(2));
            [buf, got] = local_ensure(obj, buf, 2 + n, deadline, budget);
            if ~got
                return
            end
            isEnd = n == 1 && buf(3) == 255;
            buf(1:2 + n) = [];
            if isEnd
                needSentinel = false;
            end

        case 2  % [2 softCode], pushed by setStateOutputs when a state emits one
            buf(1:2) = [];

        otherwise
            vprintf(2, 'Bpod: discarding byte %d while draining an aborted matrix', ...
                double(buf(1)));
            buf(1) = [];
    end
end

% --- Epilogue header -----------------------------------------------------
if needHeader
    [buf, got] = local_ensure(obj, buf, 10, deadline, budget);
    if ~got
        return
    end
    nTs = double(buf(9)) + 256 * double(buf(10));
    vprintf(2, 'Bpod: aborted trial started at %d ms with %d timestamp(s) to collect', ...
        double(typecast(uint8(buf(1:4)), 'uint32')), nTs);
    buf(1:10) = [];
end

nTs = max(0, min(nTs, obj.MAX_TIMESTAMPS));

% --- Timestamps ----------------------------------------------------------
if nTs > 0
    % 10000 timestamps is 40 kB, which needs several seconds of wire time on
    % its own. Allow for that on top of the per-transaction timeout.
    budget = budget + (4 * nTs) / (obj.BAUD_RATE / 10);

    [buf, got] = local_ensure(obj, buf, 4 * nTs, deadline, budget);
    if ~got
        return
    end
    ts = double(typecast(uint8(buf(1:4 * nTs)), 'uint32'));
    buf(1:4 * nTs) = [];
end

if ~isempty(buf)
    vprintf(2, 'Bpod: discarding %d trailing byte(s) after the epilogue', numel(buf));
end

ok = true;

end


function [buf, ok] = local_ensure(obj, buf, n, deadline, budget)
% [buf, ok] = local_ensure(obj, buf, n, deadline, budget)
% Read from the device until buf holds at least n bytes or the budget expires.
%
% Blocking reads happen in the transport, never in a pause loop: pause()
% services the event queue, which would let a timer tick re-enter the pump and
% steal the very bytes being drained here.
while numel(buf) < n
    remaining = budget - toc(deadline);
    if remaining <= 0
        vprintf(0, 1, 'Bpod: timed out with %d of %d epilogue byte(s) in hand', ...
            numel(buf), n);
        break
    end

    try
        chunk = obj.readExactly_(n - numel(buf), remaining);
    catch ME
        vprintf(0, 1, 'Bpod: transport error while draining the epilogue: %s', ME.message);
        break
    end

    if isempty(chunk)
        % readExactly_ has already waited out the time it was given.
        vprintf(0, 1, 'Bpod: the device stopped sending mid-epilogue');
        break
    end

    buf = [buf uint8(chunk(:).')];
end

ok = numel(buf) >= n;

end


function n = local_pendingCount(obj)
% n = local_pendingCount(obj)
% Timestamp count the pump recorded when it parsed the epilogue header.
n = 0;
if isnumeric(obj.pendingEventCount_) && isscalar(obj.pendingEventCount_) ...
        && isfinite(obj.pendingEventCount_) && obj.pendingEventCount_ > 0
    n = double(obj.pendingEventCount_);
    return
end

% Fall back to the header itself, whose third element is the event count.
if isnumeric(obj.epiHdr_) && numel(obj.epiHdr_) >= 3
    n = double(obj.epiHdr_(3));
end
end
