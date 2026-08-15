function pump_(obj)
% pump_(obj)
% Non-blocking replacement for Bpod's RunStateMatrix busy-wait.
%
% RunStateMatrix owns the trial: it writes 'R', then spins in
% `while BpodSystem.InStateMatrix` calling drawnow until the matrix ends. That
% is impossible inside a 10 ms timer callback, and it is also unnecessary --
% after 'R' the device is a PUSH STREAM that emits framed [1 nEvents ev...]
% messages unsolicited from its 100 us ISR. Nothing about the protocol requires
% the host to be blocked. This function is RunStateMatrix's loop BODY (event
% decoding, state walking, rollover correction, timestamp scaling) made
% resumable, with the loop itself replaced by the runtime's timer tick.
%
% Called from get.mode on every tick, from get_parameter, and from the public
% pump() escape hatch. It must therefore be cheap on the common path and must
% never throw: an exception here would kill the session timer with the device
% mid-trial and its valves still energized.
%
% Parsing is resumable. Bytes are appended to obj.rxBuf_ and consumed greedily
% from the FRONT, one complete message at a time; the instant a partial message
% is at the head the parser returns and waits for the next tick. A message
% split at any byte boundary therefore decodes identically to the same bytes
% arriving at once.
%
% Three internal notes for anyone editing this file:
%
%   1. While the matrix runs, obj.epiHdr_ does NOT hold an epilogue header. It
%      holds RunStateMatrix's StateChangeIndexes: entry k is the 1-based index
%      into obj.eventCodes_ of the first event of the message that entered
%      state k+1. The device sends no timestamps until the end-of-trial
%      epilogue, so the indices are all that is knowable during the trial, and
%      the classdef has no spare property for them. epiHdr_ was chosen over
%      obj.stateTimes_ precisely because get_parameter publishes stateTimes_ to
%      the outside world (StateTimes, State_<Name>) and nothing outside this
%      file reads epiHdr_: stateTimes_ therefore carries honest NaN until the
%      epilogue supplies real times, instead of briefly reporting array indices
%      as seconds. obj.pendingEventCount_ < 0 marks "header not read yet"; once
%      it is read, the three header values are appended to epiHdr_.
%
%   2. Ending a trial is NOT done here. Every path -- clean epilogue, epilogue
%      watchdog, matrix overrun, immediate-mode timeout, and abortMatrix's 'X'
%      -- calls obj.finalizeTrial_, which is the single publisher of the frozen
%      result set. Latching trialComplete_ locally instead is what left an
%      aborted trial reporting the PREVIOUS trial's results, Aborted included.
%
%   3. get_parameter serves most trial results by deriving them from the
%      record this file accumulates (stateCodes_, stateTimes_, eventCodes_,
%      eventTimes_, lastSoftCode_, trialAborted_, currentState_). The handful
%      that cannot be derived -- TrialStartTimestamp, TrialDuration_Actual,
%      RespCode, RespLatency, EventCountMismatch -- are published by
%      finalizeTrial_ as fields of obj.inputCache_ under exactly those names.
%      Anything that refreshes that cache must MERGE into it, never replace it
%      wholesale.
%
% Parameters:
%   obj - hw.Bpod instance to service.
%
% See also: hw.Bpod.pump, hw.Bpod.finalizeTrial_, hw.Bpod.get_parameter,
%           documentation/hw/hw_Bpod.md

% --- Re-entrancy guard ---------------------------------------------------
% get_parameter and the soft-code path can both re-enter through get.mode. A
% second parse of the same buffer would consume message halves out from under
% the first and desynchronize the trial.
if obj.pumping_
    return
end
obj.pumping_ = true;
pumpGuard = onCleanup(@() releasePump_(obj));

if ~obj.linkReady_
    return
end

% --- Immediate (no state matrix) mode ------------------------------------
% There is no device-side trial, so the host times it.
if ~obj.usesStateMatrix()
    try
        immediateModeTick_(obj);
    catch ME
        vprintf(0, 1, ME);
    end
    return
end

% --- Common path ---------------------------------------------------------
% Nothing in flight: this is what the timer hits on the vast majority of ticks
% and it must stay a handful of property reads. epilogueTic_ is included
% because abortMatrix() may clear matrixRunning_ while the device is still
% emitting its post-'X' sentinel and epilogue burst, which must be drained.
if ~(obj.matrixRunning_ || obj.awaitingEpilogue_ || ~isempty(obj.epilogueTic_))
    return
