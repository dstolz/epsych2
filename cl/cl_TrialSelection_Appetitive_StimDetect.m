function TRIALS = cl_TrialSelection_Appetitive_StimDetect(TRIALS)
% cl_TrialSelection_Appetitive_StimDetect(TRIALS)
% Selects the next trial for the appetitive stimulus-detection task.
%
% Input:
%   TRIALS  Runtime struct used by the trial loop. Reads trial metadata
%           from TRIALS.trials and TRIALS.writeParamIdx, trial history from
%           TRIALS.DATA, the hidden hardware parameter '~ReminderTrial', and
%           task parameters from TRIALS.Parameters.
%
% Output:
%   TRIALS  Updated runtime struct with NextTrialID set to the next trial
%           row. For STIM trials, also writes the selected Depth value into
%           all STIM rows in TRIALS.trials.
%
% Notes:
%   - Local trial-type codes: STIM = 0, CATCH = 1, REMIND = 2.
%   - ReminderTrials forces a REMIND trial and sets '~ReminderTrial'.
%   - Staircase depth update uses StepOnHit, StepOnMiss, MinDepth, and
%     MaxDepth.
%   - Catch scheduling is controlled by P_Catch.
%   - The initial scheduled trial is the first STIM row.
%   - Documentation: documentation/cl_TrialSelection_Appetitive_StimDetect.md.
%
% See also cl_TrialSelection_Appetitive_GONOGO

%--------------------------------------------------------------------------
% 1) Get the hidden reminder-trial hardware parameter
%    This flag tells the circuit whether the next scheduled trial is a
%    reminder trial.
%--------------------------------------------------------------------------
reminderTrial = TRIALS.HW.find_parameter('~ReminderTrial',includeInvisible=true);

%--------------------------------------------------------------------------
% 2) Define local trial-type codes used in trial rows and decoded history
%--------------------------------------------------------------------------
TT.STIM   = 0;   % stimulus (Stim) trial
TT.CATCH  = 1;   % catch (NOStim) trial
TT.REMIND = 2;   % reminder trial
% TT = dictionary(["STIM","CATCH","REMIND"],0:2)



%--------------------------------------------------------------------------
% 3) Copy write-parameter columns into numeric vectors for easier access
%--------------------------------------------------------------------------
for fn = string(fieldnames(TRIALS.writeParamIdx))'
    T.(fn) = [TRIALS.trials{:,TRIALS.writeParamIdx.(fn)}];
end

%--------------------------------------------------------------------------
% 4) On the first trial, start with the first stimulus row and return
%--------------------------------------------------------------------------
if TRIALS.TrialIndex == 1
    TRIALS.NextTrialID = find(T.TrialType == TT.STIM,1);
    return
end

%--------------------------------------------------------------------------
% 5) Read software parameters created by the task GUI
%    If the GUI has not been initialized yet, leave the current default.
%--------------------------------------------------------------------------
P = TRIALS.Parameters;

%--------------------------------------------------------------------------
% 6) Reminder override: force the reminder row and set the hardware flag
%--------------------------------------------------------------------------
if P.ReminderTrials.Value == 1
    TRIALS.NextTrialID = find(T.TrialType == TT.REMIND,1);
    reminderTrial.Value = true;
    return
end


%--------------------------------------------------------------------------
% 7) Clear the reminder flag for the normal selection path
%--------------------------------------------------------------------------
reminderTrial.Value = false;

%--------------------------------------------------------------------------
% 8) Decode completed-trial response codes into outcome/trial-type masks
%    See epsych.BitMask.list() for decoded field names.
%--------------------------------------------------------------------------
RC = epsych.BitMask.decode([TRIALS.DATA.RespCode]);



%--------------------------------------------------------------------------
% 9) Find the depth of the most recent stimulus trial
%    If no prior stimulus trial exists, begin from the maximum depth.
%--------------------------------------------------------------------------
lastStimTrialIdx = find(RC.("TrialType_"+TT.STIM),1,'last');
stim = [TRIALS.DATA.Depth];
if isempty(lastStimTrialIdx)
    lastStim = max(T.Depth); % no prior STIM: start at max depth
