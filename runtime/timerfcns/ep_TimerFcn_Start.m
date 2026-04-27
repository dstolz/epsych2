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
if ~isfield(RUNTIME,'TempDataDir') || ~isfolder(RUNTIME.TempDataDir)
    RUNTIME.TempDataDir = fullfile(fileparts(E.root),'DATA');
end
if ~isfolder(RUNTIME.TempDataDir), mkdir(RUNTIME.TempDataDir); end

RUNTIME.NSubjects = length(CONFIG);

RUNTIME.HELPER = epsych.Helper;

for i = 1:RUNTIME.NSubjects
    C = CONFIG(i);

    snap = C.PROTOCOL.runtimeSnapshot();
    RUNTIME.TRIALS(i).writeparams   = snap.writeparams;
    RUNTIME.TRIALS(i).readparams    = snap.readparams;
    RUNTIME.TRIALS(i).trials        = snap.trials;
    RUNTIME.TRIALS(i).writeParamIdx = snap.writeParamIdx;
    RUNTIME.TRIALS(i).selector      = epsych.TrialSelector.create(snap.selectorConfig);
    RUNTIME.TRIALS(i).selector.initialize(snap);
    RUNTIME.TRIALS(i).UserData      = [];
    RUNTIME.TRIALS(i).Subject       = C.SUBJECT;
    RUNTIME.TRIALS(i).BoxID         = C.SUBJECT.BoxID;

    RUNTIME.TRIALS(i).FORCE_TRIAL = false;
    RUNTIME.TRIALS(i).RECOMPILE_REQUESTED = false;




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

    assert(isfolder(RUNTIME.TempDataDir),'Invalid Data Directory "%s"',RUNTIME.TempDataDir)
    RUNTIME.DataFile(i) = fullfile(RUNTIME.TempDataDir,dfn);

    if exist(RUNTIME.DataFile(i),'file')
        vprintf(3, 'Data file already exists for runtime: %s. Deleting existing file.', RUNTIME.DataFile(i))
        oldstate = recycle('on');
        delete(RUNTIME.DataFile(i));
        recycle(oldstate);
    end
    vprintf(3, 'Creating temporary data file for runtime: %s', RUNTIME.DataFile(i))
    save(RUNTIME.DataFile(i),'info','-v6');



    % Initialize default data filename
    vprintf(3, 'Initializing data filename for subject "%s" on box %d', RUNTIME.TRIALS(i).Subject.Name, RUNTIME.TRIALS(i).Subject.BoxID)
    sn = RUNTIME.TRIALS(i).Subject.Name;
    pth = fullfile(RUNTIME.dfltDataPath,sn);
    RUNTIME.TRIALS(i).DataFilename = epsych.RunExpt.defaultFilename(pth,sn);

    RUNTIME.ON_HOLD(i) = false;

    % make HW object handles available in TRIALS structure
    RUNTIME.TRIALS(i).HW = RUNTIME.HW; 

    % SOFTWARE INTERFACE
    RUNTIME.S = hw.Software;
    % addlistener(RUNTIME.HW,'mode','PostSet',@RUNTIME.S.mode_handler);

  

end






for i = 1:RUNTIME.NSubjects
    % Initialize first trial using selector
    RUNTIME.TRIALS(i).TrialIndex = 1;
    RUNTIME.TRIALS(i).NextTrialID = RUNTIME.TRIALS(i).selector.selectNext(RUNTIME.TRIALS(i));



    % SIMPLIFY ACCESS TO BUILTIN TRIGGERS
    bmn = ["RespCode","TrigState","NewTrial","ResetTrig","TrialNum", "TrialComplete"];
    for cc = bmn
        trigStr = sprintf('_%s~%d',cc,RUNTIME.TRIALS(i).Subject.BoxID);
        p = RUNTIME.HW.find_parameter(trigStr,includeInvisible=true,silenceParameterNotFound=true);
        RUNTIME.CORE(i).(cc) = p;
    end

    % Protocol already loaded by ExptDispatch; use it directly
    RUNTIME.TRIALS(i).protocol = CONFIG(i).PROTOCOL;


    % vvvvvvvvvvvvv  NEW TRIAL SEQUENCE  vvvvvvvvvvvvv
    vprintf(2,'Setting up first trial on box %d',i)

    % ignore parameters with an asterisk (*) prefix
    wp = RUNTIME.TRIALS(i).writeparams;
    wpind = ~startsWith(wp,'*');

    % 1. Send trigger to reset components before updating parameters
    RUNTIME.HW.trigger(RUNTIME.CORE(i).ResetTrig);
    
    % 2. Update parameter tags
    % TO DO: UPDATE PROTOCOL STRUCTURE AND MAKE THIS GENERALLY MORE EFFICIENT
    trials = RUNTIME.TRIALS(i).trials(RUNTIME.TRIALS(i).NextTrialID,wpind);

    
    P = RUNTIME.HW.find_parameter(wp(wpind),includeInvisible=true);
    [P.Value] = deal(trials{:});

    % 3. Trigger first new trial
    RUNTIME.HW.trigger(RUNTIME.CORE(i).NewTrial);

    % 4. Notify whomever is listening of new trial
    RUNTIME.HELPER.notify('NewTrial');

end











