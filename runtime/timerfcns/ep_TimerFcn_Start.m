function RUNTIME = ep_TimerFcn_Start(CONFIG, RUNTIME, AX)
% RUNTIME = ep_TimerFcn_Start(CONFIG, RUNTIME, RP)
% RUNTIME = ep_TimerFcn_Start(CONFIG, RUNTIME, DA)
% RUNTIME = ep_TimerFcn_Start(CONFIG, RUNTIME, SYN)
% 
% Default Start timer function
% 
% Initialize parameters and take care of some other things just before
% beginning experiment
% 
% Use ep_PsychConfig GUI to specify custom timer function.
% 
% Daniel.Stolzberg@gmail.com 2019

% Copyright (C) 2019  Daniel Stolzberg, PhD

E = EPsychInfo;



% make temporary directory in current folder for storing data during
% runtime in case of a computer crash or Matlab error
if ~isfield(RUNTIME,'DataDir') || ~isfolder(RUNTIME.DataDir)
    RUNTIME.DataDir = fullfile(fileparts(E.root),'DATA');
end
if ~isfolder(RUNTIME.DataDir), mkdir(RUNTIME.DataDir); end

RUNTIME.NSubjects = length(CONFIG);

RUNTIME.HELPER = epsych.Helper;

for i = 1:RUNTIME.NSubjects
    C = CONFIG(i);

    RUNTIME.TRIALS(i).trials       = C.PROTOCOL.COMPILED.trials;
    RUNTIME.TRIALS(i).TrialCount   = zeros(size(RUNTIME.TRIALS(i).trials,1),1); 
    RUNTIME.TRIALS(i).activeTrials = true(size(RUNTIME.TRIALS(i).TrialCount));
    RUNTIME.TRIALS(i).UserData     = [];
    RUNTIME.TRIALS(i).trialfunc    = C.PROTOCOL.OPTIONS.trialfunc;
    RUNTIME.TRIALS(i).writeparams  = C.PROTOCOL.COMPILED.writeparams;
    RUNTIME.TRIALS(i).readparams   = C.PROTOCOL.COMPILED.readparams;

    RUNTIME.TRIALS(i).writeparams = cellfun(@(a) a(find(a=='.',1)+1:end),RUNTIME.TRIALS(i).writeparams,'uni',0);
    RUNTIME.TRIALS(i).readparams  = cellfun(@(a) a(find(a=='.',1)+1:end),RUNTIME.TRIALS(i).readparams,'uni',0);

    RUNTIME.TRIALS(i).Subject = C.SUBJECT;
    RUNTIME.TRIALS(i).BoxID = C.SUBJECT.BoxID; % make BoxID more easily accessible DJS 1/14/2016






    % Create data file for saving data during runtime in case there is a problem
    % * this file is automatically overwritten

    % Create data file info structure
    info.Subject = RUNTIME.TRIALS(i).Subject;
    info.CompStartTimestamp = datetime("now");
    info.EPsychMeta = E.meta;
    [~, computer] = system('hostname'); 
    info.Computer = strtrim(computer);
    
    dfn = sprintf('RUNTIME_DATA_%s_Box_%02d_%s.mat', ...
        genvarname(RUNTIME.TRIALS(i).Subject.Name), ...
        RUNTIME.TRIALS(i).Subject.BoxID,datetime('today',Format='MMM-dd-yyyy'));
    RUNTIME.DataFile{i} = fullfile(RUNTIME.DataDir,dfn);

    if exist(RUNTIME.DataFile{i},'file')
        oldstate = recycle('on');
        delete(RUNTIME.DataFile{i});
        recycle(oldstate);
    end
    save(RUNTIME.DataFile{i},'info','-v6');

    RUNTIME.ON_HOLD(i) = false;


    % Initialize data structure
    ptags = RUNTIME.HW.filter_parameters('Access','Read',testFcn=@contains);
    for p = ptags
        RUNTIME.TRIALS(i).DATA.(p.validName) = [];
    end    
    RUNTIME.TRIALS(i).DATA.ResponseCode = [];
    RUNTIME.TRIALS(i).DATA.TrialID = [];
    RUNTIME.TRIALS(i).DATA.ComputerTimestamp = [];
    
end






for i = 1:RUNTIME.NSubjects
    % Initialize first trial
    RUNTIME.TRIALS(i).TrialIndex = 1;
    try
        n = feval(RUNTIME.TRIALS(i).trialfunc,RUNTIME.TRIALS(i));
        if isstruct(n)
            RUNTIME.TRIALS(i).trials       = n.trials;
            RUNTIME.TRIALS(i).NextTrialID  = n.NextTrialID;
            RUNTIME.TRIALS(i).activeTrials = n.activeTrials;
            RUNTIME.TRIALS(i).UserData     = n.UserData;
        elseif isscalar(n) 
            RUNTIME.TRIALS(i).NextTrialID = n;
        else
            error('Invalid output from custom trial selection function ''%s''',RUNTIME.TRIALS(i).trialfunc)
        end
    catch me
        errordlg(sprintf('Error in Custom Trial Selection Function "%s" on line %d\n\n%s\n%s', ...
            me.stack(1).name,me.stack(1).line,me.identifier,me.message));
        rethrow(me)
    end
    RUNTIME.TRIALS(i).TrialCount(RUNTIME.TRIALS(i).NextTrialID) = 1;
    



    % SIMPLIFY ACCESS TO BUILTIN TRIGGERS
    bmn = ["RespCode","TrigState","NewTrial","ResetTrig","TrialNum", ...
        'TrialComplete','AcqBuffer','AcqBufferSize'];
    for cc = bmn
        trigStr = sprintf('_%s~%d',cc,RUNTIME.TRIALS(i).Subject.BoxID);
        p = RUNTIME.HW.find_parameter(trigStr,includeInvisible=true,silenceParamterNotFound=true);
        RUNTIME.CORE(i).(cc) = p;
    end




    % vvvvvvvvvvvvv  NEW TRIAL SEQUENCE  vvvvvvvvvvvvv

    load(RUNTIME.TRIALS(i).protocol_fn,'-mat');
    RUNTIME.TRIALS(i).protocol = protocol;


    vprintf(2,'Triggering first trial on box %d',i)

    % 1. Send trigger to reset components before updating parameters
    RUNTIME.HW.trigger(RUNTIME.CORE(i).ResetTrig);

    % 2. Update parameter tags
    % TO DO: UPDATE PROTOCOL STRUCTURE AND MAKE THIS GENEREALLY MORE
    % EFFICIENT
    trials = RUNTIME.TRIALS(i).trials(RUNTIME.TRIALS(i).NextTrialID,:);
    P = RUNTIME.HW.find_parameter(RUNTIME.TRIALS.writeparams);
    arrayfun(@(a,b) a.Parent.set_parameter(a,b{1}),P,trials);
    % for t = 1:length(wp)
    %     P.HW.set_parameter(wp{i},trials{t});
    % end

    % 3. Trigger first new trial
    RUNTIME.HW.trigger(RUNTIME.CORE(i).NewTrial);

    
end











