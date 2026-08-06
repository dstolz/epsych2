function value = get_parameter(obj, name, options)
% value = get_parameter(obj, name)
% value = get_parameter(obj, name, includeInvisible=true)
% Read one or more parameters, preserving the requested order.
%
% Nothing here talks to the device except an input line read, and even that
% is served from a short-lived cache and is interlocked against a running
% state matrix. Outputs come from the local shadow and trial results come
% from the record the byte pump latched, so a full trial-end sweep over
% every readable parameter costs zero round trips.
%
% This is one of only two entry points the runtime guarantees on every 10 ms
% tick (the other is get.mode), so it also drives the byte pump. It must
% never block.
%
% Parameters
%   name - Parameter name(s), or hw.Parameter handle(s).
%
% Name=Value
%   includeInvisible (logical)          - Include hidden parameters when
%                                         resolving names. Default false.
%   silenceParameterNotFound (logical)  - Suppress the not-found warning.
%                                         Default false.
%
% Returns:
%   value - Value, or a cell array of values for multiple names.
%
% See also: hw.Bpod.set_parameter, hw.Bpod.pump, documentation/hw/hw_Bpod.md

arguments
    obj
    name
    options.includeInvisible (1,1) logical = false
    options.silenceParameterNotFound (1,1) logical = false
end

% The device is a push stream once a matrix is running, so the parser has to
% be serviced from whatever the runtime calls often. ep_TimerFcn_RunTime
% polls x_TrialComplete_ through here on every tick; that is the hook.
obj.pump();

if isa(name, 'hw.Parameter')
    P = name;
    name = {P.Name};
else
    if ischar(name) || isstring(name)
        name = cellstr(name);
    end
    P = obj.find_parameter(name, ...
        includeInvisible = options.includeInvisible, ...
        silenceParameterNotFound = options.silenceParameterNotFound);
end

if isempty(P)
    value = [];
    return
end

value = cell(size(P));

if ~obj.IsConnected
    % Offline reads are benign: hw.Parameter.get.Value short-circuits to its
    % own stored value when the owning interface reports disconnected, so
    % reading it back here cannot recurse. This is the path ProtocolDesigner
    % and trial preview take with no board attached.
    for i = 1:numel(P)
        value{i} = P(i).Value;
    end
else
    for i = 1:numel(P)
        value{i} = readOne_(obj, P(i));
    end
end

% Restore the caller's requested order. find_parameter drops names it could
% not resolve, so idx can contain zeros; they are removed rather than used.
[~, idx] = ismember(name, {P.Name});
idx(idx == 0) = [];
if numel(idx) == numel(value)
    value = value(idx);
end

if isscalar(value)
    value = value{1};
end
end


% ------------------------------------------------------------------------
function v = readOne_(obj, P)
% v = readOne_(obj, P)
% Serve one parameter from the shadow, the input cache, or the trial record.
%
% An unrecognized name is not an error: parameters the operator adds to the
% Bpod module in ProtocolDesigner are host-side trial configuration consumed
% by the state matrix builder, and they legitimately have no device home.

wire = hw.Interface.getHardwareParameterName(P);
[kind, idx] = decodeName_(wire);

switch kind
    case 'complete'
        % Polled every tick by ep_TimerFcn_RunTime. Latched by the pump when
        % the matrix-end sentinel and its epilogue have both been consumed.
        v = double(obj.trialComplete_);

    case 'portin'
        % readInput_ owns both the SnapshotInterval cache and the 'I'
        % interlock: while matrixRunning_ or awaitingEpilogue_ it returns the
        % cached value and issues no serial traffic, because the bare reply
        % byte would be parsed as an event opcode and desynchronize the
        % trial. It also applies the INPUT_PULLUP inversion, so 1 here means
        % the beam is broken.
        v = obj.readInput_('P', idx);

    case 'bncin'
        v = obj.readInput_('B', idx);

    case 'wirein'
        v = obj.readInput_('W', idx);

    % Outputs are served from the absolute local shadow. The host is the
    % only writer between trials and the firmware never reports output
    % state back, so a round trip would buy nothing.
    case 'valve'
        v = obj.valves_(idx);

    case 'pwm'
        v = obj.pwm_(idx);

    case 'bncout'
        v = obj.bncOut_(idx);

    case 'wireout'
        v = obj.wireOut_(idx);

    case 'serialbyte'
        % Momentary: the byte is handed to the module and nothing is
        % retained, so there is no meaningful value to report.
        v = nan;

    case 'state'
        v = stateEntryTime_(obj, wire(7:end));

    case 'event'
        v = eventTime_(obj, wire(7:end));

    case 'result'
        v = resultValue_(obj, wire);

    otherwise
        v = storedValue_(obj, P);
end
end


% ------------------------------------------------------------------------
function [kind, idx] = decodeName_(wire)
% [kind, idx] = decodeName_(wire)
% Classify a wire name into a Bpod parameter family and channel number.
%
% kind is '' when the name belongs to no family. Tests are ordered by how
% often they are hit, because the trial-completion poll runs on every tick.

kind = '';
idx  = 0;

if strncmp(wire, 'x_TrialComplete_', 16)
    kind = 'complete';
    return
end

tok = regexp(wire, '^Port([1-8])In$', 'tokens', 'once');
if ~isempty(tok), kind = 'portin'; idx = str2double(tok{1}); return, end

tok = regexp(wire, '^BNCIn([1-2])$', 'tokens', 'once');
if ~isempty(tok), kind = 'bncin'; idx = str2double(tok{1}); return, end

tok = regexp(wire, '^WireIn([1-4])$', 'tokens', 'once');
if ~isempty(tok), kind = 'wirein'; idx = str2double(tok{1}); return, end

