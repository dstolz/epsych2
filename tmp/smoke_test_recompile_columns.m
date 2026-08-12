function smoke_test_recompile_columns()
% smoke_test_recompile_columns()
% Regression test for the trial-table column map going stale across a
% recompile.
%
% TRIALS.writeParamIdx maps a parameter valid-name to its column of
% TRIALS.trials. The safe-boundary recompile in ep_TimerFcn_RunTime used to
% replace parameters and trials but keep the old writeparams/writeParamIdx,
% so a recompile that added a parameter shifted every later column while the
% map still pointed at the old ones. In the appetitive paradigm that showed
% up as "Depth = 20000" in the Next Trial panel: cl_AppetitiveStimDetect
% creates two runtime parameters (P_Catch_Current, CatchTrialsEnabled) at
% run start, the first phase load recompiled with them present, and the
% stale index for Depth landed two columns earlier, on the Lowpass setting.
%
% The write path is the dangerous half: gui.Parameter_Update and
% Runtime.updateTrialsFromParameters commit operator edits *into* the column
% writeParamIdx names, so a stale map writes one parameter's value over
% another parameter's trial column.
%
%   matlab -batch "run('tmp/smoke_test_recompile_columns.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

PREF_TAG = 'smoke_recompile_columns';
tmpDir = fullfile(tempdir,'epsych_smoke_recompile_columns');
if isfolder(tmpDir), rmdir(tmpDir,'s'); end
mkdir(tmpDir);
cleanupObj = onCleanup(@() cleanupAll(tmpDir, PREF_TAG));

% 1. compiledTrialColumns returns a map that indexes its own table ---------
P = makeProtocol(tmpDir);
P.compile();

[params, trials, wp, idx] = epsych.Runtime.compiledTrialColumns(P.COMPILED);
assert(numel(wp) == size(trials,2), 'one write parameter per trial column');
assert(numel(params) == size(trials,2), 'one parameter handle per trial column');
for k = 1:numel(wp)
    assert(idx.(wp{k}) == k, 'writeParamIdx must name the column it indexes');
    assert(strcmp(params(k).validName, wp{k}), 'parameters must be column-aligned');
end
fprintf('PASS: compiledTrialColumns builds a self-consistent map\n');

% 2. A started session maps its columns the same way ----------------------
R = makeRuntime(P, tmpDir);
T = R.TRIALS(1);
assert(isfield(T,'writeParamIdx'), 'the start path should install a column map');
assert(T.trials{T.NextTrialID, T.writeParamIdx.Depth} == 0.5, 'Depth reads its own column');
assert(T.trials{T.NextTrialID, T.writeParamIdx.Lowpass} == 20000, 'Lowpass reads its own column');

staleIdx = T.writeParamIdx;
depthWas = staleIdx.Depth;
fprintf('PASS: session start installs a working column map\n');

% 3. The map survives a recompile that inserts parameters -----------------
% Stand-in for the selector's run-start parameters. compile_internal walks
% interfaces, then modules, then parameters in order, so a parameter's
% column is its position in that walk; these two are moved ahead of the rest
% to reproduce the real layout, where the Software interface (which the
% selector adds to) is compiled before the hardware interface that carries
% Lowpass and Depth.
sw = P.findInterface('Software');
addParam(sw,'P_Catch_Current',0.1);
addParam(sw,'CatchTrialsEnabled',true);
prm = sw.Module.Parameters;
sw.Module.Parameters = [prm(end-1:end), prm(1:end-2)];

P.compile();
compiled = P.COMPILED;
assert(size(compiled.trials,2) == size(T.trials,2) + 2, 'the recompile should add two columns');

% What the recompile used to do: new table, old map.
assert(compiled.trials{1, staleIdx.Depth} ~= 0.5, ...
    'the stale index should now address a different parameter (the bug being fixed)');

% What it does now, exactly as ep_TimerFcn_RunTime's safe-boundary block.
[R.TRIALS(1).parameters, R.TRIALS(1).trials, R.TRIALS(1).writeparams, R.TRIALS(1).writeParamIdx] = ...
    epsych.Runtime.compiledTrialColumns(compiled);