else
    lastStim = stim(lastStimTrialIdx);
end

%--------------------------------------------------------------------------
% 10) Update the next stimulus depth from the latest behavioral outcome
%     Hit  decreases depth, Miss increases depth, and Abort/CR/FA keep the
%     previous stimulus depth for the next stimulus trial.
%--------------------------------------------------------------------------
rda = P.RepeatDelayOnAbort.Value && RC.Abort(end);
if RC.Hit(end)
    nextStim = lastStim - P.StepOnHit.Value;

    restore_stimdelay_randomization(P.StimDelay);

elseif RC.Miss(end) 
    nextStim = lastStim + P.StepOnMiss.Value;

    restore_stimdelay_randomization(P.StimDelay);

elseif RC.Abort(end)
    % no change to nextStim (repeat same depth)
    nextStim = lastStim;

    tooManyAborts = length(RC.Abort) >= 3 && all(RC.Abort(end-2:end));

    if tooManyAborts
        vprintf(2,'Too many Aborts: resetting nextStim to max depth and clearing StimDelay randomization')
        restore_stimdelay_randomization(P.StimDelay);

    elseif rda
        sdval = TRIALS.DATA(end).StimDelay.Value;
    
        % temporarily disable PostUpdateFcn and randomization
        if ~isfield(P.StimDelay.UserData,'CORRECTVAL') || isempty(P.StimDelay.UserData.CORRECTVAL)
            P.StimDelay.UserData = P.StimDelay.toStruct;

            P.StimDelay.isRandom = false;

            P.StimDelay.Value = sdval;
            P.StimDelay.UserData.CORRECTVAL = sdval;
        end

        vprintf(3,'Repeating trial due to Abort: nextStim = %g, StimDelay = %g',nextStim,sdval)
    end
    
elseif RC.CorrectReject(end) || RC.FalseAlarm(end)
    % no change to nextStim (same depth for next STIM trial)
    nextStim = lastStim;
end



%--------------------------------------------------------------------------
% 12) Clamp the new depth to the configured staircase bounds
%--------------------------------------------------------------------------
nextStim = max(nextStim, P.MinDepth.Value);
nextStim = min(nextStim, P.MaxDepth.Value);
vprintf(4,'nextStim = %g',nextStim)

%--------------------------------------------------------------------------
% 13) Write the selected depth into all stimulus trial rows
%--------------------------------------------------------------------------
ind = T.TrialType == TT.STIM;


[TRIALS.trials{ind,TRIALS.writeParamIdx.Depth}] = deal(nextStim);


%--------------------------------------------------------------------------
% 14) Optionally schedule a catch trial based on p(Catch)
%     A catch trial is only inserted when the latest completed trial was
%     not already a catch trial.
%--------------------------------------------------------------------------
pCT = P.P_Catch.Value; % probability of catch trial (0 to 1)

if RC.Abort(end), pCT = 0; end % do not present a catch trial if the previous trial result was an Abort

if length(RC.("TrialType_" + TT.STIM)) >= 10
    nLast10Stim = sum(RC.("TrialType_" + TT.STIM)(end-9:end));
else
    nLast10Stim = 0;
end
if ~RC.("TrialType_" + TT.CATCH)(end) && (rand() < pCT || nLast10Stim >= 10)
    % Override next trial to CATCH based on p(CATCH) and current trial type
    TRIALS.NextTrialID = find(T.TrialType == TT.CATCH,1);

else
    %--------------------------------------------------------------------------
    % 15) Select the first stimulus row as the next trial and return
    %--------------------------------------------------------------------------
    TRIALS.NextTrialID = find(T.TrialType == TT.STIM,1);
end

end


function restore_stimdelay_randomization(pStimDelay)
    if isfield(pStimDelay.UserData,'isRandom') && ~isempty(pStimDelay.UserData.isRandom)
        pStimDelay.isRandom = pStimDelay.UserData.isRandom;
    end
    pStimDelay.UserData.CORRECTVAL = [];
end