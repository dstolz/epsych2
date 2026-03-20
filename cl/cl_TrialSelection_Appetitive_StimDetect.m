function TRIALS = cl_TrialSelection_Appetitive_StimDetect(TRIALS)
% cl_TrialSelection_Appetitive_StimDetect(TRIALS)
% Select the next trial for the appetitive stimulus-detection task.
%
% This callback updates TRIALS.NextTrialID from the most recent response
% outcome, with support for reminder trials, catch-trial insertion, and
% staircase-style stimulus-depth updates.
%
% Inputs:
%   TRIALS  Experiment runtime struct. The function reads trial metadata
%           from TRIALS.trials and TRIALS.writeParamIdx, completed-trial
%           history from TRIALS.DATA, the hidden hardware parameter
%           '~ReminderTrial', and software parameters stored in
%           TRIALS.S.Module.Parameters.
%
% Returns:
%   TRIALS  Updated runtime struct with NextTrialID set to the next trial
%           row. For stimulus trials, the selected Depth value is also
%           written back to the STIM trial rows in TRIALS.trials.
%
% Notes:
%   - Trial types are encoded locally as STIM = 0, CATCH = 1, and
%     REMIND = 2.
%   - ReminderTrials forces the reminder row and sets '~ReminderTrial'.
%   - Staircase updates use StepOnHit, StepOnMiss, MinDepth, MaxDepth,
%     and P_Catch.
%   - The first selected trial is the first STIM row.
%   - See documentation/cl_TrialSelection_Appetitive_StimDetect.md for a
%     behavior summary and parameter notes.
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
    all.(fn) = [TRIALS.trials{:,TRIALS.writeParamIdx.(fn)}];
end

%--------------------------------------------------------------------------
% 4) On the first trial, start with the first stimulus row and return
%--------------------------------------------------------------------------
if TRIALS.TrialIndex == 1
    TRIALS.NextTrialID = find(all.TrialType == TT.STIM,1);
    return
end

%--------------------------------------------------------------------------
% 5) Read software parameters created by the task GUI
%    If the GUI has not been initialized yet, leave the current default.
%--------------------------------------------------------------------------
sp = TRIALS.S.Module.Parameters;
if isempty(sp), return; end
sn = {sp.validName};
for j = 1:length(sp), SP.(sn{j}) = sp(j); end




%--------------------------------------------------------------------------
% 6) Reminder override: force the reminder row and set the hardware flag
%--------------------------------------------------------------------------
if SP.ReminderTrials.Value == 1
    TRIALS.NextTrialID = find(all.TrialType == TT.REMIND,1);
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
    lastStim = max(all.Depth); % no prior STIM: start at max depth
else
    lastStim = stim(lastStimTrialIdx);
end

%--------------------------------------------------------------------------
% 10) Update the next stimulus depth from the latest behavioral outcome
%     Hit  decreases depth, Miss increases depth, and Abort/CR/FA keep the
%     previous stimulus depth for the next stimulus trial.
%--------------------------------------------------------------------------

if RC.Hit(end)
    nextStim = lastStim - SP.StepOnHit.Value;
elseif RC.Miss(end)
    nextStim = lastStim + SP.StepOnMiss.Value;
elseif RC.Abort(end)
    % no change to nextStim (repeat same depth)
    nextStim = lastStim;

    % Retain the previous stimulus delay for the repeated trial.
    sdval = TRIALS.DATA.StimDelay(end);
    SP.StimDelay.Value = sdval; % TODO: DOUBLE CHECK THAT THIS INDEED UPDATES THE GUI PARAMETER FOR THE NEXT TRIAL
elseif RC.CorrectRejection(end) || RC.FalseAlarm(end)
    % no change to nextStim (same depth for next STIM trial)
    nextStim = lastStim;
end



%--------------------------------------------------------------------------
% 12) Clamp the new depth to the configured staircase bounds
%--------------------------------------------------------------------------
nextStim = max(nextStim, SP.MinDepth.Value);
nextStim = min(nextStim, SP.MaxDepth.Value);
vprintf(4,'nextStim = %g',nextStim)

%--------------------------------------------------------------------------
% 13) Write the selected depth into all stimulus trial rows
%--------------------------------------------------------------------------
ind = all.TrialType == TT.STIM;


[TRIALS.trials{ind,TRIALS.writeParamIdx.Depth}] = deal(nextStim);


%--------------------------------------------------------------------------
% 14) Optionally schedule a catch trial based on p(Catch)
%     A catch trial is only inserted when the latest completed trial was
%     not already a catch trial.
%--------------------------------------------------------------------------
pCT = SP.P_Catch.Value; % probability of catch trial (0 to 1)
if ~RC.("TrialType_" + TT.CATCH)(end) && rand() < pCT
    % Override next trial to CATCH based on p(CATCH) and current trial type
    TRIALS.NextTrialID = find(all.TrialType == TT.CATCH,1);

else
    %--------------------------------------------------------------------------
    % 15) Select the first stimulus row as the next trial and return
    %--------------------------------------------------------------------------
    TRIALS.NextTrialID = find(all.TrialType == TT.STIM,1);
end