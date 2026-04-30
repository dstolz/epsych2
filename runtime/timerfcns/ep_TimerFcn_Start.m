function RUNTIME = ep_TimerFcn_Start(RUNTIME,CONFIG)
% RUNTIME = ep_TimerFcn_Start(RUNTIME,CONFIG)
% Initialize runtime state and trial selectors before an experiment starts.
%
% Parameters:
%	RUNTIME	- Runtime state struct to populate for the upcoming session.
%	CONFIG	- Per-subject configuration array with compiled protocols.
%
% Returns:
%	RUNTIME	- Updated runtime state ready for timer-driven execution.
% 
% Copyright (C) 2019  Daniel Stolzberg, PhD
% updated for hardware abstraction 2024 DS


E = EPsychInfo;

RUNTIME.NSubjects = length(CONFIG);

for i = 1:RUNTIME.NSubjects
    C = CONFIG(i);

    compiled = C.PROTOCOL.COMPILED;
    selectorConfig = struct('trialFunc', C.PROTOCOL.Options.trialFunc);

    RUNTIME.TRIALS(i).parameters    = compiled.parameters;
    RUNTIME.TRIALS(i).trials        = compiled.trials;
    RUNTIME.TRIALS(i).selector      = epsych.TrialSelector.create(selectorConfig);
    RUNTIME.TRIALS(i).selector.initialize(RUNTIME.TRIALS(i));
    RUNTIME.TRIALS(i).selector.setRuntime(RUNTIME, i);
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



end






for i = 1:RUNTIME.NSubjects
    % Initialize first trial using selector
    RUNTIME.TRIALS(i).TrialIndex = 1;
    RUNTIME.TRIALS(i).NextTrialID = RUNTIME.TRIALS(i).selector.selectNext(RUNTIME.TRIALS(i));



    RUNTIME.resolveCoreParameters(i);






    RUNTIME.dispatchNextTrial(i);

end











