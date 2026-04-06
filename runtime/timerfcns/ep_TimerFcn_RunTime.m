
function RUNTIME = ep_TimerFcn_RunTime(RUNTIME)
% RUNTIME = ep_TimerFcn_RunTime(RUNTIME)
%
% Default RunTime timer function for EPsych.
% Handles trial completion, data saving, trial selection, and hardware triggers for each subject.
%
% Parameters:
%   RUNTIME - (struct or epsych.Runtime) Current runtime state, including hardware, trial, and data fields.
%
% Returns:
%   RUNTIME - Updated runtime state after timer tick.
%
% See also: epsych.Runtime, documentation/overviews/RunExpt_GUI_Overview.md

% Copyright (C) 2016  Daniel Stolzberg, PhD
% updated for hardware abstraction 2024 DS


for i = 1:RUNTIME.NSubjects
    % the following FORCE_TRIAL tells ep_TimerFcn_RunTime to skip waiting
    % for a trial to complete and just go directly to updating for next trial
    if ~RUNTIME.TRIALS(i).FORCE_TRIAL
        if ~RUNTIME.ON_HOLD(i)
            % Check _RespCode parameter for non-zero value or if #TrigState is true

            RCtag = RUNTIME.CORE(i).RespCode.Value;
            TStag = RUNTIME.CORE(i).TrigState.Value;

            if ~RCtag || TStag, continue; end



                
            % There was a response and the trial is over.
            % Retrieve parameter data for this trial and save in TRIALS structure. 

            % get all 'Read' or 'Read / Write' parameters from hardware and software interfaces and save in data struct
            data = RUNTIME.getAllParameters(Access = 'Read', asStruct = true);
            
            RUNTIME.TRIALS(i).DATA(RUNTIME.TRIALS(i).TrialIndex) = data;

            data = RUNTIME.TRIALS(i).DATA; % get current trial data struct for saving

            % Save updated runtime data in case of crash
            save(RUNTIME.DataFile(i),'data','-append','-v6'); % -v6 is much faster because it doesn't use compression

            % Broadcast event data has been updated
            evtdata = epsych.TrialsData(RUNTIME.TRIALS(i));
            RUNTIME.HELPER.notify('NewData',evtdata);

            vprintf(3,'Trial #%d: Trial Over for box %d',RUNTIME.TRIALS(i).TrialIndex,i)
        end







        % If in use, wait for manual completion of trial in RPvds
        if ~isempty(RUNTIME.CORE(i),TrialComplete)
            vprintf(4,'Checking TrialComplete tag for box %d',i)
            RUNTIME.ON_HOLD(i) = ~RUNTIME.CORE(i).TrialComplete.Value;
        end

        if RUNTIME.ON_HOLD(i), continue; end





        % Increment trial index
        RUNTIME.TRIALS(i).TrialIndex = RUNTIME.TRIALS(i).TrialIndex + 1;



    end


    RUNTIME.TRIALS(i).FORCE_TRIAL(i) = false;



    % Select next trial with default or custom function
    try
        vprintf(3,'Selecting next trial for box %d using "%s"',i,RUNTIME.TRIALS(i).trialfunc)
        tcf = tic;
        n = feval(RUNTIME.TRIALS(i).trialfunc,RUNTIME.TRIALS(i));
        vprintf(4,'Custom Trial Function, "%s",ran in %.4f seconds',RUNTIME.TRIALS(i).trialfunc,toc(tcf))
        if isstruct(n)
            RUNTIME.TRIALS(i).trials = n.trials;
            RUNTIME.TRIALS(i).NextTrialID = n.NextTrialID;
        elseif isscalar(n)
            RUNTIME.TRIALS(i).NextTrialID = n;
        else
            error('Invalid output from custom trial selection function ''%s''',RUNTIME.TRIALS(i).trialfunc)
        end

    catch me
        fprintf(2,'Error in Custom Trial Selection Function "%s" on line %d\n\n%s\n%s', ...
            me.stack(1).name,me.stack(1).line,me.identifier,me.message);
        vprintf(0,1,me);
    end
    

    
    
    wp = RUNTIME.TRIALS(i).writeparams;
    wpind = ~startsWith(wp,'*'); % ignore asterisk flag

    % Indicate next trial parameters in command window if GVerbosity >= 4    
    pn = matlab.lang.makeValidName(wp);
    for j = 1:size(RUNTIME.TRIALS(i).trials,2)
        vprintf(4,'Trial #%d: %s = %g', ...
            RUNTIME.TRIALS(i).TrialIndex, ...
            wp{j}, ...
            RUNTIME.TRIALS(i).trials{RUNTIME.TRIALS(i).NextTrialID, RUNTIME.TRIALS(i).writeParamIdx.(pn{j})})
    end

    
    



    
    
    % Increment TRIALS.TrialCount for the selected trial index
    RUNTIME.TRIALS(i).TrialCount(RUNTIME.TRIALS(i).NextTrialID) = ...
        RUNTIME.TRIALS(i).TrialCount(RUNTIME.TRIALS(i).NextTrialID) + 1;

    

    
    
    
    

    % vvvvvvvvvvvvv  NEW TRIAL SEQUENCE  vvvvvvvvvvvvv
    vprintf(2,'Trial #%d: New Trial Sequence for box %d',RUNTIME.TRIALS(i).TrialIndex,i)

    % 1. Send trigger to reset components before updating parameters
    vprintf(4,'Hardware Trigger for ResetTrig')
    RUNTIME.HW.trigger(RUNTIME.CORE(i).ResetTrig);

    % 2. Update parameter tags
    % TO DO: UPDATE PROTOCOL STRUCTURE AND MAKE THIS GENEREALLY MORE EFFICIENT
    vprintf(4,'Update parameter tags')
    trials = RUNTIME.TRIALS(i).trials(RUNTIME.TRIALS(i).NextTrialID,wpind);
    P = RUNTIME.HW.find_parameter(wp,includeInvisible=true);
    for k = 1:length(trials)
        P(k).Value = trials{k};
    end
    % [P.Value] = deal(trials{:});

    % 3. Trigger new trial
    vprintf(4,'Hardware Trigger for NewTrial')
    RUNTIME.HW.trigger(RUNTIME.CORE(i).NewTrial);

    % 4. Notify whomever is listening of new trial
    vprintf(4,'Notify listeners with new trial data')
    evtdata = epsych.TrialsData(RUNTIME.TRIALS(i));
    RUNTIME.HELPER.notify('NewTrial',evtdata);

end














