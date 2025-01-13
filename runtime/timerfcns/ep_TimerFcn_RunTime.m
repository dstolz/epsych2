function RUNTIME = ep_TimerFcn_RunTime(RUNTIME)
% RUNTIME = ep_TimerFcn_RunTime(RUNTIME)
% 
% Default RunTime timer function
% 

% Copyright (C) 2016  Daniel Stolzberg, PhD
% updated for hardware abstraction 2024 DS


for i = 1:RUNTIME.NSubjects

    if ~RUNTIME.ON_HOLD(i)
        % Check _RespCode parameter for non-zero value or if #TrigState is true

        RCtag = RUNTIME.HW.get_parameter(RUNTIME.CORE(i).RespCode);
        TStag = RUNTIME.HW.get_parameter(RUNTIME.CORE(i).TrigState);
        
        if ~RCtag || TStag, continue; end
        
        TrialNum = RUNTIME.HW.get_parameter(RUNTIME.CORE(i).TrialNum);
        
        
        
        
        % There was a response and the trial is over.
        % Retrieve parameter data from HW
        wpn = RUNTIME.TRIALS(i).writeparams;
        wpn = matlab.lang.makeValidName(wpn);
        wpv = RUNTIME.HW.get_parameter(wpn);
        wp = [wpn; wpv];
        data = struct(wp{:});
        data.ResponseCode = RCtag;
        data.TrialID = TrialNum;
        data.inaccurateTimestamp = datetime("now");
        RUNTIME.TRIALS(i).DATA(RUNTIME.TRIALS(i).TrialIndex) = data;
        
        
        % Broadcast event data has been updated
        evtdata = epsych.TrialsData(RUNTIME.TRIALS(i));
        RUNTIME.HELPER.notify('NewData',evtdata);
        
        
        % Save runtime data in case of crash
        data = RUNTIME.TRIALS(i).DATA;
        save(RUNTIME.DataFile{i},'data','-append','-v6'); % -v6 is much faster because it doesn't use compression
        
    end
    
    
    



    
    % If in use, wait for manual completion of trial in RPvds
    if isfield(RUNTIME,'TrialCompleteIdx') % ???
        TCtag = RUNTIME.HW.get_parameter(RUNTIME.CORE(i).TrialComplete);
        RUNTIME.ON_HOLD(i) = ~TCtag;
    end
    
    if RUNTIME.ON_HOLD(i), continue; end
    
    





    
    % Collect Buffer if available
    if isfield(RUNTIME,'AcqBufferStr')
        try
            RUNTIME.TRIALS(i).AcqBuffer = RUNTIME.HW.get_parameter(RUNTIME.CORE(i).AcqBuffer);
        end
    end
    

    
    
     % Increment trial index
    RUNTIME.TRIALS(i).TrialIndex = RUNTIME.TRIALS(i).TrialIndex + 1;
    
    






    
    % Select next trial with default or custom function
    try
        n = feval(RUNTIME.TRIALS(i).trialfunc,RUNTIME.TRIALS(i));
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
    
    
    



    
    
    % Increment TRIALS.TrialCount for the selected trial index
    RUNTIME.TRIALS(i).TrialCount(RUNTIME.TRIALS(i).NextTrialID) = ...
        RUNTIME.TRIALS(i).TrialCount(RUNTIME.TRIALS(i).NextTrialID) + 1;

    

    
    
    
    

    % vvvvvvvvvvvvv  NEW TRIAL SEQUENCE  vvvvvvvvvvvvv
    vprintf(2,'Triggering trial on box %d',i)

    % 1. Send trigger to reset components before updating parameters
    RUNTIME.HW.trigger(RUNTIME.CORE(i).ResetTrig);

    % 2. Update parameter tags
    % TO DO: UPDATE PROTOCOL STRUCTURE AND MAKE THIS GENEREALLY MORE EFFICIENT
    trials = RUNTIME.TRIALS(i).trials(RUNTIME.TRIALS(i).NextTrialID,:);
    wp = RUNTIME.TRIALS.writeparams;
    P = RUNTIME.HW.find_parameter(wp);
    [P.Value] = deal(trials{:});

    % 3. Trigger first new trial
    RUNTIME.HW.trigger(RUNTIME.CORE(i).NewTrial);

    % notify of new trial
    RUNTIME.HELPER.notify('NewTrial');


end













