function smoke_test_phaseselector_select_parameters()
% smoke_test_phaseselector_select_parameters()
% Loading a chosen subset of a phase's parameters.
%
%   1. SelectParametersOnLoad: default off, "Load..." when on, the right-click
%      toggle, and that only the operator's toggle is remembered
%   2. Exclude by name leaves the parameter exactly as it was -- value, range
%      -- and reconciles its Values so the scheduled recompile keeps what it is
%      running (including a deferred trial-table commit), not its design value
%   3. The same load without Exclude still loads everything
%   4. readParameters' Exclude and Excluded output directly; an unknown name
%   5. gui.selectPhaseParameters on its own: filtering, check/uncheck, Check
%      None, Cancel, Include, the nothing-changes case
%   6. The chooser end to end from Load: what it lists, unchecking, Cancel
%      loading nothing, Exclude pre-unchecking
%
% The dialog blocks in uiwait, so sections 5 and 6 drive it from a timer. Run
% under -batch (a Software-only runtime; a visible uifigure because
% uiprogressdlg refuses a hidden one):
%
%   matlab -batch "run('tmp/smoke_test_phaseselector_select_parameters.m')"

here = fileparts(mfilename('fullpath'));
if exist('gui.selectPhaseParameters', 'file') ~= 2
    run(fullfile(here, '..', 'epsych_startup.m'));
end

tmpDir = tempname; mkdir(tmpDir);
cleanupTmp = onCleanup(@() rmdir(tmpDir, 's'));

% PhaseSelector prefers its remembered directory over the constructor
% argument, and remembers the operator's chooser setting; neither may leak
% in from, or out to, the machine running this.
prefGroup = 'epsych2_gui_PhaseSelector';
cleanupPrefs = {isolatePref(prefGroup, 'LastPhasePath'), ...
    isolatePref(prefGroup, 'SelectParametersOnLoad')};

[rt, proto] = makeRuntime(tmpDir);
pDelay = rt.find_parameter('StimDelay');
pDepth = rt.find_parameter('Depth');
pLevel = rt.find_parameter('Level');

% The phase: StimDelay 250 in [0 1000], Depth -10 in [-60 0], Level roved
% over four levels. The trial table is synced too, because
% writeParametersProtocol saves the COMMITTED trial-table value over Value.
setCommitted(pDelay, 250);
setCommitted(pDepth, -10);
pDepth.Min = -60;
pLevel.Values = {1 2 3 4};
phaseFile = fullfile(tmpDir, 'phaseA.eprot');
rt.writeParametersProtocol(phaseFile, "phase A");

fig = uifigure('Visible', 'on');
cleanupFig = onCleanup(@() delete(fig));
ps = gui.components.PhaseSelector(rt, tmpDir);
h  = ps.createGUI(uipanel(fig));

driverLog = {};   % what a dialog driver saw, for the assertions after it
dialogError = '';


%% 1. SelectParametersOnLoad and the Load button ---------------------------
assert(~ps.SelectParametersOnLoad, 'SelectParametersOnLoad should default to false');
assert(strcmp(h.LoadPhase.Text, 'Load'), 'default Load text changed: "%s"', h.LoadPhase.Text);
menuToggle = findall(h.LoadPhase.ContextMenu, 'Text', 'Always Choose Before Loading');
menuOnce   = findall(h.LoadPhase.ContextMenu, 'Text', 'Choose Parameters to Load...');
assert(isscalar(menuToggle) && isscalar(menuOnce), 'the Load button should carry both menu items');
assert(~logical(menuToggle.Checked), 'the toggle should start unchecked');

ps.SelectParametersOnLoad = true;
assert(strcmp(h.LoadPhase.Text, 'Load...'), 'a dialog-first Load should read "Load...", got "%s"', h.LoadPhase.Text);
assert(logical(menuToggle.Checked), 'the menu should follow the property');
assert(~ispref(prefGroup, 'SelectParametersOnLoad'), 'setting the property from code must not be remembered');
selectPhase('phaseA');
assert(strcmp(h.LoadPhase.Text, 'Load... *'), 'staged dialog-first text wrong: "%s"', h.LoadPhase.Text);
ps.SelectParametersOnLoad = false;
assert(strcmp(h.LoadPhase.Text, 'Load *'), 'turning it off should keep the staged mark: "%s"', h.LoadPhase.Text);

