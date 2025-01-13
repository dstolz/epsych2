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

if TRIALS.TrialIndex == 1
    % THIS INDICATES THAT WE ARE ABOUT TO BEGIN THE FIRST TRIAL.
    % THIS IS A GOOD PLACE TO TAKE CARE OF ANY SETUP TASKS LIKE PROMPTING
    % THE USER FOR CUSTOM PARAMETERS, ETC.


   

    % Aversive GO-NOGO always starts with a NOGO trial
    i = [TRIALS.trials{:,loc.TrialType}] == 0; % NOGO TrialType = 0
    TRIALS.NextTrialID = find(i);
    return
end

TRIALS.S.Module.Parameters
P.ReminderTrials = TRIALS.S.find_parameter('ReminderTrials');
P.ReminderTrials = TRIALS.S.find_parameter('TrialOrder');