T = R.TRIALS(1);
assert(T.writeParamIdx.Depth ~= depthWas, 'Depth should have moved');
assert(T.trials{1, T.writeParamIdx.Depth} == 0.5, 'the refreshed map should still find Depth');
assert(T.trials{1, T.writeParamIdx.Lowpass} == 20000, 'and still find Lowpass');
for k = 1:numel(T.writeparams)
    assert(T.writeParamIdx.(T.writeparams{k}) == k, 'the refreshed map must index its own table');
    assert(strcmp(T.parameters(k).validName, T.writeparams{k}), 'columns stay aligned');
end
fprintf('PASS: the column map is refreshed with the trial table\n');

% 4. The write path targets the right column ------------------------------
% updateTrialsFromParameters commits by name; with a stale map this wrote
% over an unrelated parameter's column.
pDepth = R.find_parameter('Depth');
pDepth.Value = 0.25;
R.updateTrialsFromParameters(pDepth);

T = R.TRIALS(1);
assert(T.trials{1, T.writeParamIdx.Depth} == 0.25, 'the edit should land in the Depth column');
assert(T.trials{1, T.writeParamIdx.Lowpass} == 20000, 'no other column should have been touched');
fprintf('PASS: parameter commits land in the named column\n');

% 5. The display reads the right column -----------------------------------
% gui.NextTrial resolves a field through writeParamIdx, which is how the
% wrong value reached the Next Trial panel.
fig = uifigure('Visible','off','Tag',PREF_TAG);
NT = gui.NextTrial(R.HELPER, fig, Fields=["Depth","Lowpass"], PreferenceTag=PREF_TAG);

R.HELPER.notify('NewTrial', epsych.TrialsData(R.TRIALS(1)));
shown = string(NT.TableH.Data);

depthRow = find(shown(:,1) == "Depth", 1);
lowRow   = find(shown(:,1) == "Lowpass", 1);
assert(~isempty(depthRow) && ~isempty(lowRow), 'both fields should be listed');
assert(shown(depthRow,2) == "0.25", ...
    'Depth must show its own value, not another parameter''s (got %s)', shown(depthRow,2));
assert(shown(lowRow,2) == "20000", 'Lowpass must show its own value');
delete(NT);
close(fig);
fprintf('PASS: gui.NextTrial reads the refreshed map\n');

fprintf('smoke_test_recompile_columns: ALL PASS\n');
end


function P = makeProtocol(tmpDir) %#ok<INUSD>
% Protocol shaped like the appetitive one: session-control parameters, then
% the block holding Lowpass and Depth, plus the core triggers a session
% needs to start.
P = epsych.Protocol(Name='RecompileColumns', Info='column map regression');
P.addParameter('Software','RepeatDelayOnAbort',1,Type='Integer');
P.addParameter('Software','ITIDur',2000,Type='Float');
P.addParameter('Software','Lowpass',20000,Type='Float');
P.addParameter('Software','Depth',0.5,Type='Float');
P.addParameter('Software','StimDelay',1000,Type='Float');

sw = P.findInterface('Software');
sw.add_parameter('x_NewTrial_1',      0, isTrigger=true);
sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);

for name = {'RepeatDelayOnAbort','ITIDur','Lowpass','Depth','StimDelay'}
    p = sw.find_parameter(name{1});
    p.Value = p.Values(1);
end
end


function R = makeRuntime(P, tmpDir)
% Start a session the way ep_TimerFcn_Start does, so TRIALS is built by the
% real path rather than by hand.
R = epsych.Runtime;
R.isTest = true;
R.HELPER = epsych.Helper;
R.Interfaces = P.Interfaces;
R.Protocol = P;
R.dfltDataPath = tmpDir;
R.TempDataDir = tmpDir;

subject = epsych.DefaultSubject(struct('Name','ColumnSubject', ...
    'Species','Mouse','Sex','Unknown','BoxID',1));
R = ep_TimerFcn_Start(R, struct('PROTOCOL',P,'SUBJECT',subject));
end


function p = addParam(iface, name, value)
p = iface.add_parameter(name, value);
p.Value = value;
end


function cleanupAll(tmpDir, prefTag)
delete(findall(groot,'Type','figure','-and','Tag',prefTag));
if ispref('epsych2_gui_NextTrial',prefTag)
    rmpref('epsych2_gui_NextTrial',prefTag);
end
if isfolder(tmpDir)
    rmdir(tmpDir,'s');
end
end
