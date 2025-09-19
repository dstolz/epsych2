function RUNTIME = ep_TimerFcn_Start(RUNTIME,CONFIG)
% RUNTIME = ep_TimerFcn_Start(RUNTIME,CONFIG)
% 
% Default Start timer function
% 
% Initialize parameters and take care of some other things just before
% beginning experiment
% 
% Use ep_PsychConfig GUI to specify custom timer function.
% 
% Copyright (C) 2019  Daniel Stolzberg, PhD
% updated for hardware abstraction 2024 DS


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

    RUNTIME.TRIALS(i).trials       = sortrows(C.PROTOCOL.COMPILED.trials);
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

    RUNTIME.TRIALS(i).FORCE_TRIAL = false;

    % make it a bit easier to find writeparameters
    for k = 1:length(RUNTIME.TRIALS(i).writeparams)
        wp = RUNTIME.TRIALS(i).writeparams{k};
        wpn = matlab.lang.makeValidName(wp);
        RUNTIME.TRIALS(i).writeParamIdx.(wpn) = find(ismember(RUNTIME.TRIALS(i).writeparams,wp));
    end




    % Create data file for saving data during runtime in case there is a problem
    % * this file is automatically overwritten

    % Create data file info structure
    info.Subject = RUNTIME.TRIALS(i).Subject;
    info.CompStartTimestamp = datetime("now");
    info.EPsychMeta = E.meta;
    [~, computer] = system('hostname'); 
    info.Computer = strtrim(computer);
    
    dfn = sprintf('RUNTIME_DATA_%s_Box_%02d_%s.mat', ...
        RUNTIME.TRIALS(i).Subject.Name, ...
        RUNTIME.TRIALS(i).Subject.BoxID, ...
        datetime('now',Format='yyMMddHHmmSS'));
    RUNTIME.DataFile{i} = fullfile(RUNTIME.DataDir,dfn);

    if exist(RUNTIME.DataFile{i},'file')
        oldstate = recycle('on');
        delete(RUNTIME.DataFile{i});
        recycle(oldstate);
    end
    save(RUNTIME.DataFile{i},'info','-v6');



    % Initialize default data filename
    sn = RUNTIME.TRIALS(i).Subject.Name;
    pth = fullfile(RUNTIME.dfltDataPath,sn);
    RUNTIME.TRIALS(i).DataFilename = ep_RunExpt2.defaultFilename(pth,sn);

    RUNTIME.onHold(i) = false;


    % Initialize data structure
    rpn = RUNTIME.TRIALS(i).readparams;
    rpn = matlab.lang.makeValidName(rpn);
    for p = string(rpn)
        RUNTIME.TRIALS(i).DATA.(p) = [];
    end    
    RUNTIME.TRIALS(i).DATA.ResponseCode = [];
    RUNTIME.TRIALS(i).DATA.TrialID = [];
    RUNTIME.TRIALS(i).DATA.inaccurateTimestamp = [];
    
    RUNTIME.TRIALS(i).HW = RUNTIME.HW; % make HW object handles available in TRIALS structure


    % SOFTWARE INTERFACE
    RUNTIME.S = hw.Software;
    RUNTIME.TRIALS(i).S = RUNTIME.S; % make S object handle available in TRIALS structure
    % addlistener(RUNTIME.HW,'mode','PostSet',@RUNTIME.S.mode_handler);

  
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
        p = RUNTIME.HW.find_parameter(trigStr,includeInvisible=true,silenceParameterNotFound=true);
        RUNTIME.CORE(i).(cc) = p;
    end

    load(RUNTIME.TRIALS(i).protocol_fn,'-mat');
    RUNTIME.TRIALS(i).protocol = protocol;


    % vvvvvvvvvvvvv  NEW TRIAL SEQUENCE  vvvvvvvvvvvvv
    vprintf(2,'Setting up first trial on box %d',i)

    % 1. Send trigger to reset components before updating parameters
    RUNTIME.HW.trigger(RUNTIME.CORE(i).ResetTrig);

    % 2. Update parameter tags
    % TO DO: UPDATE PROTOCOL STRUCTURE AND MAKE THIS GENEREALLY MORE EFFICIENT
    trials = RUNTIME.TRIALS(i).trials(RUNTIME.TRIALS(i).NextTrialID,:);
    P = RUNTIME.HW.find_parameter(RUNTIME.TRIALS.writeparams,includeInvisible=true);
    [P.Value] = deal(trials{:});

    % 3. Trigger first new trial
    RUNTIME.HW.trigger(RUNTIME.CORE(i).NewTrial);

    % 4. Notify whomever is listening of new trial
    RUNTIME.HELPER.notify('NewTrial');

end











