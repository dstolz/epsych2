function TRIALS = cl_TrialSelection_Appetitive_StimDetect(TRIALS)
% TRIALS = cl_TrialSelection_Appetitive_StimDetect(TRIALS)
%
% Select the next trial in an appetitive stimulus-detection task.
% Uses the last trial outcome (HIT/MISS/CR/FA) to probabilistically choose
% the next trial *type* (STIM vs CATCH). Supports an optional REMIND trial
% override via GUI parameter.
%
% PARAMETERS USED FROM TRIALS.trials (via "all" struct):
%
%   Used in ALL TrialOrder modes:
%     TrialType   - numeric trial code (STIM/CATCH/REMIND filtering)
%     Depth       - stimulus depth (selection and matching)
%
%   Used ONLY in 'Staircase' mode:
%     StepHarder  - decrement applied after HIT
%     StepEasier  - increment applied after MISS
%     MinDepth    - lower bound for Depth
%     MaxDepth    - upper bound for Depth
%
% OTHER TRIALS FIELDS USED:
%   TRIALS.activeTrials - logical mask of currently enabled trials
%                         (used in Descending/Ascending/Random modes)
%   TRIALS.DATA.Depth   - depth history for completed trials
%                         (used in Random and Staircase modes)
%   TRIALS.DATA.RespCode- response codes for outcome decoding
%
% GUI PARAMETERS USED:
%   ReminderTrials  - forces REMIND trial when enabled (all modes)
%   TrialOrder      - 'Descending' | 'Ascending' | 'Random' | 'Staircase'
%
% PARAMETERS / VALUES HARDCODED IN THIS FUNCTION:
%   TT.STIM   = 0
%   TT.CATCH  = 1
%   TT.REMIND = 2
%   Outcome-conditioned probabilities p.* (HIT/MISS/CR/FA transitions)
%   Default first-trial behavior: CATCH
%   Random mode balancing rule: choose least-presented Depth (loose match)





%--------------------------------------------------------------------------
% 1) Hidden hardware flag: marks the next trial as a reminder to the circuit
%--------------------------------------------------------------------------
reminderTrial = TRIALS.HW.find_parameter('~ReminderTrial',includeInvisible=true);

%--------------------------------------------------------------------------
% 2) Numeric trial-type codes used in TRIALS.trials and response decoding
%--------------------------------------------------------------------------
TT.STIM   = 0;   % stimulus (GO) trial
TT.CATCH  = 1;   % catch (NOGO) trial
TT.REMIND = 2;   % reminder trial

%--------------------------------------------------------------------------
% 3) Outcome-conditioned probabilities for selecting the next trial type
%--------------------------------------------------------------------------
p.HIT_STIM   = 0.5;  % P(STIM | HIT)
p.HIT_CATCH  = 0.5;  % P(CATCH | HIT)
p.MISS_STIM  = 1.0;  % P(STIM | MISS)
p.MISS_CATCH = 0.0;  % P(CATCH | MISS)
p.FA_STIM    = 0.0;  % P(STIM | FA)
p.FA_CATCH   = 1.0;  % P(CATCH | FA)
p.CR_STIM    = 1.0;  % P(STIM | CR)
p.CR_CATCH   = 0.0;  % P(CATCH | CR)

%--------------------------------------------------------------------------
% 4) Copy each write-parameter column from TRIALS.trials into numeric arrays
%--------------------------------------------------------------------------
for fn = string(fieldnames(TRIALS.writeParamIdx))'
    all.(fn) = [TRIALS.trials{:,TRIALS.writeParamIdx.(fn)}];
end

%--------------------------------------------------------------------------
% 5) Default next trial = first CATCH (used on trial 1 / unknown outcome)
%--------------------------------------------------------------------------
TRIALS.NextTrialID = find(all.TrialType == TT.CATCH,1);

%--------------------------------------------------------------------------
% 6) Read software parameters (GUI). If not initialized, keep default.
%--------------------------------------------------------------------------
sp = TRIALS.S.Module.Parameters;
if isempty(sp), return; end
sn = {sp.validName};
for j = 1:length(sp), SP.(sn{j}) = sp(j); end

%--------------------------------------------------------------------------
% 7) Reminder override: force REMIND trial and set hardware flag
%--------------------------------------------------------------------------
if SP.ReminderTrials.Value == 1
    TRIALS.NextTrialID = find(all.TrialType == TT.REMIND,1);
    reminderTrial.Value = true;
    return
end

%--------------------------------------------------------------------------
% 8) Clear reminder flag (normal trial selection path)
%--------------------------------------------------------------------------
reminderTrial.Value = false;

%--------------------------------------------------------------------------
% 9) Decode response codes for completed trials and label the latest outcome
%    See epsych.BitMask.list() for decoded field names.
%--------------------------------------------------------------------------
RC = epsych.BitMask.decodeResponseCodes([TRIALS.DATA.RespCode]);

