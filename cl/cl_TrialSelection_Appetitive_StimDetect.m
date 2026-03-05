function TRIALS = cl_TrialSelection_Appetitive_StimDetect(TRIALS)
% TRIALS = cl_TrialSelection_Appetitive_StimDetect(TRIALS)
%
% Select the next trial in an appetitive stimulus-detection task.
%
% PARAMETERS USED FROM TRIALS.trials (via "all" struct):
%
%   Used in ALL TrialOrder modes:
%     TrialType   - numeric trial code (STIM/CATCH/REMIND filtering)
%     Depth       - stimulus depth (selection and matching)
%
%   Used ONLY in 'Staircase' mode:
%     StepDown    - decrement applied after HIT
%     StepUp      - increment applied after MISS
%     MinDepth    - lower bound for Depth
%     MaxDepth    - upper bound for Depth
%
% OTHER TRIALS FIELDS USED:
%   TRIALS.activeTrials - logical mask of currently enabled trials
%   TRIALS.DATA.Depth   - depth history for completed trials
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


% OVERVIEW (numbered to match code sections):
%   1)  Access hidden hardware Reminder flag
%   2)  Define trial-type codes (STIM/CATCH/REMIND)
%   3)  Define outcome-conditioned transition probabilities
%   4)  Extract write parameters into struct "all"
%   5)  Set default NextTrialID (CATCH)
%   6)  Read GUI parameters
%   7)  Apply Reminder override (if enabled)
%   8)  Clear Reminder flag (normal path)
%   9)  Decode last trial outcome (HIT/MISS/CR/FA)
%  10)  Select next trial type (STIM vs CATCH)
%  11)  Define valid trials for Depth selection (exclude REMIND;
%       respect TRIALS.activeTrials)
%  12)  Select next Depth based on TrialOrder
%         - Descending / Ascending
%         - Random (least-presented Depth)
%         - Staircase (delegated to section 13)
%  12a)  Staircase mode: update Depth and assign NextTrialID
%  12b)  Non-staircase: map selected Depth to trial row
%



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
% TT = dictionary(["STIM","CATCH","REMIND"],0:2)



%--------------------------------------------------------------------------
% 4) Copy each write-parameter column from TRIALS.trials into numeric arrays
%--------------------------------------------------------------------------
for fn = string(fieldnames(TRIALS.writeParamIdx))'
    all.(fn) = [TRIALS.trials{:,TRIALS.writeParamIdx.(fn)}];
end

%--------------------------------------------------------------------------
% 5) Default next trial = first CATCH (used on trial 1 / unknown outcome)
%--------------------------------------------------------------------------
if TRIALS.TrialIndex == 1
    TRIALS.NextTrialID = find(all.TrialType == TT.STIM,1);
    return
end

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



%--------------------------------------------------------------------------
% 12) Select next Depth based on TrialOrder
%     Descending/Ascending: step through sorted Depth values relative to lastStim
%     Random: choose among least-presented Depth values (loose match)
%     Staircase: handled in the 'Staircase' case (updates Depth directly)
%--------------------------------------------------------------------------
lastGoTrialIdx = find(RC.("TrialType_"+TT.STIM),1,'last');
stim = [TRIALS.DATA.Depth];
if isempty(lastGoTrialIdx)
    lastStim = max(all.Depth); % no prior STIM: start at max depth
else
    lastStim = stim(lastGoTrialIdx);
end

%--------------------------------------------------------------------------
% 12a) Staircase: update Depth on STIM trials
%     HIT  -> StepDown (shallower)
%     MISS -> StepUp   (deeper)
%--------------------------------------------------------------------------

nextStim = lastStim; % no change after 'aborted' trial

if RC.Hit(end)
    nextStim = lastStim - SP.StepOnHit.Value;
elseif RC.Miss(end)
    nextStim = lastStim + SP.StepOnMiss.Value;
end

nextStim = max(nextStim, SP.MinDepth.Value);
nextStim = min(nextStim, SP.MaxDepth.Value);
vprintf(4,'nextStim = %g',nextStim)

ind = all.TrialType == TT.STIM;


[TRIALS.trials{ind,TRIALS.writeParamIdx.Depth}] = deal(nextStim);

%--------------------------------------------------------------------------
% Assign NextTrialID for Staircase mode and return
%--------------------------------------------------------------------------
TRIALS.NextTrialID = find(all.TrialType == TT.STIM,1);