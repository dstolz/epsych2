function smoke_test_writeonly_parameter_reads()
% smoke_test_writeonly_parameter_reads()
% Gate on the framework never reading hw.Parameter.Value of a write-only
% parameter. get.Value on Access='Write' logs a critical '"<Name>" is a
% write-only parameter' record and returns NaN, so the expression machinery
% used to spam the log - in the Protocol Designer on every parameter edit, on
% every protocol save and load, and once per write-only sibling on every
% per-trial dispatch during a session.
%
% Also pins the replacement semantics: a write-only parameter's design-time
% stand-in is its first level (Values{1}), the same convention
% Protocol.dryRunExpressions/sweepExpressions and orderByDependencies use,
% not NaN.
%
%   matlab -batch "run('tmp/smoke_test_writeonly_parameter_reads.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

P = epsych.Protocol;
pGain  = P.addParameter('Software', 'Gain', 3, Access='Write');
P.addParameter('Software', 'Norm', 2, Access='Write');
pLevel = P.addParameter('Software', 'Level', 0);
P.addParameter('Software', 'RespWin', 100);

pd = epsych.ProtocolDesigner(P);
cleanupPd = onCleanup(@() localForceClose_(pd));

% ===== 0. Positive control: the detector sees a real write-only read =======
try
    before = localCountWriteOnlyRecords_();
    v = pGain.Value;
    assert(isnan(v), 'reading a write-only parameter should return NaN, got %s', mat2str(v));
    assert(localCountWriteOnlyRecords_() > before, ...
        'fixture: a direct write-only read must log, otherwise this test proves nothing');
    fprintf('PASS: 0. direct write-only read still logs (detector works)\n');
catch ME
    failures{end+1} = sprintf('0. positive control: %s', ME.message);
    fprintf('FAIL: 0. %s\n', ME.message);
end

% ===== A. Editing the Value column logs nothing ============================
try
    before = localCountWriteOnlyRecords_();
    pd.onParamEdited(localEditEvent_(pd, 'Level', 5, '10'));
    assert(isequal(pLevel.Values, {10}), 'Value edit should store 10');
    assert(localCountWriteOnlyRecords_() == before, ...
        'a Value edit logged %d write-only message(s)', localCountWriteOnlyRecords_() - before);
    fprintf('PASS: A. Value-column edit produces no write-only log records\n');