feval(menuToggle.MenuSelectedFcn, menuToggle, []);
assert(ps.SelectParametersOnLoad && getpref(prefGroup, 'SelectParametersOnLoad'), ...
    'the operator''s toggle should set and remember the choice');
ps2 = gui.components.PhaseSelector(rt, tmpDir);
assert(ps2.SelectParametersOnLoad, 'a new instance should reopen with the remembered choice');
delete(ps2);
feval(menuToggle.MenuSelectedFcn, menuToggle, []);
assert(~ps.SelectParametersOnLoad && ~getpref(prefGroup, 'SelectParametersOnLoad'), ...
    'toggling back should clear and remember that too');
fprintf('PASS: 1. SelectParametersOnLoad, button text, remembered toggle\n');


%% 2. Exclude by name leaves the parameter exactly as it is ----------------
resetLive();
% A deferred commit: the trial table holds 77, the parameter still 5.
col = rt.TRIALS(1).writeParamIdx.StimDelay;
rt.TRIALS(1).trials(:, col) = {77};
rt.TRIALS(1).RECOMPILE_REQUESTED = false;
nNotes = numel(rt.NOTES.Records);

loadPhase(Exclude = "StimDelay");

assert(isequal(pDepth.Value, -10) && pDepth.Min == -60, 'Depth should have loaded (value and range)');
assert(isequal(pLevel.Values, {1 2 3 4}), 'Level''s levels should have loaded');
assert(isequal(pDelay.Value, 5), 'an excluded parameter''s Value must not move (got %g)', pDelay.Value);
assert(pDelay.Max == 500, 'an excluded parameter''s range must not move (Max %g)', pDelay.Max);
assert(isequal(pDelay.Values, {77}), ...
    'an excluded parameter''s Values should carry the committed value across the recompile');
assert(all(cellfun(@(c) isequal(c, 77), rt.TRIALS(1).trials(:, col))), ...
    'the excluded column must not be rewritten by the load');
assert(rt.TRIALS(1).RECOMPILE_REQUESTED, 'the load should still schedule a recompile');

[trials, idx] = recompile();
assert(all(cellfun(@(c) isequal(c, 77), trials(:, idx.StimDelay))), ...
    'the recompile must reproduce the kept value, not revert it');
assert(all(cellfun(@(c) isequal(c, -10), trials(:, idx.Depth))), 'the recompile should carry the loaded Depth');

newText = strjoin(cellstr(string({rt.NOTES.Records(nNotes+1:end).Text})), ' | ');
assert(contains(newText, 'kept as they were: StimDelay') && ~contains(newText, 'updated: StimDelay'), ...
    'the session note should name what was kept, got: %s', newText);
assert(isequal(rt.Phase(end).Excluded, "StimDelay"), 'RUNTIME.Phase should record the exclusion');
assert(any(contains(string(h.Description.Text), 'kept as they were')), 'the description should say something was kept');
fprintf('PASS: 2. Exclude leaves value and range alone; Values reconciled for the recompile\n');


%% 3. The same load without Exclude loads everything -----------------------
resetLive();
loadPhase();
assert(isequal(pDelay.Value, 250) && pDelay.Max == 1000 && isequal(pDelay.Values, {250}), ...
    'a plain load should restore StimDelay in full');
assert(~any(contains(string(h.Description.Text), 'kept as they were')), 'nothing was kept this time');
assert(isempty(rt.Phase(end).Excluded), 'no exclusion should be recorded');
fprintf('PASS: 3. a plain load still loads everything\n');


