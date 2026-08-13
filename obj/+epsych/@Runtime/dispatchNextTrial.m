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

% 1. Send trigger to reset components before updating parameters
vprintf(4,'Hardware Trigger for ResetTrig')
obj.CORE(subjectIdx).ResetTrig.Trigger();

% 2. Dispatch write parameters for this trial (Access ~= 'Read')
vprintf(4,'Update parameter tags')
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
    vprintf(4,'Trial #%d: %s = %g', ...
        T.TrialIndex, ...
        P(j).Name, ...
        trialRow{j})

    P(j).Value = trialRow{j};
end

% 4. Trigger new trial
vprintf(4,'Hardware Trigger for NewTrial')
obj.CORE(subjectIdx).NewTrial.Trigger();

% 5. Notify whomever is listening of new trial
vprintf(4,'Notify listeners with new trial data')
evtdata = epsych.TrialsData(T);
obj.HELPER.notify('NewTrial',evtdata);

end