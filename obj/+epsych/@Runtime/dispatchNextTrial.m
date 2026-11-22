function dispatchNextTrial(obj, subjectIdx)
% dispatchNextTrial(obj, subjectIdx)
% Dispatch the already selected next trial for one subject.
%
% Applies all writable trial parameters for the current NextTrialID, fires the
% reset and new-trial triggers, and broadcasts the NewTrial event.
%
% Parameters:
%   obj                           Runtime state object.
%   subjectIdx (1,1) double       Index of the subject to dispatch.
%
% Returns:
%   None. Updates parameter handles and notifies listeners.

arguments
    obj (1,1) epsych.Runtime
    subjectIdx (1,1) double {mustBeInteger,mustBePositive}
end

T = obj.TRIALS(subjectIdx);

% Dispatch writable parameters flagged to update every trial. SetOnce
% parameters (e.g. coefficient buffers) ride along on the first dispatch only
% -- the one triggered by set.TRIALS before the session timer starts, when
% TrialIndex is still 1 -- so their value reaches the hardware once and is
% then left alone. Read-only parameters and those with UpdateEveryTrial ==
% false (and SetOnce == false) are never written by this per-trial dispatch.
notReadOnly = ~strcmp({T.parameters.Access}, 'Read');
updateEveryTrial = [T.parameters.UpdateEveryTrial];
setOnce = [T.parameters.SetOnce];
dispatchIdx = notReadOnly & (updateEveryTrial | (setOnce & T.TrialIndex == 1));




% vvvvvvvvvvvvv  NEW TRIAL SEQUENCE  vvvvvvvvvvvvv
vprintf(2,'Trial #%d: New Trial Sequence for box %d',T.TrialIndex,subjectIdx)

% Trial-loop timing, when the session asked for it. Outside a trial boundary
% (the first dispatch, a regenerate) the marks are ignored.
ts = obj.TickStats;
timed = ~isempty(ts);

% From here to the end of the NewTrial pulse every interface knows that what
% it is asked to write belongs to a trial dispatch (hw.Interface.InDispatch).
% A backend then leaves its per-write success record to the one summary
% record below: with the log taking every level by default, a record per
% parameter from here plus another per write from the backend was two
% dbstack-and-file-write records for each of some forty parameters, on every
% trial, while the subject waited. Failures are still logged where they
% happen, and a write made outside a dispatch keeps its own record.
ifaces = obj.Interfaces;
for k = 1:numel(ifaces)
    ifaces(k).InDispatch = true;
end
endDispatch = onCleanup(@() localEndDispatch(ifaces));

% 1. Send trigger to reset components before updating parameters
obj.TRIGGERS(subjectIdx).ResetTrig.Trigger();
if timed, ts.mark("reset"); end

% 2. Dispatch write parameters for this trial (Access ~= 'Read')
P = T.parameters(dispatchIdx);
trialRow = T.trials(T.NextTrialID, dispatchIdx);

% Dispatch in dependency order: a parameter whose Expression reads another
% dispatched parameter's value (e.g. RespWinDelay referencing a randomized
% StimDelay) must be assigned after that parameter, or the expression
% evaluates against the previous trial's value.
cache = obj.DispatchOrderCache_;
cacheValid = numel(cache) >= subjectIdx ...
    && numel(cache(subjectIdx).params) == numel(P) ...
    && all(cache(subjectIdx).params == P);
if ~cacheValid
    % Resolution scope mirrors hw.Parameter.evaluateExpression_: every
    % parameter of every module across all interfaces.
    scope = hw.Parameter.empty(1, 0);
    for k = 1:numel(obj.Interfaces)
        modules = obj.Interfaces(k).Module;
        for m = 1:numel(modules)
            if ~isempty(modules(m).Parameters)
                scope = [scope, modules(m).Parameters];
            end
        end
    end
    cache(subjectIdx).params = P;
    cache(subjectIdx).order = hw.Parameter.orderByDependencies(P, scope);
    obj.DispatchOrderCache_ = cache;
end
dispatchOrder = obj.DispatchOrderCache_(subjectIdx).order;
P = P(dispatchOrder);
trialRow = trialRow(dispatchOrder);

% 3. Assign next trial parameter values to the parameter objects.
for j = 1:numel(P)
    P(j).Value = trialRow{j};
end

% One record for the whole dispatch, listing what each parameter was actually
% given -- after randomization, its Expression and clamping, which is why the
% value comes from the parameter and not from the trial row. Built only when
% a destination wants trace records: it is a string per parameter.
if visenabled(4)
    parts = cell(1, numel(P));
    for j = 1:numel(P)
        [v, known] = P(j).hostValue();
        if ~known, v = trialRow{j}; end
        parts{j} = [P(j).Name '=' P(j).formatValue(v)];
    end
    vprintf(4, 'Trial #%d dispatch for box %d: %s', T.TrialIndex, subjectIdx, strjoin(parts, ', '))
end
if timed, ts.mark("writes"); end

% 4. Trigger new trial
obj.TRIGGERS(subjectIdx).NewTrial.Trigger();
if timed, ts.mark("trigger"); end

% The dispatch is over: a listener that writes a parameter from here on is
% not part of it.
clear endDispatch

% 5. Notify whomever is listening of new trial
evtdata = epsych.TrialsData(T);
obj.EVENTS.notify('NewTrial',evtdata);
if timed, ts.mark("newTrial"); end

end


function localEndDispatch(ifaces)
% Clear the in-dispatch flag, on every exit path.
for k = 1:numel(ifaces)
    if isvalid(ifaces(k))
        ifaces(k).InDispatch = false;
    end
end
end