end

try
    n = obj.bytesAvailable_();
    if n > 0
        chunk = obj.readNow_(n);
        if ~isempty(chunk)
            obj.rxBuf_ = [obj.rxBuf_, uint8(reshape(chunk, 1, []))];
        end
    end

    parseStream_(obj);
    checkBacklog_(obj);
catch ME
    % Degrade, never throw: the watchdogs below still force-complete the trial
    % so the session cannot freeze at a trial boundary.
    vprintf(0, 1, ME);
    vprintf(0, 1, 'Bpod: byte pump failed while parsing the trial stream; the watchdog will close the trial.');
end

try
    watchdogs_(obj);
catch ME
    vprintf(0, 1, ME);
end

end


% =========================================================================
% Local helpers. obj is a handle, so these mutate the interface in place.
% Trailing-underscore names mark them as internal, matching the classdef.
% =========================================================================

function releasePump_(obj)
% releasePump_(obj)
% onCleanup target that releases the re-entrancy guard on every exit path,
% including an error escaping the try blocks above.
obj.pumping_ = false;
end


function parseStream_(obj)
% parseStream_(obj)
% Consume complete messages from the front of obj.rxBuf_.
%
% Phase A is the event stream; phase B is the end-of-trial epilogue. Work is
% bounded by MaxMessagesPerPump so one flooded trial cannot let a single timer
% tick starve the rest of the session.

buf = obj.rxBuf_;
pos = 1;
nbuf = numel(buf);
budget = max(1, round(obj.MaxMessagesPerPump));

while budget > 0
    % --- Phase B: epilogue ----------------------------------------------
    if obj.awaitingEpilogue_
        pos = parseEpilogue_(obj, buf, pos);
        % Either the epilogue is still incomplete (wait for more bytes) or the
        % trial has just been finalized. Nothing else belongs to this trial.
        break
    end

    % --- Phase A: event stream ------------------------------------------
    remaining = nbuf - pos + 1;
    if remaining < 2
        break   % partial message at the head
    end

    opCode = double(buf(pos));
    switch opCode
        case 1  % events
            nEvents = double(buf(pos + 1));
            if remaining < 2 + nEvents
                break   % partial message at the head
            end
            ev = double(buf(pos + 2 : pos + 1 + nEvents));
            pos = pos + 2 + nEvents;
            handleEventMessage_(obj, ev);

        case 2  % soft code emitted by a state's SoftCode output column
            obj.lastSoftCode_ = double(buf(pos + 1));
            pos = pos + 2;

        otherwise
            % Unreachable backstop. The only way a non-1/2 opcode reaches the
            % head of the stream is an 'I' reply that was issued while the
            % matrix was live -- a bare, unframed byte with no CRC, sequence
            % number or resync marker to recover from. readInput_'s interlock
            % exists to prevent exactly this.
            vprintf(0, 1, ['Bpod: opcode %d is not a valid stream message. The event stream is ' ...
                'desynchronized, almost certainly because an input read was issued while the ' ...
                'state matrix was running. Discarding the buffer and closing the trial.'], opCode);
            obj.flushInput_();
            obj.trialAborted_ = true;
            if isempty(obj.epilogueTic_)
                obj.epilogueTic_ = tic;   % hand the trial to the watchdog
            end
            pos = nbuf + 1;
            break
    end

    budget = budget - 1;

    if ~(obj.matrixRunning_ || obj.awaitingEpilogue_)
        break   % trial finished and finalized
    end
end

if pos > 1
    obj.rxBuf_ = buf(pos:end);
end

end


function handleEventMessage_(obj, ev)
% handleEventMessage_(obj, ev)
% Decode one [1 nEvents ev...] message and walk the state matrix.
%
% Ported from RunStateMatrix's `case 1` branch, minus the commander-GUI mirror.
%
% Parameters:
%   ev - Raw (0-based) event bytes from the message, as doubles.

% Bpod's convention: convert from the firmware's 0-based codes to MATLAB's
% 1-based event indices. 256 is the matrix-end sentinel.
e = ev + 1;

endIdx = find(e == 256, 1);
if ~isempty(endIdx)
    obj.matrixRunning_ = false;
    obj.awaitingEpilogue_ = true;
    obj.epilogueTic_ = tic;
    % Negative marks "epilogue header not read yet". epiHdr_ is left alone: it
    % is still carrying this trial's state-change indices, and the header is
    % appended to them when it arrives.
    obj.pendingEventCount_ = -1;
    % The firmware always sends the sentinel alone as [1 1 255]; keeping any
    % events ahead of it is defensive only.
    e = e(1:endIdx - 1);
    if isempty(e)
        return
    end
