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

dispatchIdx = ~strcmp({T.parameters.Access}, 'Read');




% Indicate next trial parameters in command window if GVerbosity >= 4    
for j = 1:numel(T.parameters)
    vprintf(4,'Trial #%d: %s = %g', ...
        T.TrialIndex, ...
        T.parameters(j).Name, ...
        T.trials{T.NextTrialID, j})
end

% vvvvvvvvvvvvv  NEW TRIAL SEQUENCE  vvvvvvvvvvvvv
vprintf(2,'Trial #%d: New Trial Sequence for box %d',T.TrialIndex,subjectIdx)

% 1. Send trigger to reset components before updating parameters
vprintf(4,'Hardware Trigger for ResetTrig')
obj.CORE(subjectIdx).ResetTrig.trigger();

% 2. Dispatch write parameters for this trial (Access ~= 'Read')
vprintf(4,'Update parameter tags')
P = T.parameters(dispatchIdx);
trialRow = T.trials(T.NextTrialID, dispatchIdx);
[P.Value] = deal(trialRow{:});

% 3. Trigger new trial
vprintf(4,'Hardware Trigger for NewTrial')
obj.CORE(subjectIdx).NewTrial.trigger();

% 4. Notify whomever is listening of new trial
vprintf(4,'Notify listeners with new trial data')
evtdata = epsych.TrialsData(T);
obj.HELPER.notify('NewTrial',evtdata);

end