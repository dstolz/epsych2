function finalizeTrial_(obj, timestamps, hdr)
% finalizeTrial_(obj, timestamps, hdr)
% Close the trial: scale timestamps, build the frozen result set, latch
% x_TrialComplete_.
%
% This is a method rather than a local function in pump_.m because it is the
% SINGLE place the frozen result set is published to obj.inputCache_, and both
% pump_ (clean end, epilogue watchdog, immediate mode) and abortMatrix ('X')
% have to end a trial. A second copy of the result vocabulary has already caused
% one silent data-corruption defect here -- an aborted trial that left the
% PREVIOUS trial's results in the cache, recording Aborted = false -- so every
% path that ends a trial must land in this function.
%
% Callers must set obj.trialAborted_ BEFORE calling: it is read here into the
% published Aborted field and folded into RespCode as epsych.BitMask.Abort.
%
% Parameters:
%   obj        - hw.Bpod instance.
%   timestamps - Raw device timestamps as doubles, or [] when no epilogue was
%                received (watchdog, desync, or host-timed immediate mode).
%   hdr        - [trialStartMs matrixStartUs nTimestamps], or [] as above.
%
% See also: hw.Bpod.pump, hw.Bpod.abortMatrix, hw.Bpod.get_parameter,
%           documentation/hw/hw_Bpod.md

% State-change indexes, taken by count rather than by "everything in epiHdr_",
% so this is correct whether or not the epilogue header has been appended
% behind them (see note 1 at the top of pump_.m).
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


% =========================================================================
% Local helpers. Every one of these is used only to build the frozen result
% set, so they travelled here with finalizeTrial_ rather than staying behind
% in pump_.m.
% =========================================================================

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


function value = round2Millis_(value)
% value = round2Millis_(value)
% Round to the millisecond, matching RunStateMatrix's Round2Millis. Keeps
% saved timestamps free of the float noise that 100 us ticks divided by 10
% would otherwise leave in every record.
value = round(value * 1000) / 1000;
end
