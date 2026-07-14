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

% Dispatch writable parameters flagged to update every trial. Read-only
% parameters and those with UpdateEveryTrial == false are set once elsewhere
% and left unchanged by this per-trial dispatch.
notReadOnly = ~strcmp({T.parameters.Access}, 'Read');
updateEveryTrial = [T.parameters.UpdateEveryTrial];
dispatchIdx = notReadOnly & updateEveryTrial;




% vvvvvvvvvvvvv  NEW TRIAL SEQUENCE  vvvvvvvvvvvvv
vprintf(2,'Trial #%d: New Trial Sequence for box %d',T.TrialIndex,subjectIdx)

% 1. Send trigger to reset components before updating parameters
vprintf(4,'Hardware Trigger for ResetTrig')
obj.CORE(subjectIdx).ResetTrig.Trigger();

% 2. Dispatch write parameters for this trial (Access ~= 'Read')
vprintf(4,'Update parameter tags')
P = T.parameters(dispatchIdx);
trialRow = T.trials(T.NextTrialID, dispatchIdx);

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