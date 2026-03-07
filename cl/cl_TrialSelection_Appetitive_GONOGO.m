function TRIALS = cl_TrialSelection_Appetitive_GONOGO(TRIALS)
% TRIALS = cl_TrialSelection_Appetitive_GONOGO(TRIALS)
% 
% Select next trial for an appetitive GO/NOGO paradigm.
% Implements:
%   - Variable-length NOGO runs
%   - Forced NOGO after false alarms
%   - Optional REMINDER trials
%   - GO trial selection by Ascending / Descending / Random order

%--------------------------------------------------------------------------
% 1) Keep a persistent counter target (nNOGOs)
%    Stores how many consecutive NOGO trials must occur before allowing
%    a GO trial. Value persists across function calls.
%--------------------------------------------------------------------------
persistent nNOGOs

%--------------------------------------------------------------------------
% 2) Find hidden "Reminder trial" hardware parameter
%    This flag informs the circuit whether the next trial is a reminder.
%--------------------------------------------------------------------------
reminderTrial = TRIALS.HW.find_parameter('~ReminderTrial',includeInvisible=true);

%--------------------------------------------------------------------------
% 3) Define numeric trial-type codes
%--------------------------------------------------------------------------
TT.GO     = 0;
TT.NOGO   = 1;
TT.REMIND = 2;

%--------------------------------------------------------------------------
% 4) Build convenient arrays of trial parameters from TRIALS.trials
%    Extract each write parameter column into numeric vectors in "all".
%--------------------------------------------------------------------------
for fn = string(fieldnames(TRIALS.writeParamIdx))'
    all.(fn) = [TRIALS.trials{:,TRIALS.writeParamIdx.(fn)}];
end

%--------------------------------------------------------------------------
% 5) Set default next trial to first NOGO
%--------------------------------------------------------------------------
TRIALS.NextTrialID = find(all.TrialType == TT.NOGO,1);

%--------------------------------------------------------------------------
% 6) Extract software parameters (SP)
%    If GUI not yet initialized, exit early.
%--------------------------------------------------------------------------
sp = TRIALS.S.Module.Parameters;
if isempty(sp), return; end
sn = {sp.validName};
for j = 1:length(sp), SP.(sn{j}) = sp(j); end

%--------------------------------------------------------------------------
% 7) Hard override: if reminder trial requested, force REMIND trial
%--------------------------------------------------------------------------
if SP.ReminderTrials.Value == 1
    TRIALS.NextTrialID = find(all.TrialType == TT.REMIND,1);
    reminderTrial.Value = true;
    return
end

%--------------------------------------------------------------------------
% 8) Clear reminder trial hardware flag
%--------------------------------------------------------------------------
reminderTrial.Value = false;

%--------------------------------------------------------------------------
% 9) Decode response codes from completed trials to an struct of logical vectors
% see epsych.BitMask.list() for structure field names
%--------------------------------------------------------------------------
RC = epsych.BitMask.decode([TRIALS.DATA.RespCode]);

%--------------------------------------------------------------------------
% 10) Determine required number of consecutive NOGOs from sofware parameters
%--------------------------------------------------------------------------
NOGOmax = SP.ConsecutiveNOGO_max.Value;
NOGOmin = SP.ConsecutiveNOGO_min.Value;

if isempty(nNOGOs) || nNOGOs > NOGOmax
    nNOGOs = randi([NOGOmin, NOGOmax]);
end

%--------------------------------------------------------------------------
% 11) Count recent NOGO trials
%--------------------------------------------------------------------------
nBack = min(nNOGOs,TRIALS.TrialIndex-1);
nRecentNOGOs = sum(RC.("TrialType_"+TT.NOGO)(end-nBack+1:end));

%--------------------------------------------------------------------------
% 12) Enforce NOGO continuation rule
%     - If required NOGO run not satisfied
%     -> Force next trial to NOGO
%--------------------------------------------------------------------------
if nRecentNOGOs < nNOGOs
    TRIALS.NextTrialID = find(all.TrialType == TT.NOGO,1);
    return
end

%--------------------------------------------------------------------------
% 13) Set new random NOGO target for next block
%--------------------------------------------------------------------------
nNOGOs = randi([NOGOmin, NOGOmax]);


%--------------------------------------------------------------------------
% 14) Define selectable GO trials (exclude REMIND)
%--------------------------------------------------------------------------
activeTrials = false(size(all.TrialType));
activeTrials(all.TrialType~=TT.REMIND) = TRIALS.activeTrials;

valid.Depth = all.Depth(activeTrials & all.TrialType == TT.GO);
valid.TrialType = all.TrialType(activeTrials & all.TrialType == TT.GO);

%--------------------------------------------------------------------------
% 15) Determine last GO stimulus depth
%--------------------------------------------------------------------------
goTrials = RC.("TrialType_"+TT.GO);
lastGoTrialIdx = find(goTrials,1,'last');
lastStim = [];
stim = [TRIALS.DATA.Depth];
if ~isempty(lastGoTrialIdx), lastStim = stim(lastGoTrialIdx); end

%--------------------------------------------------------------------------
% 16) Select next GO depth according to TrialOrder type
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
        goTrials = stim(RC.("TrialType_"+TT.GO));
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
        error('Staircase mode not implemented')
end

%--------------------------------------------------------------------------
% 17) Map selected depth to trial row and assign NextTrialID
%--------------------------------------------------------------------------
ntid = find(all.Depth == nextDepth & all.TrialType ~= TT.REMIND);
TRIALS.NextTrialID = ntid;
