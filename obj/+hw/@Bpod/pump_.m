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
%   2. The result set published to obj.inputCache_ is deliberately
%      matrix-INDEPENDENT (no per-state fields). A mid-session operator
%      recompile can change obj.StateNames, and a result field set derived from
%      it would change with it, which is exactly what makes
%      `RUNTIME.TRIALS(i).DATA(k) = data` throw "Subscripted assignment between
%      dissimilar structures". Per-state onsets stay available through
%      get_parameter's State_<Name> parameters, which read the record directly.
%
%   3. get_parameter serves most trial results by deriving them from the
%      record this file latches (stateCodes_, stateTimes_, eventCodes_,
%      eventTimes_, lastSoftCode_, trialAborted_, currentState_). The handful
%      that cannot be derived -- TrialStartTimestamp, TrialDuration_Actual,
%      RespCode, RespLatency, EventCountMismatch -- are published as fields of
%      obj.inputCache_ under exactly those names. Anything that refreshes that
%      cache must MERGE into it, never replace it wholesale.
%
% Parameters:
%   obj - hw.Bpod instance to service.
%
% See also: hw.Bpod.pump, hw.Bpod.get_parameter, documentation/hw/hw_Bpod.md

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

finalizeTrial_(obj, timestamps, obj.epiHdr_(end - 2:end));

end


function finalizeTrial_(obj, timestamps, hdr)
% finalizeTrial_(obj, timestamps, hdr)
% Close the trial: scale timestamps, build the frozen result set, latch
% x_TrialComplete_.
%
% Parameters:
%   timestamps - Raw device timestamps as doubles, or [] when no epilogue was
%                received (watchdog, desync, or host-timed immediate mode).
%   hdr        - [trialStartMs matrixStartUs nTimestamps], or [] as above.

% State-change indexes, taken by count rather than by "everything in epiHdr_",
% so this is correct whether or not the epilogue header has been appended
% behind them (see note 1 at the top of this file).
nStates = numel(obj.stateCodes_);
nChanges = min(max(0, nStates - 1), numel(obj.epiHdr_));
changeIndexes = obj.epiHdr_(1:nChanges);
countMismatch = false;

if isempty(hdr)
    % No device timing available. Keep the arrays parallel with NaN so a
    % consumer cannot silently pair an event with the wrong timestamp.
    trialStart = NaN;
    eventTimes = nan(1, numel(obj.eventCodes_));
else
    trialStartMs  = hdr(1);
    matrixStartUs = hdr(2);
    nTimestampsHdr = hdr(3);

    % 32-bit clock rollover, applied exactly as RunStateMatrix applies it:
    % anything earlier than the matrix start belongs to the next epoch. This is
    % a no-op on build >= 6, where the device restarts its tick counter at 0
    % for every matrix, but firmware < 6 timestamps free-running micros().
    if ~isempty(timestamps) && timestamps(end) < matrixStartUs
        postRollOver = timestamps < matrixStartUs;
        timestamps(postRollOver) = timestamps(postRollOver) + 4294967295;
    end

    if obj.FirmwareBuild < 6
        timeScaleFactor = 1000;   % device clock counts microseconds
    else
        timeScaleFactor = 10;     % device clock counts 100 us ticks
    end

    timestampsMillis = timestamps / timeScaleFactor;
    trialStartMillis = matrixStartUs / 1000;
    eventTimes = round2Millis_(timestampsMillis - trialStartMillis) / 1000;
    trialStart = round2Millis_(trialStartMs / 1000);

    % The firmware stops recording timestamps past MAX_TIMESTAMPS while the
    % state machine keeps running and keeps streaming events, so a disagreement
    % is expected on very long or very noisy trials -- and is also what a lost
    % byte looks like. Flag the trial, never throw.
    countMismatch = numel(obj.eventCodes_) ~= nTimestampsHdr;
    if countMismatch
        vprintf(0, 1, ['Bpod: %d events were streamed but the device reported %d timestamps. ' ...
            'Either the trial exceeded the firmware''s %d timestamp limit or bytes were lost; ' ...
            'EventTimestamps is padded with NaN and EventCountMismatch is set for this trial.'], ...
            numel(obj.eventCodes_), nTimestampsHdr, obj.MAX_TIMESTAMPS);
    end
end

% Keep EventCodes and EventTimestamps index-aligned.
nPad = numel(obj.eventCodes_) - numel(eventTimes);
if nPad > 0
    eventTimes = [eventTimes, nan(1, nPad)];
end

% State onsets, from RunStateMatrix: entry 1 is the trial start, entry k is the
% timestamp of the event that entered state k, and one extra entry closes the
% final state at the last event.
stateTimes = nan(1, nStates);
if nStates > 0
    stateTimes(1) = 0;