%% 4. readParameters directly; an unknown name -----------------------------
resetLive();
[P, kept] = rt.readParameters(phaseFile, Exclude = pDelay);
assert(isscalar(kept) && kept == pDelay, 'Excluded should return the parameter it kept');
assert(~any(P == pDelay), 'the excluded parameter must not be in P');
assert(isequal(pDelay.Value, 5) && isequal(pDepth.Value, -10), 'readParameters Exclude');
[~, kept] = rt.readParameters(phaseFile);
assert(isempty(kept) && isa(kept, 'hw.Parameter'), 'no Exclude, nothing excluded');

resetLive();
loadPhase(Exclude = "NoSuchParameter");
assert(isequal(pDelay.Value, 250), 'an unknown name should not stop the rest loading');
fprintf('PASS: 4. readParameters Exclude/Excluded; unknown names ignored\n');


%% 5. gui.selectPhaseParameters on its own ----------------------------------
rows = table(["A";"B";"C";"D"], ["a";"";"c";"d"], ["1";"0";"5";"x"], ["2";"0";"5";"x"], ...
    ["ms";"";"";""], ["";"range [0, 1] -> [0, 2]";"";""], ["M";"M";"M";"M"], [true;false;false;false], ...
    'VariableNames', {'Parameter','Description','Current','New','Unit','Changes','Module','ValueChanged'});

inc = runDialog(@() gui.selectPhaseParameters(rows, PhaseName = "P5"), @(d) uncheckRow(d, "A"));
assert(isequal(driverLog{1}, ["A";"B"]), 'only the two changed rows should be listed first');
assert(isequal(inc, [false; true; true; true]), 'unchecking A should exclude only A');

inc = runDialog(@() gui.selectPhaseParameters(rows), @(d) showAllThenUncheck(d, "C"));
assert(isequal(driverLog{1}, ["A";"B";"C";"D"]), 'Show unchanged should list every row');
assert(isequal(inc, [true; true; false; true]), 'an unchanged row can be unchecked too');

% Check None acts on the rows listed; hidden unchanged rows keep their checks.
inc = runDialog(@() gui.selectPhaseParameters(rows), @(d) checkNoneThenLoad(d));
assert(isequal(inc, [false; false; true; true]), 'Check None should uncheck only the listed rows');

inc = runDialog(@() gui.selectPhaseParameters(rows), @(d) checkNoneThenCancel(d));
assert(isequal(driverLog{1}, 'off'), 'Load should be disabled with nothing checked');
assert(isempty(inc), 'Cancel should return []');

inc = runDialog(@() gui.selectPhaseParameters(rows, Include = [true; false; true; true]), ...
    @(d) clickButton(d, 'Load'));
assert(isequal(inc, [true; false; true; true]), 'Include should set the initial checks');

quiet = rows; quiet.ValueChanged(:) = false; quiet.Changes(:) = "";
inc = runDialog(@() gui.selectPhaseParameters(quiet), @(d) inspectAndAccept(d));
assert(isequal(driverLog{1}.Parameter, ["A";"B";"C";"D"]), 'with nothing changing, every row should be listed');
assert(all(inc), 'accepting untouched should load everything');
fprintf('PASS: 5. gui.selectPhaseParameters filtering, checks, Cancel, Include\n');


%% 6. The chooser end to end from Load --------------------------------------
resetLive();
nNotes = numel(rt.NOTES.Records);
phaseBefore = ps.CurrentPhase;
ps.CurrentPhase = 0;
runDialog(@() loadPhase(SelectParameters = true), @(d) clickButton(d, 'Cancel'));
assert(isequal(pDelay.Value, 5) && isequal(pDepth.Value, -2) && pDepth.Min == -40, ...
    'a cancelled chooser must load nothing');
assert(ps.CurrentPhase == 0 && numel(rt.NOTES.Records) == nNotes, ...
    'a cancelled chooser must leave no trace of a load');
ps.CurrentPhase = phaseBefore;

runDialog(@() loadPhase(SelectParameters = true), @(d) inspectAndUncheck(d, "StimDelay"));
D = driverLog{1};
rowOf = @(name) D(D.Parameter == name, :);
assert(rowOf("StimDelay").Current == "5" && rowOf("StimDelay").New == "250", ...
    'StimDelay row should read 5 -> 250');