catch ME
    failures{end+1} = sprintf('A. value edit: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% ===== B. Editing the Expression column logs nothing =======================
try
    before = localCountWriteOnlyRecords_();
    pd.onParamEdited(localEditEvent_(pd, 'Level', 4, 'RespWin - 50'));
    assert(strcmp(char(pLevel.Expression), 'RespWin - 50'), ...
        'referencing expression should persist, got "%s"', pLevel.Expression);
    assert(localCountWriteOnlyRecords_() == before, ...
        'an Expression edit logged %d write-only message(s)', localCountWriteOnlyRecords_() - before);
    fprintf('PASS: B. Expression-column edit produces no write-only log records\n');
catch ME
    failures{end+1} = sprintf('B. expression edit: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. Refreshing and compiling log nothing =============================
% The same expression machinery runs on every table refresh and on compile,
% which is what a newly added parameter triggers once its name is accepted.
try
    before = localCountWriteOnlyRecords_();
    pd.refreshUI();
    pd.onCompile();
    assert(localCountWriteOnlyRecords_() == before, ...
        'refresh/compile logged %d write-only message(s)', localCountWriteOnlyRecords_() - before);
    fprintf('PASS: C. refresh and compile produce no write-only log records\n');
catch ME
    failures{end+1} = sprintf('C. refresh/compile: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end

% ===== D. A write-only reference resolves to its design-time value =========
% Before the fix Gain.Value came back NaN (and logged); it must now be the
% first design-time level, so the expression evaluates to a real number.
try
    before = localCountWriteOnlyRecords_();
    pd.onParamEdited(localEditEvent_(pd, 'Level', 4, 'Gain.Value * 2'));
    assert(isequal(pLevel.Values, {6}), ...
        'Gain.Value should stand in as the design value 3, got %s', mat2str([pLevel.Values{:}]));
    assert(localCountWriteOnlyRecords_() == before, ...
        'a write-only reference logged %d write-only message(s)', localCountWriteOnlyRecords_() - before);
    fprintf('PASS: D. Gain.Value resolves to the design-time level without logging\n');
catch ME
    failures{end+1} = sprintf('D. write-only reference: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end

% ===== E. Loading a protocol logs nothing ==================================
% Protocol.fromStruct re-evaluates expression parameters until they stop
% changing, and used to probe convergence by reading Value back - twice per
% pass per parameter, so a write-only expression parameter both spammed the
% log and (NaN never being isequal to itself) blocked the early exit.
try
    P2 = epsych.Protocol;
    P2.addParameter('Software', 'RespWin', 100);
    g = P2.addParameter('Software', 'Gain', 1, Access='Write');
    g.Expression = "RespWin / 10";
    n = P2.addParameter('Software', 'Norm', 1, Access='Write');
    n.Expression = "RespWin / 4";

    tmpFile = fullfile(tempdir, 'smoke_designer_writeonly.eprot');
    cleanupFile = onCleanup(@() localDeleteFile_(tmpFile));

    % toStruct used to serialize the NaN that get.Value returns, and fromStruct
    % assigns S.Value straight back, so a round trip left the parameter at NaN.
    S = g.toStruct();
    assert(isequal(S.Value, 1), ...
        'a write-only parameter should serialize its design value, got %s', mat2str(S.Value));

    before = localCountWriteOnlyRecords_();
    P2.save(tmpFile);
    epsych.Protocol.load(tmpFile);
    assert(localCountWriteOnlyRecords_() == before, ...
        'save/load logged %d write-only message(s)', localCountWriteOnlyRecords_() - before);
    fprintf('PASS: E. saving and loading a protocol produce no write-only log records\n');
catch ME
    failures{end+1} = sprintf('E. protocol load: %s', ME.message);
    fprintf('FAIL: E. %s\n', ME.message);
end

% ===== F. Runtime dispatch logs nothing ====================================
% The same messages appear while running an experiment, not just in the
% designer: resolveExpressionContext reads EVERY sibling to build the context,
% referenced or not, so each per-trial evaluation of any expression parameter
% used to read every write-only sibling on the module.
try
    P3 = epsych.Protocol;
    rw = P3.addParameter('Software', 'RespWin', 100);
    P3.addParameter('Software', 'Gain', 3, Access='Write');
    P3.addParameter('Software', 'Norm', 2, Access='Write');
    lvl = P3.addParameter('Software', 'Level', 0);
    lvl.Expression = "RespWin / 2";

    before = localCountWriteOnlyRecords_();
    for trial = 1:5
        rw.Value = 100 + 10 * trial;
        lvl.Value = 0;                    % per-trial dispatch re-evaluates
    end
    assert(isequal(lvl.Value, 75), ...
        'expression should track RespWin, expected 75, got %s', mat2str(lvl.Value));
    assert(localCountWriteOnlyRecords_() == before, ...
        '5 dispatches logged %d write-only message(s)', localCountWriteOnlyRecords_() - before);
    fprintf('PASS: F. per-trial expression dispatch produces no write-only log records\n');
catch ME
    failures{end+1} = sprintf('F. runtime dispatch: %s', ME.message);
    fprintf('FAIL: F. %s\n', ME.message);
end

% ===== G. ValueStr never reads back ========================================
% ValueStr is display text: GUIs poll it and the TDT backends logged it after
% every write, so reading Value inside it put one record per write-only
% parameter per trial into the log (stack seen on a live rig:
% get.Value <- get.ValueStr <- TDT_RPcox.set_parameter <- set.Value <-
% dispatchNextTrial). formatValue is the read-free path for callers that
% already hold the value.
try
    before = localCountWriteOnlyRecords_();
    str = pGain.ValueStr;
    assert(strcmp(strtrim(str), '3'), ...
        'ValueStr should show the design level 3, got "%s"', str);
    assert(strcmp(strtrim(pGain.formatValue(42)), '42'), ...
        'formatValue should format the value it is handed');
    assert(localCountWriteOnlyRecords_() == before, ...
        'ValueStr logged %d write-only message(s)', localCountWriteOnlyRecords_() - before);
    fprintf('PASS: G. ValueStr shows the design level without reading back\n');
catch ME
    failures{end+1} = sprintf('G. ValueStr: %s', ME.message);
    fprintf('FAIL: G. %s\n', ME.message);
end

% ===== H. Phase-load trial sync never reads back ===========================
% gui.PhaseSelector deliberately keeps write-only parameters in the change set
% and hands them to updateTrialsFromParameters, which read Value and wrote the
% resulting NaN into every trial row for that parameter.
try
    P4 = epsych.Protocol;
    P4.addParameter('Software', 'ToneLevel', [10 20 30], Type='Float');
    P4.addParameter('Software', 'Gain', 7, Access='Write');
    sw4 = P4.findInterface('Software');
    sw4.add_parameter('x_NewTrial_1',      0, isTrigger=true);
    sw4.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
    sw4.add_parameter('x_TrialComplete_1', 0, isTrigger=true);
    P4.compile();

    R4 = epsych.Runtime;
    R4.isTest = true;
    R4.HELPER = epsych.Helper;
    R4.Interfaces = P4.Interfaces;
    R4.Protocol = P4;
    dataDir = tempname; mkdir(dataDir);
    cleanupDataDir = onCleanup(@() rmdir(dataDir, 's'));
    R4.dfltDataPath = dataDir;
    R4.TempDataDir = dataDir;

    subject = epsych.DefaultSubject(struct('Name', 'WOSubject', ...
        'Species', 'Mouse', 'Sex', 'Unknown', 'BoxID', 1));
    R4 = ep_TimerFcn_Start(R4, struct('PROTOCOL', P4, 'SUBJECT', subject));

    % find_parameter's default filter drops write-only entries, so take the
    % handle straight off the live module.
    liveParams = [R4.Interfaces(1).Module(:).Parameters];
    pG = liveParams(strcmp({liveParams.Name}, 'Gain'));
    assert(isscalar(pG), 'fixture: Gain not found on the live interface');
    before = localCountWriteOnlyRecords_();
    R4.updateTrialsFromParameters(pG);
    assert(localCountWriteOnlyRecords_() == before, ...
        'trial sync logged %d write-only message(s)', localCountWriteOnlyRecords_() - before);

    col = R4.TRIALS(1).writeParamIdx.Gain;
    written = unique(cell2mat(R4.TRIALS(1).trials(:,col)));
    assert(isequal(written, 7), ...
        'trial table should carry the design level 7, not NaN; got %s', mat2str(written));
    fprintf('PASS: H. phase-load trial sync writes the design level, not NaN\n');
catch ME
    failures{end+1} = sprintf('H. trial sync: %s', ME.message);
    fprintf('FAIL: H. %s\n', ME.message);
end

% ===== Summary ============================================================
if isempty(failures)
    fprintf('\nALL PASS: nothing reads write-only parameter values\n');
else
    fprintf('\n%d FAILURE(S):\n', numel(failures));
    fprintf('  %s\n', failures{:});
    error('smoke:designerWriteOnlyLog', 'smoke test failed');
end

end


function n = localCountWriteOnlyRecords_()
% Number of '... is a write-only parameter' records in the session log so far.
logger = eplog.Logger.instance();
logger.flush();
logFile = logger.LogFile;
if isempty(logFile) || ~isfile(logFile)
    n = 0;
    return
end
txt = fileread(logFile);
n = numel(strfind(txt, 'is a write-only parameter'));
end


function localDeleteFile_(filePath)
if isfile(filePath)
    delete(filePath);
end
end


function evt = localEditEvent_(pd, parameterName, column, newData)
% Build a CellEditCallback-shaped event for the named parameter row.
row = find(cellfun(@(h) strcmp(h.Name, parameterName), pd.ParameterHandles), 1);
assert(~isempty(row), 'fixture: parameter %s not found in the designer table', parameterName);
evt = struct('Indices', [row, column], 'NewData', newData);
end


function localForceClose_(pd)
if isvalid(pd)
    warnState = warning('off', 'MATLAB:structOnObject');
    s = struct(pd);
    warning(warnState);
    figs = {s.Figure, s.InterfaceFigure, s.OptionsFigure, s.PreviewFigure, s.CheckCalcFigure};
    for idx = 1:numel(figs)
        if ~isempty(figs{idx}) && isvalid(figs{idx})
            delete(figs{idx});
        end
    end
end
end
