function TRIALS = cl_Aversive_GONOGO(TRIALS)
% TRIALS = cl_Aversive_GONOGO(TRIALS)
% 
% TRIALS is a structure which has many subfields used during an experiment.
% Below are some important subfields:
% 
% TRIALS.TrialIndex  ... Keeps track of each completed trial
% TRIALS.trials      ... A cell matrix in which each column is a different
%                        parameter and each row is a unique set of
%                        parameters (called a "trial")
% TRIALS.readparams  ... Parameter tag names for reading values from a
%                        running TDT circuit. The position of the parameter
%                        tag name in this array is the same as the position
%                        of its corresponding parameters (column) in
%                        TRRIALS.trials.
% TRIALS.writeparams ... Parameter tag names writing values from a
%                        running TDT circuit. The position of the parameter
%                        tag name in this array is the same as the position
%                        of its corresponding parameters (column) in
%                        TRIALS.trials.
% TRIALS.TrialCount  ... This field is an Nx1 integer array with N unique
%                        trials. Indices get incremented each time that
%                        trial is run.
% TRIALS.NextTrialID ... Update this field with a scalar index to indicate
%                        which trial to run next.
%
%
% See also, SelectTrial


loc = TRIALS.writeParamIdx;

% Make Software parameters easier to acces
sp = TRIALS.S.Module.Parameters;
sn = {sp.validName};
for j = 1:length(sp), SP.(sn{j}) = sp(j); end

activeTrials = TRIALS.activeTrials;


if TRIALS.TrialIndex == 1
    % THIS INDICATES THAT WE ARE ABOUT TO BEGIN THE FIRST TRIAL.
    % THIS IS A GOOD PLACE TO TAKE CARE OF ANY SETUP TASKS LIKE PROMPTING
    % THE USER FOR CUSTOM PARAMETERS, ETC.


    % Aversive GO-NOGO always starts with a NOGO trial
    i = [TRIALS.trials{:,loc.TrialType}] == 0; % NOGO TrialType = 0
    TRIALS.NextTrialID = find(i);
    return
end

allAMdepths = [TRIALS.trials{:,loc.AMdepth}];

if SP.ReminderTrials.Value
    i = allAMdepths == max(allAMdepths) & activeTrials;
    TRIALS.NextTrialID = find(i);
    return
end


lastAMdepth = TRIALS.DATA(end).AMdepth;

validAMdepths = allAMdepths(activeTrials);

switch SP.TrialOrder.Value
    case 'Descending'
        validAMdepths = sort(validAMdepths,'descend');
        i = find(validAMdepths < lastAMdepth-1e6,1);
        if isempty(i)
            nextAMdepth = max(validAMdepths);
        else
            nextAMdepth = validAMdepths(i);
        end

    case 'Ascending'
        validAMdepths = sort(validAMdepths,'ascend');
        i = find(validAMdepths > lastAMdepth+1e-6,1);
        if isempty(i)
            nextAMdepth = min(validAMdepths);
        else
            nextAMdepth = validAMdepths(i);
        end

    case 'Random'
        % TO DO: FOLLOW RULES OF MAX/MIN CONSECUTIVE NOGO TRIALS
        y = [TRIALS.DATA.AMdepth];
        tt = [TRIALS.DATA.TrialType];
        maxNOGO = SP.ConsecutiveNOGO_max.Value;
        minNOGO = SP.ConsecutiveNOGO_min.Value;
        n = sum(tt(end-maxNOGO:end)==1);
        if n > maxNOGO % next trial must be GO (0)
            idx = find(tt==0);
        elseif n < minNOGO % next trial must be NOGO (1)
            idx = find(tt==1);
        else
            idx = 1:length(tt);
        end
        r = randi(length(idx));
        i = idx(r);
        nextAMdepth = validAMdepths(i);

end

TRIALS.NextTrialID = find(allAMdepths == nextAMdepth);