tok = regexp(wire, '^Valve([1-8])$', 'tokens', 'once');
if ~isempty(tok), kind = 'valve'; idx = str2double(tok{1}); return, end

tok = regexp(wire, '^PWM([1-8])$', 'tokens', 'once');
if ~isempty(tok), kind = 'pwm'; idx = str2double(tok{1}); return, end

tok = regexp(wire, '^BNCOut([1-2])$', 'tokens', 'once');
if ~isempty(tok), kind = 'bncout'; idx = str2double(tok{1}); return, end

tok = regexp(wire, '^WireOut([1-4])$', 'tokens', 'once');
if ~isempty(tok), kind = 'wireout'; idx = str2double(tok{1}); return, end

tok = regexp(wire, '^Serial([1-2])Byte$', 'tokens', 'once');
if ~isempty(tok), kind = 'serialbyte'; idx = str2double(tok{1}); return, end

if strncmp(wire, 'State_', 6)
    kind = 'state';
    return
end

if strncmp(wire, 'Event_', 6)
    kind = 'event';
    return
end

if any(strcmp(wire, {'TrialNum','TrialAborted','TrialDuration','NStates', ...
        'NEvents','LastSoftCode','CurrentState','CurrentStateName', ...
        'StateCodes','StateTimes','EventCodes','EventTimes'}))
    kind = 'result';
end
end


% ------------------------------------------------------------------------
function v = resultValue_(obj, wire)
% v = resultValue_(obj, wire)
% Serve a scalar or vector summary of the latched trial record.
%
% Every branch returns a value of a fixed class and, where scalar, a fixed
% size. The readable field set has to stay frozen for the life of the
% interface or RUNTIME.TRIALS(i).DATA(k) = data throws "Subscripted
% assignment between dissimilar structures" the first time a trial visits a
% different set of states.

switch wire
    case 'TrialNum'
        v = obj.trialNum_;

    case 'TrialAborted'
        v = double(obj.trialAborted_);

    case 'TrialDuration'
        % Host-side elapsed time. The authoritative device timing lives in
        % StateTimes/EventTimes; this is a convenience for online plots.
        if isempty(obj.trialTic_)
            v = nan;
        else
            v = toc(obj.trialTic_);
        end

    case 'NStates'
        v = numel(obj.stateCodes_);

    case 'NEvents'
        % Can legitimately exceed numel(EventTimes): the firmware stops
        % recording timestamps past MAX_TIMESTAMPS while the state machine
        % keeps running and keeps reporting events.
        v = numel(obj.eventCodes_);

    case 'LastSoftCode'
        v = obj.lastSoftCode_;

    case 'CurrentState'
        v = obj.currentState_;

    case 'CurrentStateName'
        if obj.currentState_ >= 1 && obj.currentState_ <= numel(obj.StateNames)
            v = obj.StateNames{obj.currentState_};
        else
            v = '';
        end

    case 'StateCodes'
        v = obj.stateCodes_;

    case 'StateTimes'
        v = obj.stateTimes_;

    case 'EventCodes'
        v = obj.eventCodes_;

    case 'EventTimes'
        v = obj.eventTimes_;

    otherwise
        v = nan;
end
end


% ------------------------------------------------------------------------
function v = stateEntryTime_(obj, stateName)
% v = stateEntryTime_(obj, stateName)
% Seconds from matrix start to the first entry into a named state.
%
% Returns NaN when the state was never visited, so the parameter reports a
% value of a stable class on every trial instead of vanishing from the DATA
% struct on trials that skip it.
%
% State indices in the event stream refer to the post-compile manifest
% order that sendStateMatrix produced -- add order, not declaration order --
% so the name is resolved against obj.StateNames and nothing else.

v = nan;

if isempty(obj.StateNames) || isempty(obj.stateCodes_)
    return
end

si = find(strcmp(obj.StateNames, stateName), 1);
if isempty(si)
    return
end

k = find(obj.stateCodes_ == si, 1);
if isempty(k) || k > numel(obj.stateTimes_)
    return
end

v = obj.stateTimes_(k);
end


% ------------------------------------------------------------------------
function v = eventTime_(obj, eventName)
% v = eventTime_(obj, eventName)
% Seconds from matrix start to the first occurrence of a named event.
%
% Names are resolved against the fixed hw.Bpod.EVENT_NAMES vocabulary, so
% an event that never fired reports NaN rather than dropping its field.

v = nan;

if isempty(obj.eventCodes_)
    return
end

ei = find(strcmp(obj.EVENT_NAMES, eventName), 1);
if isempty(ei)
    return
end

k = find(obj.eventCodes_ == ei, 1);
if isempty(k) || k > numel(obj.eventTimes_)
    return
end

v = obj.eventTimes_(k);
end


% ------------------------------------------------------------------------
function v = storedValue_(obj, P)
% v = storedValue_(obj, P)
% Read a parameter's locally stored value without recursing.
%
% hw.Parameter.get.Value delegates straight back to this interface whenever
% the interface reports IsConnected, so reading P.Value from inside
% get_parameter recurses until MATLAB's stack limit -- the trap hw.Software
% documents in capital letters in its own get_parameter. Dropping
% linkReady_ for the duration takes the same short circuit hw.Software
% relies on, and the flag is restored even when the getter errors.
%
% This is the path host-side trial configuration takes: dispatchNextTrial
% wrote the value through set.Value, which stored it on the parameter and
% then told us about it, and the trial-end sweep reads it straight back.

wasReady = obj.linkReady_;
obj.linkReady_ = false;
try
    v = P.Value;
catch ME
    v = nan;
    vprintf(0, 1, ME);
end
obj.linkReady_ = wasReady;
end