end

% The trial record is lazily seeded here so the pump is correct even though
% x_NewTrial_ only sets currentState_. RunStateMatrix starts the record at
% state 1, whose onset is the matrix start and is therefore known to be 0.
if isempty(obj.stateCodes_)
    obj.stateCodes_ = 1;
    obj.stateTimes_ = 0;
    obj.epiHdr_ = [];
    obj.currentState_ = 1;
end
if obj.currentState_ < 1
    obj.currentState_ = 1;
end

[inputMatrix, timerMatrix, counterMatrix] = transitionMatrices_(obj);
nTotalStates = numel(obj.StateNames);

if ~isempty(inputMatrix) && nTotalStates > 0 && obj.currentState_ <= size(inputMatrix, 1)
    currentState = obj.currentState_;
    newState = currentState;
    i = 1;
    while newState == currentState && i <= numel(e)
        thisEvent = e(i);
        if thisEvent >= 1 && thisEvent < 41
            if thisEvent <= size(inputMatrix, 2)
                newState = inputMatrix(currentState, thisEvent);
            end
        elseif thisEvent < 46
            if ~isempty(timerMatrix) && (thisEvent - 40) <= size(timerMatrix, 2)
                newState = timerMatrix(currentState, thisEvent - 40);
            end
        elseif thisEvent < 51
            if ~isempty(counterMatrix) && (thisEvent - 45) <= size(counterMatrix, 2)
                newState = counterMatrix(currentState, thisEvent - 45);
            end
        end
        i = i + 1;
    end

    if newState ~= currentState
        if newState <= nTotalStates
            % StateChangeIndexes: the index of the FIRST event of this message,
            % captured before the message's events are appended. Every event in
            % one firmware cycle shares a timestamp, so any of them would do.
            % See note 1 at the top of this file for why they live in epiHdr_.
            obj.epiHdr_(end + 1) = numel(obj.eventCodes_) + 1;
            obj.stateCodes_(end + 1) = newState;
            % No timestamp is knowable until the epilogue; NaN says so honestly
            % to anything that reads StateTimes or State_<Name> mid-trial.
            obj.stateTimes_(end + 1) = NaN;
            obj.currentState_ = newState;
        end
        % newState > nTotalStates is the exit state (nStates+1). The firmware
        % follows this message with the matrix-end sentinel, so there is
        % nothing to record here -- this mirrors RunStateMatrix's hardware path.
    end
elseif nTotalStates == 0 || isempty(inputMatrix)
    warnOnce_('nomatrix', 0, ['Bpod: events are arriving but no compiled state matrix is available, ' ...
        'so state transitions cannot be tracked. Event codes and timestamps are still recorded.']);
end

obj.eventCodes_ = [obj.eventCodes_, e];

end


function pos = parseEpilogue_(obj, buf, pos)
% pos = parseEpilogue_(obj, buf, pos)
% Consume the end-of-trial epilogue, resuming across ticks.
%
% Layout, immediately after the framed [1 1 255] sentinel:
%   uint32 trialStartMs   - matrix start, ms since the '6' handshake
%   uint32 matrixStartUs  - device clock at matrix start (0 on build >= 6)
%   uint16 nTimestamps    - clamped at MAX_TIMESTAMPS by the firmware
%   uint32 x nTimestamps  - one timestamp per recorded event
%
% All little-endian, and unframed: there is no sentinel to resync on, which is
% precisely why the epilogue watchdog is mandatory.

nbuf = numel(buf);

if obj.pendingEventCount_ < 0
    if nbuf - pos + 1 < 10
        return   % partial header at the head
    end
    raw = buf(pos:pos + 9);
    pos = pos + 10;
    % Appended behind the state-change indices already in epiHdr_; see note 1.
    obj.epiHdr_ = [obj.epiHdr_, ...
        double(typecast(raw(1:4), 'uint32')), ...
        double(typecast(raw(5:8), 'uint32')), ...
        double(typecast(raw(9:10), 'uint16'))];
    obj.pendingEventCount_ = obj.epiHdr_(end);
end

nBytesNeeded = 4 * obj.pendingEventCount_;
if nbuf - pos + 1 < nBytesNeeded
    return   % timestamps still arriving