latestOutcome = "";
if TRIALS.TrialIndex > 1
    lastRC = RC(end);
    if lastRC.Hit
        latestOutcome = "HIT";
    elseif lastRC.Miss
        latestOutcome = "MISS";
    elseif lastRC.CorrectReject
        latestOutcome = "CR";
    elseif lastRC.FalseAlarm
        latestOutcome = "FA";
    end
end

%--------------------------------------------------------------------------
% 10) Choose next trial type based on last outcome
%--------------------------------------------------------------------------
switch latestOutcome
    case "HIT"
        nextTrialType = randsample([TT.STIM, TT.CATCH],1,true,[p.HIT_STIM, p.HIT_CATCH]);
    case "MISS"
        nextTrialType = randsample([TT.STIM, TT.CATCH],1,true,[p.MISS_STIM, p.MISS_CATCH]);
    case "CR"
        nextTrialType = randsample([TT.STIM, TT.CATCH],1,true,[p.CR_STIM, p.CR_CATCH]);
    case "FA"
        nextTrialType = randsample([TT.STIM, TT.CATCH],1,true,[p.FA_STIM, p.FA_CATCH]);
    otherwise
        nextTrialType = TT.CATCH; % first trial / unknown outcome
end

%--------------------------------------------------------------------------
% 11) Define valid trials for Depth selection (exclude REMIND; respect activeTrials)
%--------------------------------------------------------------------------
activeTrials = false(size(all.TrialType));
activeTrials(all.TrialType~=TT.REMIND) = TRIALS.activeTrials;

valid.Depth = all.Depth(activeTrials & all.TrialType == TT.STIM);
valid.TrialType = all.TrialType(activeTrials & all.TrialType == TT.STIM);

%--------------------------------------------------------------------------
% 12) Select next Depth based on TrialOrder
%     Descending/Ascending: step through sorted Depth values relative to lastStim
%     Random: choose among least-presented Depth values (loose match)
%     Staircase: handled in the 'Staircase' case (updates Depth directly)
%--------------------------------------------------------------------------
switch SP.TrialOrder.Value
       
    case 'Descending'
        valid.Depth = sort(valid.Depth,'descend');
        if isempty(lastStim), lastStim = inf; end
        lastStim = double(lastStim)-1e-4;
        i = find(valid.Depth < lastStim,1);
        if isempty(i)
            nextDepth = max(valid.Depth);
        else
            nextDepth = valid.Depth(i);
        end

    case 'Ascending'
        valid.Depth = sort(valid.Depth,'ascend');
        if isempty(lastStim), lastStim = -inf; end
        lastStim = double(lastStim)+1e-4;
        i = find(valid.Depth > lastStim,1);
        if isempty(i)
            nextDepth = min(valid.Depth);
        else
            nextDepth = valid.Depth(i);
        end

    case 'Random'
        n = length(valid.Depth);
        goTrials = stim(RC.("TrialType_"+TT.STIM));
        if length(goTrials) > n
            goTrials = goTrials(end-n+1:end);
        end
        nPresentations = arrayfun(@(a) sum(isapprox(goTrials,a,"loose")),valid.Depth);
        m = min(nPresentations);
        idx = find(nPresentations == m);
        r = randi(length(idx));
        i = idx(r);
        nextDepth = valid.Depth(i);
        
    case 'Staircase'

        %--------------------------------------------------------------------------
        % 13a) Staircase: update Depth on STIM trials
        %     HIT  -> StepHarder (harder)
        %     MISS -> StepEasier (easier)
        %--------------------------------------------------------------------------
        lastGoTrialIdx = find(RC.("TrialType_"+TT.STIM),1,'last');
        stim = [TRIALS.DATA.Depth];
        if isempty(lastGoTrialIdx)
            lastStim = max(all.Depth); % no prior STIM: start at max depth
        else
            lastStim = stim(lastGoTrialIdx);
        end

        if nextTrialType == TT.STIM
            if latestOutcome == "HIT"
                nextStim = lastStim - all.StepHarder(1);
                nextStim = max(nextStim, all.MinDepth(1));
            elseif latestOutcome == "MISS"
                nextStim = lastStim + all.StepEasier(1);
                nextStim = min(nextStim, all.MaxDepth(1));
            end

            ind = all.TrialType == TT.STIM;
            [TRIALS.trials{1,ind}] = deal(nextStim);
        end

        %--------------------------------------------------------------------------
        % 13b) Assign NextTrialID for Staircase mode and return
        %--------------------------------------------------------------------------
        TRIALS.NextTrialID = find(all.TrialType == TT.(nextTrialType),1);
        return
end

%--------------------------------------------------------------------------
% 14) Map selected Depth to trial row and assign NextTrialID (non-staircase)
%--------------------------------------------------------------------------
TRIALS.NextTrialID = find(all.Depth == nextDepth & all.TrialType ~= TT.REMIND);
