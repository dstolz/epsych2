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

    % Trial table and the column map that names its columns, installed
    % together: writeparams is a column-ordered cell of valid parameter
    % names and writeParamIdx maps each valid-name to its trial column.
    % Consumers (gui.Parameter_Update, updateTrialsFromParameters,
    % eval_*_training_mode, gui.NextTrial) rely on these to locate writable
    % columns, so the safe-boundary recompile must refresh them the same way.
    [T(i).parameters, T(i).trials, T(i).writeparams, T(i).writeParamIdx] = ...
        epsych.Runtime.compiledTrialColumns(compiled);
    T(i).selector      = epsych.TrialSelector.create(selectorConfig);
    T(i).selector.initialize(T(i));
    T(i).selector.setRuntime(RUNTIME, i);
    T(i).Subject       = C.SUBJECT;
    T(i).BoxID         = C.SUBJECT.BoxID;

    % The safe-boundary recompile (ep_TimerFcn_RunTime) recompiles this
    % handle when RECOMPILE_REQUESTED is set (operator request or phase load).
    T(i).protocol      = C.PROTOCOL;

    T(i).FORCE_TRIAL = false;
    T(i).RECOMPILE_REQUESTED = false;

    
    % Create data file for saving data during runtime in case there is a problem
    % * this file is automatically overwritten

    % Create data file info structure
    info.Subject = T(i).Subject;
    info.CompStartTimestamp = datetime("now");
    info.EPsychMeta = E.meta;
    info.isTest = RUNTIME.isTest;
    
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
    % RunExpt reserves these before the run so the webcam recording carries the
    % same name; generate one only when Start is invoked without a reservation.
    if numel(RUNTIME.SessionDataFilename) >= i && strlength(RUNTIME.SessionDataFilename(i)) > 0
        T(i).DataFilename = char(RUNTIME.SessionDataFilename(i));
    else
        sn = T(i).Subject.Name;
        pth = fullfile(RUNTIME.dfltDataPath,sn);
        T(i).DataFilename = epsych.RunExpt.defaultFilename(pth,sn);
    end


    % Initialize first trial using selector
    T(i).TrialIndex = 1;
    T(i).NextTrialID = T(i).selector.selectNext(T(i));
end


RUNTIME.TRIALS = T;









