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
        
        if RUNTIME.usingSynapse
            TrialNum = AX.getParameterValue(RUNTIME.TDT.Module_{1},RUNTIME.TrialNumStr{i}) - 1;
        else
            TrialNum = AX(RUNTIME.TrialNumIdx(i)).GetTagVal(RUNTIME.TrialNumStr{i}) - 1;
        end
        
        
        
        % There was a response and the trial is over.
        % Retrieve parameter data from RPvds circuits
        data = feval(sprintf('Read%sTags',RUNTIME.TYPE),AX,RUNTIME.TRIALS(i));
        data.ResponseCode = RCtag;
        data.TrialID = TrialNum;
        data.ComputerTimestamp = datetime("now");
        RUNTIME.TRIALS(i).DATA(RUNTIME.TRIALS(i).TrialIndex) = data;
        
        
        
        
        % Save runtime data in case of crash
        data = RUNTIME.TRIALS(i).DATA;
        save(RUNTIME.DataFile{i},'data','-append','-v6'); % -v6 is much faster because it doesn't use compression
        
        
        
        % Broadcast event data has been updated
        evtdata = epsych.TrialsData(RUNTIME.TRIALS(i));
        RUNTIME.HELPER.notify('NewData',evtdata);
        RUNTIME.HELPER.notify('NewTrial',evtdata);
    end
    
    
    



    
    % If in use, wait for manual completion of trial in RPvds
    if isfield(RUNTIME,'TrialCompleteIdx')
        if RUNTIME.usingSynapse            
            TCtag = AX.getParameterValue(RUNTIME.TDT.Module_{1},RUNTIME.TrialCompleteStr{i});
        else
            TCtag = AX(RUNTIME.TrialCompleteIdx(i)).GetTagVal(RUNTIME.TrialCompleteStr{i});
        end
        RUNTIME.ON_HOLD(i) = ~TCtag;
    end
    
    if RUNTIME.ON_HOLD(i), continue; end
    
    





    
    % Collect Buffer if available
    if isfield(RUNTIME,'AcqBufferStr')
        % TODO: determine if a buffer actually exists
        try
            bufferSize = AX(RUNTIME.AcqBufferSizeIdx(i)).GetTagVal(RUNTIME.AcqBufferSizeStr{i});
            RUNTIME.TRIALS(i).AcqBuffer = AX(RUNTIME.AcqBufferIdx(i)).ReadTagV(RUNTIME.AcqBufferStr{i},0,bufferSize);
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
        vprintf(0,me);
    end
    
    
    



    
    
    % Increment TRIALS.TrialCount for the selected trial index
    RUNTIME.TRIALS(i).TrialCount(RUNTIME.TRIALS(i).NextTrialID) = ...
        RUNTIME.TRIALS(i).TrialCount(RUNTIME.TRIALS(i).NextTrialID) + 1;

    

    
    
    
    

    % vvvvvvvvvvvvv  NEW TRIAL SEQUENCE  vvvvvvvvvvvvv
    vprintf(2,'Triggering trial on box %d',i)

    % 1. Send trigger to reset components before updating parameters
    RUNTIME.HW.trigger(RUNTIME.CORE(i).ResetTrig);

    % 2. Update parameter tags
    % TO DO: UPDATE PROTOCOL STRUCTURE AND MAKE THIS GENEREALLY MORE
    % EFFICIENT
    trials = RUNTIME.TRIALS(i).trials(RUNTIME.TRIALS(i).NextTrialID,:);
    wp = RUNTIME.TRIALS.writeparams;
    P = RUNTIME.HW.find_parameter(wp);
    for j = 1:length(P), P(j).Value = trials{j}; end

    % 3. Trigger first new trial
    RUNTIME.HW.trigger(RUNTIME.CORE(i).NewTrial);


end