end

if nBytesNeeded > 0
    timestamps = double(typecast(buf(pos:pos + nBytesNeeded - 1), 'uint32'));
else
    timestamps = zeros(1, 0);
end
pos = pos + nBytesNeeded;

obj.finalizeTrial_(timestamps, obj.epiHdr_(end - 2:end));

end


function [inputMatrix, timerMatrix, counterMatrix] = transitionMatrices_(obj)
% [inputMatrix, timerMatrix, counterMatrix] = transitionMatrices_(obj)
% Fetch the compiled transition matrices, tolerating an unsent matrix.
%
% These must be the POST-permutation matrices sendStateMatrix uploaded: 1-based
% manifest-ordered state indices aligned with obj.StateNames, with the exit
% state encoded as nStates+1.
inputMatrix = [];
timerMatrix = [];
counterMatrix = [];

sma = obj.lastMatrix_;
if ~isstruct(sma) || isempty(sma)
    return
end
if isfield(sma, 'InputMatrix')
    inputMatrix = sma.InputMatrix;
end
if isfield(sma, 'GlobalTimerMatrix')
    timerMatrix = sma.GlobalTimerMatrix;
end
if isfield(sma, 'GlobalCounterMatrix')
    counterMatrix = sma.GlobalCounterMatrix;
end
end


function watchdogs_(obj)
% watchdogs_(obj)
% Bound every way a trial can fail to end.
%
% These are not defensive decoration. The epilogue is length-prefixed but
% unframed, so a single lost byte leaves the parser waiting for timestamps that
% will never arrive, with x_TrialComplete_ stuck at 0 and the session frozen at
% a trial boundary -- no error, no log line, no trial advance. Both timeouts
% close the trial with Aborted = true instead.

% --- Matrix overrun: no exit state was ever reached ----------------------
% Issued once: a non-empty epilogueTic_ while the matrix runs means 'X' has
% already gone out and the drain deadline below now owns the trial.
if obj.matrixRunning_ && ~isempty(obj.trialTic_) && isempty(obj.epilogueTic_) ...
        && toc(obj.trialTic_) > obj.MaxTrialSeconds
    vprintf(0, 1, ['Bpod: the state matrix has run for %.1f s without reaching an exit state ' ...
        '(MaxTrialSeconds = %g). Aborting the matrix; check the trial''s exit conditions.'], ...
        toc(obj.trialTic_), obj.MaxTrialSeconds);
    obj.trialAborted_ = true;
    obj.epilogueTic_ = tic;
    % 'X' still produces the full sentinel + epilogue burst, because the
    % firmware's `if (MatrixFinished)` sits outside `if (RunningStateMatrix)`.
    % The parser stays in phase A and drains it exactly like a clean end.
    obj.abortMatrix();
    return
end

% --- Drain deadline: sentinel or epilogue never completed ----------------
if ~isempty(obj.epilogueTic_) && toc(obj.epilogueTic_) > obj.EpilogueTimeout
    vprintf(0, 1, ['Bpod: the end-of-trial epilogue did not complete within %g s ' ...
        '(%d of %d timestamp bytes received). The trial is being force-completed with ' ...
        'Aborted = true and the input buffer flushed; timestamps for this trial are lost.'], ...
        obj.EpilogueTimeout, numel(obj.rxBuf_), 4 * max(0, obj.pendingEventCount_));
    obj.trialAborted_ = true;
    obj.flushInput_();
    obj.rxBuf_ = uint8([]);
    obj.finalizeTrial_([], []);
end

end


function immediateModeTick_(obj)
% immediateModeTick_(obj)
% Host-timed trial completion for immediate I/O mode.
%
% With no StateMatrixFcn there is no device-side trial at all: the behavior GUI or
% custom code drives the hardware directly and the host decides when the trial
% is over, from the TrialDuration parameter.
if obj.trialComplete_ || isempty(obj.trialTic_)
    return
end

elapsed = toc(obj.trialTic_);

if elapsed > obj.MaxTrialSeconds
    vprintf(0, 1, ['Bpod: immediate-mode trial has run %.1f s (MaxTrialSeconds = %g) without ' ...
        'completing. Force-completing with Aborted = true.'], elapsed, obj.MaxTrialSeconds);
    obj.trialAborted_ = true;
    obj.finalizeTrial_([], []);
    return
end

