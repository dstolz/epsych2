
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

            % Get Read parameters scoped to this subject's box.
            % Box-specific parameters carry a "~BoxID" suffix; global parameters
            % (software interface, no suffix) are included for every subject.
            boxSuffix = sprintf('~%d', RUNTIME.TRIALS(i).BoxID);
            P_read = RUNTIME.all_parameters(Access = 'Read');
            if ~isempty(P_read)
                names = string({P_read.Name});
                boxMask = endsWith(names, boxSuffix) | ~contains(names, '~');
                P_read = P_read(boxMask);
            end
            data = struct();
            for k = 1:numel(P_read)
                data.(P_read(k).validName) = P_read(k).Value;
            end

            data.TrialNumber = RUNTIME.TRIALS(i).TrialIndex;
            data.TrialID     = RUNTIME.TRIALS(i).NextTrialID;
            data.computerTimestamp = datetime('now');

            trialIdx = RUNTIME.TRIALS(i).TrialIndex;

            % Store data in runtime struct for this trial
            RUNTIME.TRIALS(i).DATA(trialIdx) = data;

            % Append only the new trial entry to the data file (avoids rewriting all accumulated trials)
            m = matfile(RUNTIME.DataFile(i), 'Writable', true);
            m.allData(1, trialIdx) = data;

            
            % Notify selector that this trial completed
            RUNTIME.TRIALS(i).selector.onComplete(RUNTIME.TRIALS(i).NextTrialID, data);


            % Broadcast event data has been updated
            evtdata = epsych.TrialsData(RUNTIME.TRIALS(i));
            RUNTIME.HELPER.notify('NewData',evtdata);

            vprintf(3,'Trial #%d: Trial Over for box %d',RUNTIME.TRIALS(i).TrialIndex,i)
        end







        % If in use, wait for manual completion of trial in RPvds
        if ~isempty(RUNTIME.CORE(i).TrialComplete)
            vprintf(4,'Checking TrialComplete tag for box %d',i)
            RUNTIME.ON_HOLD(i) = ~RUNTIME.CORE(i).TrialComplete;
        end

        if RUNTIME.ON_HOLD(i), continue; end





        % Increment trial index
        RUNTIME.TRIALS(i).TrialIndex = RUNTIME.TRIALS(i).TrialIndex + 1;



    end


    RUNTIME.TRIALS(i).FORCE_TRIAL = false;

    % --- Safe-boundary operator recompile ---
    % Applied between trials so that hardware state is stable and no
    % trial parameters have been dispatched for the upcoming trial yet.
    if RUNTIME.TRIALS(i).RECOMPILE_REQUESTED
        RUNTIME.TRIALS(i).RECOMPILE_REQUESTED = false;
        vprintf(1,'Operator recompile requested for subject %d — attempting at trial boundary.',i)
        try
            CONFIG_ITEM = RUNTIME.TRIALS(i).protocol;
            CONFIG_ITEM.compile();
            compiled = CONFIG_ITEM.COMPILED;

            RUNTIME.TRIALS(i).parameters = compiled.parameters;
            RUNTIME.TRIALS(i).trials     = compiled.trials;

            RUNTIME.TRIALS(i).selector.onRecompile(RUNTIME.TRIALS(i));

            vprintf(1,'Recompile complete: %d trials now active for subject %d.', compiled.ntrials, i)
        catch me
            vprintf(0,1,me);
            vprintf(0,1,'Recompile failed for subject %d — preserving last valid runtime state.',i)
        end
    end

    % Select next trial using selector object
    try
        vprintf(3,'Selecting next trial for box %d using %s',i,class(RUNTIME.TRIALS(i).selector))
        tcf = tic;
        RUNTIME.TRIALS(i).NextTrialID = RUNTIME.TRIALS(i).selector.selectNext(RUNTIME.TRIALS(i));
        vprintf(4,'%s ran in %.4f seconds',class(RUNTIME.TRIALS(i).selector),toc(tcf))
    catch me
        vprintf(0,1,'Error in trial selector "%s": %s', class(RUNTIME.TRIALS(i).selector), me.message);
        vprintf(0,1,me);
        t = timerfindall;
        if ~isempty(t)
            stop(t);
            delete(t);
        end
        rethrow(me)
    end
    

    
    
    params = RUNTIME.TRIALS(i).parameters;
    dispatchIdx = ~strcmp({params.Access}, 'Read');

    % Indicate next trial parameters in command window if GVerbosity >= 4    
    for j = 1:numel(params)
        vprintf(4,'Trial #%d: %s = %g', ...
            RUNTIME.TRIALS(i).TrialIndex, ...
            params(j).Name, ...
            RUNTIME.TRIALS(i).trials{RUNTIME.TRIALS(i).NextTrialID, j})
    end

    % vvvvvvvvvvvvv  NEW TRIAL SEQUENCE  vvvvvvvvvvvvv
    vprintf(2,'Trial #%d: New Trial Sequence for box %d',RUNTIME.TRIALS(i).TrialIndex,i)

    % 1. Send trigger to reset components before updating parameters
    vprintf(4,'Hardware Trigger for ResetTrig')
    RUNTIME.HW.trigger(RUNTIME.CORE(i).ResetTrig);

    % 2. Dispatch write parameters for this trial (Access ~= 'Read')
    vprintf(4,'Update parameter tags')
    P = params(dispatchIdx);
    trial_row = RUNTIME.TRIALS(i).trials(RUNTIME.TRIALS(i).NextTrialID, dispatchIdx);
    [P.Value] = deal(trial_row{:});

    % 3. Trigger new trial
    vprintf(4,'Hardware Trigger for NewTrial')
    RUNTIME.HW.trigger(RUNTIME.CORE(i).NewTrial);

    % 4. Notify whomever is listening of new trial
    vprintf(4,'Notify listeners with new trial data')
    evtdata = epsych.TrialsData(RUNTIME.TRIALS(i));
    RUNTIME.HELPER.notify('NewTrial',evtdata);

end