assert(contains(rowOf("StimDelay").("Other Changes"), "range [0, 500]"), ...
    'StimDelay''s range change should be noted, got "%s"', rowOf("StimDelay").("Other Changes"));
assert(contains(rowOf("Depth").("Other Changes"), "range [-40, 0]"), 'Depth range note missing');
assert(contains(rowOf("Level").("Other Changes"), "levels [1 2 3]"), ...
    'Level levels note missing, got "%s"', rowOf("Level").("Other Changes"));
assert(all(D.Load), 'every box should start checked');
assert(~any(D.Parameter == "TrialType"), 'TrialType is never loaded, so never listed');
assert(isequal(pDelay.Value, 5) && pDelay.Max == 500, 'the unchecked parameter must be left alone');
assert(isequal(pDepth.Value, -10), 'the checked ones should load');

resetLive();
runDialog(@() loadPhase(SelectParameters = true, Exclude = "Depth"), @(d) inspectAndAccept(d));
D = driverLog{1};
assert(~D.Load(D.Parameter == "Depth") && D.Load(D.Parameter == "StimDelay"), ...
    'Exclude should pre-uncheck its parameters in the chooser');
assert(isequal(pDepth.Value, -2) && isequal(pDelay.Value, 250), 'the chooser''s answer should be what loads');
fprintf('PASS: 6. the chooser from Load: rows, uncheck, Cancel, Exclude pre-unchecks\n');

fprintf('ALL PASS: smoke_test_phaseselector_select_parameters\n');


    % ---------------------------------------------------------------------
    function setCommitted(p, v)
        p.Value = v;
        rt.updateTrialsFromParameters(p);
    end

    function resetLive()
        % The session as the operator left it: nothing from the phase.
        pDelay.Min = 0;  pDelay.Max = 500;  pDelay.Values = {5};
        pDepth.Min = -40; pDepth.Max = 0;   pDepth.Values = {-2};
        pLevel.Values = {1 2 3};
        setCommitted(pDelay, 5);
        setCommitted(pDepth, -2);
    end

    function selectPhase(name)
        h.PhaseSelect.Value = name;
        evalc('ps.onPhaseSelectionChanged(h.PhaseSelect);');
    end

    function loadPhase(varargin)
        selectPhase('phaseA');
        evalc('ps.loadPhaseParameters([], varargin{:});');
    end

    function [trials, idx] = recompile()
        proto.compile();
        [~, trials, ~, idx] = epsych.Runtime.compiledTrialColumns(proto.COMPILED);
    end

    function varargout = runDialog(call, action)
        % Answer the chooser the way an operator would, from a timer: it
        % blocks in uiwait, which keeps servicing timers.
        driverLog = {};
        dialogError = '';
        t = timer(ExecutionMode = 'fixedSpacing', Period = 0.2, StartDelay = 0.2, ...
            TasksToExecute = 100, Name = 'selectParametersDriver', ...
            TimerFcn = @(src, ~) tick(src, action));
        cleanupTimer = onCleanup(@() delete(t));
        start(t);
        if nargout > 0
            [varargout{1:nargout}] = call();
        else
            call();
        end
        stop(t);
        assert(isempty(dialogError), 'dialog driver failed: %s', dialogError);
        assert(isempty(findDialog()), 'the chooser should be closed once it returns');
    end

    function tick(src, action)
        d = findDialog();
        % The dialog is built hidden and shown once complete.
        if isempty(d) || ~strcmp(d.Visible, 'on')
            return
        end
        stop(src);
        try
            action(d);
        catch ME
            dialogError = ME.message;
            delete(d);   % never leave the test blocked in uiwait
        end
    end

    function uncheckRow(d, name)
        tbl = findall(d, 'Type', 'uitable');
        driverLog{1} = tbl.Data.Parameter;
        editCheck(tbl, name, false);
        clickButton(d, 'Load');
    end

    function showAllThenUncheck(d, name)
        cb = findall(d, 'Type', 'uicheckbox');
        cb.Value = true;
        feval(cb.ValueChangedFcn, cb, []);
        tbl = findall(d, 'Type', 'uitable');
        driverLog{1} = tbl.Data.Parameter;
        editCheck(tbl, name, false);
        clickButton(d, 'Load');
    end

    function checkNoneThenLoad(d)
        clickButton(d, 'Check None');
        clickButton(d, 'Load');
    end

    function checkNoneThenCancel(d)
        cb = findall(d, 'Type', 'uicheckbox');
        cb.Value = true;
        feval(cb.ValueChangedFcn, cb, []);
        clickButton(d, 'Check None');
        b = findall(d, '-isa', 'matlab.ui.control.Button', 'Text', 'Load');
        driverLog{1} = char(b.Enable);
        clickButton(d, 'Cancel');
    end

    function inspectAndUncheck(d, name)
        cb = findall(d, 'Type', 'uicheckbox');
        cb.Value = true;
        feval(cb.ValueChangedFcn, cb, []);
        tbl = findall(d, 'Type', 'uitable');
        driverLog{1} = tbl.Data;
        editCheck(tbl, name, false);
        clickButton(d, 'Load');
    end

    function inspectAndAccept(d)
        tbl = findall(d, 'Type', 'uitable');
        driverLog{1} = tbl.Data;
        clickButton(d, 'Load');
    end