end
for k = 2:nStates
    if (k - 1) <= numel(changeIndexes)
        idx = changeIndexes(k - 1);
        if idx >= 1 && idx <= numel(eventTimes)
            stateTimes(k) = eventTimes(idx);
        end
    end
end
if ~isempty(eventTimes)
    stateTimes(end + 1) = eventTimes(end);
else
    stateTimes(end + 1) = NaN;
end

obj.eventTimes_ = eventTimes;
obj.stateTimes_ = stateTimes;

% Trial duration: prefer the device's own closing timestamp, fall back to the
% host clock (which is all the watchdog and immediate-mode paths have).
trialDuration = NaN;
if ~isempty(stateTimes) && isfinite(stateTimes(end))
    trialDuration = stateTimes(end);
elseif ~isempty(obj.trialTic_)
    trialDuration = toc(obj.trialTic_);
end

lastStateCode = NaN;
lastStateName = 'None';
if nStates > 0
    lastStateCode = obj.stateCodes_(end);
    % Resolve names ONLY from obj.StateNames: event-stream state indices refer
    % to the post-compile manifest order that sendStateMatrix permuted the
    % matrix into, not to declaration order.
    if lastStateCode >= 1 && lastStateCode <= numel(obj.StateNames)
        lastStateName = obj.StateNames{lastStateCode};
    end
end

[respCode, respLatency] = resolveResponse_(obj, stateTimes);

% --- Frozen result set ---------------------------------------------------
R = resultDefaults_();
R.TrialStartTimestamp  = trialStart;
R.TrialDuration_Actual = trialDuration;
R.nStatesVisited       = nStates;
R.LastStateCode        = lastStateCode;
R.LastStateName        = lastStateName;
R.LastSoftCode         = obj.lastSoftCode_;
R.Aborted              = obj.trialAborted_;
R.RespCode             = respCode;
R.RespLatency          = respLatency;
R.EventCountMismatch   = countMismatch;
R.StateCodes           = obj.stateCodes_;
R.StateTimestamps      = obj.stateTimes_;
R.EventCodes           = obj.eventCodes_;
R.EventTimestamps      = obj.eventTimes_;

names = fieldnames(R);
for k = 1:numel(names)
    obj.inputCache_.(names{k}) = R.(names{k});
end

% --- Latch and clear the parser -----------------------------------------
obj.matrixRunning_    = false;
obj.awaitingEpilogue_ = false;
obj.epiHdr_           = [];
obj.pendingEventCount_ = 0;
obj.epilogueTic_      = [];
obj.trialComplete_    = true;

vprintf(2, 'Bpod: trial closed after %d states and %d events (%.3f s, last state "%s", aborted = %d)', ...
    nStates, numel(obj.eventCodes_), trialDuration, lastStateName, obj.trialAborted_);

end


function R = resultDefaults_()
% R = resultDefaults_()
% The frozen readable result set, with every field present.
%
% Every finalize path starts from this struct so the field set is identical on
% every trial no matter which path closed it. A field that appears on some
% trials and not others makes `RUNTIME.TRIALS(i).DATA(k) = data` throw
% "Subscripted assignment between dissimilar structures" and takes the whole
% session down at a trial boundary.
R = struct( ...
    'TrialStartTimestamp',  NaN, ...
    'TrialDuration_Actual', NaN, ...
    'nStatesVisited',       0, ...
    'LastStateCode',        NaN, ...
    'LastStateName',        'None', ...
    'LastSoftCode',         0, ...
    'Aborted',              false, ...
    'RespCode',             0, ...
    'RespLatency',          NaN, ...
    'EventCountMismatch',   false, ...
    'StateCodes',           zeros(1, 0), ...
    'StateTimestamps',      zeros(1, 0), ...
    'EventCodes',           zeros(1, 0), ...
    'EventTimestamps',      zeros(1, 0));
end


function [respCode, respLatency] = resolveResponse_(obj, stateTimes)
% [respCode, respLatency] = resolveResponse_(obj, stateTimes)
% Derive the epsych.BitMask response mask and the response latency.
%
% Outcome information comes from the state matrix builder when it supplies it,
% and from state names otherwise:
%   1. sma.OutcomeMask  - numeric uint32 mask per manifest state
%   2. sma.OutcomeTags  - epsych.BitMask member name per manifest state
%   3. state names       - a visited state named (or containing) Hit, Miss,
%                          CorrectReject, FalseAlarm, Abort, Reward or Punish
% With none of the three the mask is 0 (Undefined), which psychophysics code
% treats as "no flags" -- deliberately, because guessing here would silently
% mis-score trials rather than leave a visible gap.

respCode = 0;
respLatency = NaN;

bits = [];
outcomeStateIdx = [];
[outcomeMask, outcomeTags] = outcomeAnnotations_(obj);

