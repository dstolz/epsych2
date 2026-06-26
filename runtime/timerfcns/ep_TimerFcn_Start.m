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

nSubjs = length(CONFIG);

T = struct([]);

for i = 1:nSubjs
    C = CONFIG(i);

    compiled = C.PROTOCOL.COMPILED;
    selectorConfig = struct('trialFunc', C.PROTOCOL.Options.trialFunc);

    T(i).parameters    = compiled.parameters;
    T(i).trials        = compiled.trials;

    % Write-parameter mapping: writeparams is a column-ordered cell of valid
    % parameter names; writeParamIdx maps each valid-name to its trial column.
    % Consumers (gui.Parameter_Update, updateTrialsFromParameters,
    % eval_*_training_mode) rely on these to locate writable columns.
    T(i).writeparams   = compiled.writeparams;
    T(i).writeParamIdx = struct();
    for w = 1:numel(compiled.writeparams)
        T(i).writeParamIdx.(compiled.writeparams{w}) = w;
    end
    T(i).selector      = epsych.TrialSelector.create(selectorConfig);
    T(i).selector.initialize(T(i));
    T(i).selector.setRuntime(RUNTIME, i);
    T(i).Subject       = C.SUBJECT;
    T(i).BoxID         = C.SUBJECT.BoxID;

    T(i).FORCE_TRIAL = false;
    T(i).RECOMPILE_REQUESTED = false;

    
    % Create data file for saving data during runtime in case there is a problem
    % * this file is automatically overwritten

    % Create data file info structure
    info.Subject = T(i).Subject;
    info.CompStartTimestamp = datetime("now");
    info.EPsychMeta = E.meta;
    
    dfn = sprintf('RUNTIME_DATA_%s_Box_%02d_%s.mat', ...
        T(i).Subject.Name, ...
        T(i).Subject.BoxID, ...
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
    vprintf(3, 'Initializing data filename for subject "%s" on box %d', T(i).Subject.Name, T(i).Subject.BoxID)
    sn = T(i).Subject.Name;
    pth = fullfile(RUNTIME.dfltDataPath,sn);
    T(i).DataFilename = epsych.RunExpt.defaultFilename(pth,sn);


    % Initialize first trial using selector
    T(i).TrialIndex = 1;
    T(i).NextTrialID = T(i).selector.selectNext(T(i));
end


RUNTIME.TRIALS = T;