duration = trialDurationSeconds_(obj);
if isfinite(duration) && elapsed >= duration
    obj.finalizeTrial_([], []);
end
end


function duration = trialDurationSeconds_(obj)
% duration = trialDurationSeconds_(obj)
% Read the configured immediate-mode trial duration, in seconds.
%
% Only a WRITABLE parameter counts. hw.Bpod also publishes a read-only
% 'TrialDuration' result carrying the host-measured elapsed time of the trial
% in progress, and timing a trial against that would compare elapsed time with
% itself. Access is what separates trial configuration (Visible, Access ~=
% 'Read') from a trial result (Visible, Access == 'Read').
%
% Values are seconds unless the parameter declares a millisecond unit.
%
% Returns Inf when no configured duration exists, which leaves the trial to a
% custom GUI, a TrialSelector, or FORCE_TRIAL -- the host-owned timing that
% immediate mode is for -- with the MaxTrialSeconds watchdog as the backstop.
% Inventing a duration here would end trials early and silently.
duration = inf;

CANDIDATES = {'ImmediateTrialDuration', 'TrialDuration'};

P = [];
for i = 1:numel(CANDIDATES)
    found = obj.find_parameter(CANDIDATES{i}, includeInvisible = true, ...
        silenceParameterNotFound = true);
    for k = 1:numel(found)
        if ~strcmp(found(k).Access, 'Read')
            P = found(k);
            break
        end
    end
    if ~isempty(P)
        break
    end
end

if isempty(P)
    warnOnce_('notrialduration', 2, ['Bpod: immediate mode found no writable trial-duration ' ...
        'parameter (ImmediateTrialDuration or TrialDuration), so trial completion is left to ' ...
        'the host and bounded only by MaxTrialSeconds.']);
    return
end

% Read the parameter's STORED value, not the interface's answer for it.
% hw.Parameter.get.Value short-circuits to its own stored value whenever the
% owning interface reports disconnected, which is the same trick
% get_parameter's storedValue_ uses to avoid recursing. Two reasons to take it
% here: the stored value is authoritative for configuration (dispatchNextTrial
% wrote it through set.Value before the trial started), and it keeps this read
% independent of how get_parameter happens to dispatch the name -- a read that
% resolved to the trial's *elapsed* time would compare elapsed with itself and
% the trial would never end.
wasReady = obj.linkReady_;
obj.linkReady_ = false;
try
    value = P.Value;
catch ME
    value = [];
    vprintf(0, 1, ME);
end
obj.linkReady_ = wasReady;

if ~isnumeric(value) || isempty(value) || ~isfinite(value(1))
    return
end
duration = double(value(1));

if any(strcmpi(P.Unit, {'ms', 'msec', 'milliseconds'}))
    duration = duration / 1000;
end
end


function checkBacklog_(obj)
% checkBacklog_(obj)
% Report a pump that is falling behind the device.
%
% A starved pump degrades gracefully -- messages simply parse a tick later --
% which is exactly what makes it invisible. One log line makes it diagnosable.
% The epilogue is excluded: a 10000-event trial legitimately queues 40 kB there.
persistent backlogReported
if isempty(backlogReported)
    backlogReported = false;
end

HIGH_WATER_BYTES = 4096;   % ~340 event messages; a full tick's worth is a few

if obj.awaitingEpilogue_
    return
end

pending = numel(obj.rxBuf_);
if pending > HIGH_WATER_BYTES
    if ~backlogReported
        vprintf(1, ['Bpod: %d bytes of unparsed event stream are queued. The pump is not keeping ' ...
            'up with the device; consider raising MaxMessagesPerPump (now %g) or shortening the ' ...
            'session timer period.'], pending, obj.MaxMessagesPerPump);
        backlogReported = true;
    end
elseif pending < HIGH_WATER_BYTES / 2
    backlogReported = false;
end
end


function warnOnce_(key, level, msg)
% warnOnce_(key, level, msg)
% Emit a message once per key per MATLAB session.
%
% These conditions persist for every message of every trial, and logging them
% per tick would bury the rest of the session log. hw.Bpod is single-instance
% by design (prepareRecording rejects multi-subject sessions), so a persistent
% latch is safe here.
persistent reported
if isempty(reported)
    reported = {};
end
if any(strcmp(reported, key))
    return
end
reported{end + 1} = key;
if level == 0
    vprintf(0, 1, msg);
else
    vprintf(level, msg);
end
end