for k = 1:numel(obj.stateCodes_)
    stateCode = obj.stateCodes_(k);
    hasOutcome = false;

    if ~isempty(outcomeMask) && stateCode >= 1 && stateCode <= numel(outcomeMask) ...
            && outcomeMask(stateCode) > 0
        % An explicit mask is authoritative: fold it in whole.
        respCode = double(bitor(uint32(respCode), uint32(outcomeMask(stateCode))));
        hasOutcome = true;
    else
        label = '';
        if ~isempty(outcomeTags) && stateCode >= 1 && stateCode <= numel(outcomeTags)
            label = outcomeTags{stateCode};
        end
        if isempty(label) && stateCode >= 1 && stateCode <= numel(obj.StateNames)
            label = obj.StateNames{stateCode};
        end
        theseBits = bitsFromLabel_(label);
        if ~isempty(theseBits)
            bits = [bits, theseBits];
            hasOutcome = true;
        end
    end

    if hasOutcome && isempty(outcomeStateIdx)
        outcomeStateIdx = k;
    end
end

if obj.trialAborted_
    bits = [bits, double(epsych.BitMask.Abort)];
end

bits = unique(bits(bits > 0));
if ~isempty(bits)
    respCode = double(bitor(uint32(respCode), epsych.BitMask.Bits2Mask(bits)));
end

% Latency: when an outcome state is identifiable, the moment the trial entered
% it; otherwise the first port, BNC or wire event (codes 1-28), which excludes
% the state timer (Tup) and host-injected soft codes.
if ~isempty(outcomeStateIdx) && outcomeStateIdx <= numel(stateTimes)
    respLatency = stateTimes(outcomeStateIdx);
else
    inputIdx = find(obj.eventCodes_ >= 1 & obj.eventCodes_ <= 28, 1);
    if ~isempty(inputIdx) && inputIdx <= numel(obj.eventTimes_)
        respLatency = obj.eventTimes_(inputIdx);
    end
end

end


function bits = bitsFromLabel_(label)
% bits = bitsFromLabel_(label)
% Map a state name or outcome tag onto epsych.BitMask bit indices.
%
% An exact (case-insensitive) match against any enumeration member wins.
% Failing that, only the outcome and contingency flags are matched as
% substrings, so a state called "Choice_1_Delay" cannot be read as a trial-type
% flag while "DeliverReward" still scores as Reward.
bits = [];
if isempty(label)
    return
end
label = char(label);

[members, names] = enumeration('epsych.BitMask');
hit = find(strcmpi(names, label), 1);
if ~isempty(hit)
    value = double(members(hit));
    if value > 0
        bits = value;
    end
    return
end

candidates = {'CorrectReject', 'FalseAlarm', 'Hit', 'Miss', 'Abort', 'Reward', 'Punish'};
for i = 1:numel(candidates)
    if contains(label, candidates{i}, IgnoreCase = true)
        bits(end + 1) = double(epsych.BitMask.(candidates{i}));
    end
end
end


function [outcomeMask, outcomeTags] = outcomeAnnotations_(obj)
% [outcomeMask, outcomeTags] = outcomeAnnotations_(obj)
% Read whatever outcome annotation the compiled matrix carries.
%
% Both are indexed by manifest order, i.e. aligned with obj.StateNames, because
% that is the ordering the event stream's state indices refer to. Missing
% annotations return empty and the caller falls back to state names.
outcomeMask = [];
outcomeTags = {};

sma = obj.lastMatrix_;
if ~isstruct(sma) || isempty(sma)
    return
end

if isfield(sma, 'OutcomeMask') && isnumeric(sma.OutcomeMask)
    outcomeMask = double(sma.OutcomeMask(:)');
end

if isfield(sma, 'OutcomeTags') && iscell(sma.OutcomeTags)
    outcomeTags = sma.OutcomeTags(:)';
elseif isfield(sma, 'StateTags') && iscell(sma.StateTags)
    outcomeTags = sma.StateTags(:)';
end
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
    finalizeTrial_(obj, [], []);
end

end


function immediateModeTick_(obj)
% immediateModeTick_(obj)
% Host-timed trial completion for immediate I/O mode.
%
% With no StateMatrixFcn there is no device-side trial at all: the box GUI or
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
    finalizeTrial_(obj, [], []);
    return
end

duration = trialDurationSeconds_(obj);
if isfinite(duration) && elapsed >= duration
    finalizeTrial_(obj, [], []);
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

% Safe to read through the parameter: the re-entrancy guard is held, so the
% get_parameter this triggers cannot recurse back into the parser.
value = P.Value;
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


function value = round2Millis_(value)
% value = round2Millis_(value)
% Round to the millisecond, matching RunStateMatrix's Round2Millis. Keeps
% saved timestamps free of the float noise that 100 us ticks divided by 10
% would otherwise leave in every record.
value = round(value * 1000) / 1000;
end