end


function editCheck(tbl, name, tf)
% Tick or untick one row's Load box the way a click would report it.
r = find(tbl.Data.Parameter == name, 1);
assert(~isempty(r), 'no row "%s" in the chooser', name);
feval(tbl.CellEditCallback, tbl, struct('Indices', [r 1], 'NewData', tf));
end


function clickButton(fig, text)
b = findall(fig, '-isa', 'matlab.ui.control.Button', 'Text', text);
feval(b(1).ButtonPushedFcn, b(1), []);
end


function d = findDialog()
figs = findall(groot, 'Type', 'figure');
d = figs(startsWith(string({figs.Name}), 'Load Phase'));
if ~isempty(d), d = d(1); end
end


function c = isolatePref(group, key)
% Remove a preference for the duration of the test, restoring it after.
if ispref(group, key)
    saved = getpref(group, key);
    rmpref(group, key);
    c = onCleanup(@() setpref(group, key, saved));
else
    c = onCleanup(@() rmprefIfSet(group, key));
end
end


function rmprefIfSet(group, key)
if ispref(group, key), rmpref(group, key); end
end


function [rt, P] = makeRuntime(tmpDir)
% Software-only session built the way a real run is (see
% smoke_test_phaseselector_regenerate).
P = epsych.Protocol(Name='PhaseSelectParams', Info='phase parameter-selection smoke test');

P.addParameter('Software','TrialType',[0 1],Type='Integer');
P.addParameter('Software','StimDelay',5,Type='Float');
P.addParameter('Software','Depth',-2,Type='Float');
P.addParameter('Software','Level',[1 2 3],Type='Integer');

sw = P.findInterface('Software');
sw.add_parameter('x_NewTrial_1',      0, isTrigger=true);
sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);

p = sw.find_parameter('StimDelay');
p.Min = 0;
p.Max = 1000;
p = sw.find_parameter('Depth');
p.Min = -40;
p.Max = 0;

P.compile();

rt = epsych.Runtime;
rt.isTest          = true;
rt.EVENTS          = epsych.EventHub;
rt.Interfaces      = P.Interfaces;
rt.Protocol        = P;
rt.DefaultDataPath = tmpDir;
rt.TempDataDir     = tmpDir;

subject = epsych.DefaultSubject(struct('Name','PhaseSelectSubject', ...
    'Species','Mouse', 'Sex','Unknown', 'BoxID',1));

rt = ep_TimerFcn_Start(rt, struct('PROTOCOL',P,'SUBJECT',subject));
end
