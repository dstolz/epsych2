function smoke_test_parameter_defaults()
% smoke_test_parameter_defaults()
% Exercise per-subject parameter defaults headlessly: the record helpers and
% parsing, eligibility and checks against a protocol, apply/restore and the
% recompile it feeds, the roster round trip (including a file written before
% the field existed), copyProject and exportTable, the CONFIG seam Run uses
% with its snapshot fallback, and reading values back from saved data files.
%
% No figures: the editor window and RunExpt are GUI and are not driven here.
% Everything runs under a temporary folder; nothing touches a real roster.
%
%   matlab -batch "run('C:/src/epsych_releases/subject-defaults/tmp/smoke_test_parameter_defaults.m')"
%
% See also: epsych.ParameterDefaults, epsych.SubjectRoster.setParameterDefaults

addpath(fileparts(fileparts(mfilename('fullpath'))));
epsych_startup

root = fullfile(tempdir, 'epsych_paramdefaults_smoke');
if isfolder(root), rmdir(root, 's'); end
mkdir(root);
cleanupDir = onCleanup(@() localRemoveDir(root));

% 1. Record helpers --------------------------------------------------------
D0 = epsych.ParameterDefaults.empty();
assert(isstruct(D0) && isempty(D0) && isfield(D0, 'Value'), 'empty() must be a 0-element record array');
d = epsych.ParameterDefaults.blank();
d.Interface = 'Software'; d.Module = 'M'; d.Name = 'X'; d.Value = 3;
assert(epsych.ParameterDefaults.validate(d), 'a plain record must validate');
bad = d; bad.Value = [];
assert(~epsych.ParameterDefaults.validate(bad), 'a record that sets nothing must be refused');
bad = d; bad.Min = 5; bad.Max = 1;
assert(~epsych.ParameterDefaults.validate(bad), 'Min above Max must be refused');
bad = d; bad.Value = NaN;
assert(~epsych.ParameterDefaults.validate(bad), 'a NaN value must be refused');
assert(~epsych.ParameterDefaults.validate([d d]), 'two defaults for one parameter must be refused');
N = epsych.ParameterDefaults.normalize(struct('Name', {'A', ''}, 'Value', {1, 2}, 'Extra', {9, 9}));
assert(numel(N) == 1 && strcmp(N.Name, 'A') && isnan(N.Min) && ~isfield(N, 'Extra'), ...
    'normalize must drop nameless records and unknown fields, and fill defaults');
assert(isempty(epsych.ParameterDefaults.normalize([])), 'normalize([]) must be empty');
fprintf('PASS: record helpers validate and normalize\n');

% 2. A protocol covering every eligibility case ---------------------------
P = epsych.Protocol();
iface = char(P.Interfaces(1).Type);
pDepth  = P.addParameter(iface, 'Depth', 0, Min = -40, Max = 0, Unit = 'dB');
pLevels = P.addParameter(iface, 'Levels', [1 2 3]);
pVol    = P.addParameter(iface, 'RewardVol', 10, Min = 0, Max = 50);
pDelay  = P.addParameter(iface, 'StimDelay', 2000, Min = 1000, Max = 4000, isRandom = true);
pTrig   = P.addParameter(iface, 'Go', 0, isTrigger = true);
pMode   = P.addParameter(iface, 'Mode', 'alpha', Type = 'String');
pFlag   = P.addParameter(iface, 'Flag', true, Type = 'Boolean');
pCount  = P.addParameter(iface, 'Count', 4, Type = 'Integer', Min = 0, Max = 10);
pExpr   = P.addParameter(iface, 'Twice', 0);
pExpr.Expression = "Depth*2";
pPairA  = P.addParameter(iface, 'PairA', [1 2], UserData = struct('Pair', 'grp'));
P.addParameter(iface, 'PairB', [10 20], UserData = struct('Pair', 'grp'));
pHidden = P.addParameter(iface, 'Secret', 7, Visible = false);
modName = pDepth.Module.Name;

e = @(p) epsych.ParameterDefaults.eligibility(p);
assert(e(pDepth).CanSetValue && e(pDepth).CanSetBounds, 'a Float takes a value and bounds');
assert(~e(pDelay).CanSetValue && e(pDelay).CanSetBounds, 'a randomized parameter takes bounds only');
assert(~e(pTrig).CanSetValue && ~e(pTrig).CanSetBounds, 'a trigger takes nothing');
assert(~e(pExpr).CanSetValue, 'an expression parameter takes nothing');
assert(e(pMode).CanSetValue && ~e(pMode).CanSetBounds, 'a String takes a value, no bounds');
assert(e(pFlag).CanSetValue, 'a dispatched Boolean takes a value');

T = epsych.ParameterDefaults.parameters(P);
names = {T.Name};
assert(all(ismember({'Depth','Levels','RewardVol','StimDelay','Mode','Flag','Count','PairA','Secret'}, names)), ...
    'parameters() must list every eligible parameter, hidden ones included');
assert(~any(ismember({'Go','Twice'}, names)), 'parameters() must leave out triggers and expressions');
T2 = epsych.ParameterDefaults.parameters(P, IncludeHidden = false);
assert(~any(strcmp({T2.Name}, 'Secret')), 'IncludeHidden=false must drop hidden parameters');
fprintf('PASS: eligibility and the parameter list\n');

% 3. Parsing and formatting ------------------------------------------------
[v, ok] = epsych.ParameterDefaults.parseValue('-10', pDepth);
assert(ok && isequal(v, -10), 'a number must parse');
[v, ok] = epsych.ParameterDefaults.parseValue('[1, 2 ;3]', pLevels);
assert(ok && isequal(v, [1 2 3]), 'a bracketed list must parse');
[v, ok] = epsych.ParameterDefaults.parseValue('', pDepth);
assert(ok && isempty(v), 'blank must mean "no default"');
[~, ok] = epsych.ParameterDefaults.parseValue('disp(1)', pDepth);
assert(~ok, 'code must never parse as a number');
[v, ok] = epsych.ParameterDefaults.parseValue('off', pFlag);
assert(ok && isequal(v, false), 'off must parse as false');
[v, ok] = epsych.ParameterDefaults.parseValue(' beta ', pMode);
assert(ok && strcmp(v, 'beta'), 'text must parse as typed (trimmed)');
assert(strcmp(epsych.ParameterDefaults.formatValue([1 2.5]), '1, 2.5'), 'a list must format comma-separated');
[v2, ok] = epsych.ParameterDefaults.parseValue(epsych.ParameterDefaults.formatValue([1 2.5]), pLevels);
assert(ok && isequal(v2, [1 2.5]), 'formatValue and parseValue must round trip');
fprintf('PASS: parsing and formatting\n');

% 4. check() ---------------------------------------------------------------
mk = @(name, value, lo, hi) localRecord(iface, modName, name, value, lo, hi);
assert(~epsych.ParameterDefaults.check(mk('Depth', -50, NaN, NaN), pDepth), 'out of range must be refused');
assert(epsych.ParameterDefaults.check(mk('Depth', -50, -60, NaN), pDepth), 'a widened Min must admit the value');
assert(~epsych.ParameterDefaults.check(mk('Count', 2.5, NaN, NaN), pCount), 'an Integer must refuse a fraction');
assert(~epsych.ParameterDefaults.check(mk('StimDelay', 1500, NaN, NaN), pDelay), 'a randomized value must be refused');
assert(epsych.ParameterDefaults.check(mk('StimDelay', [], 1500, 2500), pDelay), 'randomized bounds must be accepted');
assert(~epsych.ParameterDefaults.check(mk('PairA', 1, NaN, NaN), pPairA), 'a paired parameter must keep its level count');
assert(epsych.ParameterDefaults.check(mk('PairA', [3 4], NaN, NaN), pPairA), 'a paired list of the same length is fine');
assert(~epsych.ParameterDefaults.check(mk('Mode', [], 0, 1), pMode), 'a String has no bounds to override');
fprintf('PASS: check refuses what apply could not honour\n');

% 5. apply / restore / compile --------------------------------------------
P.compile();
nBefore = P.COMPILED.ntrials;
D = [mk('Depth', -12, NaN, NaN), mk('RewardVol', 60, NaN, 80), mk('StimDelay', [], 1500, 2500), ...
     mk('Levels', [5 6], NaN, NaN), mk('Secret', 9, NaN, NaN), mk('Missing', 1, NaN, NaN)];
[state, rep] = epsych.ParameterDefaults.apply(P, D);
assert(rep.Changed && numel(rep.Applied) == 5, 'five defaults must apply');
assert(numel(rep.Skipped) == 1 && contains(rep.Skipped.Reason, 'Missing'), 'a missing parameter must be skipped, not thrown');
assert(isequal(pDepth.Values, {-12}) && pDepth.Value == -12, 'a single level must set Values and seat Value');
assert(pVol.Max == 80 && pVol.Value == 60, 'bounds must be applied before the value, or it clamps');
assert(pDelay.Min == 1500 && pDelay.Max == 2500 && pDelay.isRandom, 'randomized bounds must apply');
assert(isequal(pLevels.Values, {5 6}), 'a list must replace the roved levels');
assert(isequal(pHidden.Values, {9}), 'a hidden parameter must take its default');
P.compile();
assert(P.COMPILED.ntrials == nBefore / 3 * 2, 'the trial table must be rebuilt from the new levels');
col = strcmp({P.COMPILED.parameters.Name}, 'Depth');
assert(all(cellfun(@(x) x == -12, P.COMPILED.trials(:, col))), 'every compiled trial must carry the default');

% A second Run with one default removed puts that one back.
[state, rep2] = epsych.ParameterDefaults.apply(P, D([1 3]), state);
assert(rep2.Restored == 5 && numel(rep2.Applied) == 2, 'a second apply must restore then reapply');
assert(isequal(pVol.Values, {10}) && pVol.Max == 50 && pVol.Value == 10, 'a removed default must return the protocol''s value and bounds');
assert(isequal(pLevels.Values, {1 2 3}), 'a removed list must return the protocol''s levels');
assert(isequal(pDepth.Values, {-12}), 'a kept default must still apply');

% A phase load between runs changes a defaulted parameter; the next Run wins.
pDepth.Values = {-30};
[state, ~] = epsych.ParameterDefaults.apply(P, D(1), state);
assert(isequal(pDepth.Values, {-12}), 'the next Run must re-apply over a changed value');

% A state from another protocol object is ignored: a reloaded protocol is pristine.
Q = epsych.Protocol();
[~, rep3] = epsych.ParameterDefaults.apply(Q, epsych.ParameterDefaults.empty(), state);
assert(rep3.Restored == 0, 'a state recorded against another protocol must not be restored onto this one');

% Everything off.
[~, rep4] = epsych.ParameterDefaults.apply(P, [], state);
assert(rep4.Restored == 1 && isequal(pDepth.Values, {0}) && pDepth.Value == 0, ...
    'clearing every default must return the protocol exactly');

% Module renamed: a record falls back to interface + name.
[Pr, how] = epsych.ParameterDefaults.resolve(P, localRecord(iface, 'OldModule', 'Depth', -5, NaN, NaN));
assert(Pr == pDepth && strcmp(how, 'name'), 'a renamed module must resolve by name');
fprintf('PASS: apply, restore, recompile, and name fallback\n');

% 6. Roster round trip -----------------------------------------------------
protoFile = fullfile(root, 'proto.eprot');
P.save(protoFile);
rosterFile = fullfile(root, 'subjects.esub');
dataRoot = fullfile(root, 'data');
mkdir(dataRoot);
R = epsych.SubjectRoster(rosterFile);
pid = R.addProject('Study', DefaultProtocol = protoFile, DefaultDataPath = dataRoot);
sid = R.addSubject(struct('Name', 'PDSmoke01', 'Sex', 'Male', 'Species', 'Gerbil'));
R.assign(sid, pid);
assert(isempty(R.parameterDefaults(sid, pid)), 'a new membership must carry no defaults');

Dsave = [mk('Depth', -12, NaN, NaN), mk('Mode', 'beta', NaN, NaN), mk('Flag', false, NaN, NaN), ...
         mk('StimDelay', [], 1500, 2500)];
R.setParameterDefaults('PDSmoke01', 'Study', Dsave);
R2 = epsych.SubjectRoster(rosterFile);
Dback = R2.parameterDefaults(sid, pid);
assert(numel(Dback) == 4, 'defaults must survive the file');
assert(isequal(Dback(1).Value, -12) && strcmp(Dback(2).Value, 'beta') && isequal(Dback(3).Value, false) ...
    && isempty(Dback(4).Value) && Dback(4).Min == 1500, 'each default must round trip with its type');
try
    R.setParameterDefaults(sid, pid, [Dsave(1) Dsave(1)]);
    error('smoke:noThrow', 'duplicate defaults must be refused');
catch ME
    assert(strcmp(ME.identifier, 'epsych:SubjectRoster:InvalidParameterDefaults'), ME.message);
end
assert(numel(epsych.SubjectRoster(rosterFile).parameterDefaults(sid, pid)) == 4, ...
    'a refused write must leave the file alone');

T = R2.exportTable();
assert(ismember('ParameterDefaults', T.Properties.VariableNames), 'export must carry the defaults');
row = T(strcmp(T.Subject, 'PDSmoke01'), :);
assert(contains(row.ParameterDefaults{1}, 'Depth = -12'), 'the export column must describe them');

pid2 = R.copyProject('Study', 'Study Phase 2', IncludeSubjects = true);
assert(numel(R.parameterDefaults(sid, pid2)) == 4, 'a copied member must keep its defaults by default');
pid3 = R.copyProject('Study', 'Study Fresh', IncludeSubjects = true, CopyParameterDefaults = false);
assert(isempty(R.parameterDefaults(sid, pid3)), 'CopyParameterDefaults=false must start members clean');

% A roster written before the field existed reads as "no defaults".
old = load(rosterFile, '-mat');
old.memberships = rmfield(old.memberships, 'ParameterDefaults');
oldFile = fullfile(root, 'old.esub');
save(oldFile, '-struct', 'old', '-mat');
Rold = epsych.SubjectRoster(oldFile);
assert(isempty(Rold.LoadError) && isempty(Rold.parameterDefaults(sid, pid)), ...
    'an older roster must read with empty defaults');
assert(isfield(Rold.Memberships, 'ParameterDefaults'), 'normalize must add the field');
fprintf('PASS: roster round trip, validation, export, copy, and an older file\n');

% 7. The CONFIG seam Run uses ---------------------------------------------
Pc = epsych.Protocol.load(protoFile);
C = struct('PROTOCOL', Pc, 'SUBJECT', struct('Name', 'PDSmoke01', 'BoxID', 1), ...
    'ROSTER', epsych.ParameterDefaults.rosterLink(rosterFile, sid, pid, Dsave(1)));
[C, repC] = epsych.ParameterDefaults.applyToConfigEntry(C);
assert(strcmp(repC.Source, 'roster') && numel(repC.Applied) == 4, 'Run must read the roster''s current defaults');
pcDepth = Pc.Interfaces(1).find_parameter('Depth');
assert(isequal(pcDepth.Values, {-12}), 'the entry''s protocol must carry them');

% An edit after the commit counts at the next Run.
R.setParameterDefaults(sid, pid, mk('Depth', -20, NaN, NaN));
[C, repC] = epsych.ParameterDefaults.applyToConfigEntry(C);
assert(numel(repC.Applied) == 1 && repC.Restored == 4 && isequal(pcDepth.Values, {-20}), ...
    'an edited default must replace the last run''s');
pcMode = Pc.Interfaces(1).find_parameter('Mode');
assert(isequal(pcMode.Values, {'alpha'}), 'a default dropped since the last run must be put back');

% Roster unreadable: the commit-time snapshot is used, and said so.
C.ROSTER.File = fullfile(root, 'gone', 'missing.esub');
[~, repC] = epsych.ParameterDefaults.applyToConfigEntry(C);
assert(strcmp(repC.Source, 'snapshot') && ~isempty(repC.Message) && isequal(pcDepth.Values, {-12}), ...
    'an unreadable roster must fall back to the snapshot and say so');

% No ROSTER field (a hand-added subject or a scripted CONFIG) is left alone.
C2 = struct('PROTOCOL', epsych.Protocol.load(protoFile), 'SUBJECT', struct('Name', 'X', 'BoxID', 2));
[C2b, repN] = epsych.ParameterDefaults.applyToConfigEntry(C2);
assert(~repN.Changed && ~isfield(C2b, 'ROSTER'), 'an entry with no roster link must be untouched');
fprintf('PASS: the CONFIG seam reads the roster at Run, restores, and falls back\n');

% 8. Reading values back from data files ----------------------------------
subjDir = fullfile(dataRoot, 'PDSmoke01');
mkdir(subjDir);
localWriteSession(fullfile(subjDir, 'PDSmoke01_260920T100000.mat'), [-8 -9], 20);
localWriteSession(fullfile(subjDir, 'PDSmoke01_260925T100000.mat'), [-14 -15 -16], 25);
[file, row, msg] = epsych.ParameterDefaults.latestDataFile("PDSmoke01", Roster = epsych.SubjectRoster(rosterFile));
assert(strlength(file) > 0, msg);
assert(endsWith(file, 'PDSmoke01_260925T100000.mat') && row.Trials == 3, 'the newest saved session must be chosen');
Tp = epsych.ParameterDefaults.parameters(P);
[vals, repD] = epsych.ParameterDefaults.readDataFile(char(file), Tp);
iD = strcmp({Tp.Name}, 'Depth');
iV = strcmp({Tp.Name}, 'RewardVol');
assert(isempty(repD.Message) && repD.NumTrials == 3, 'the file must read');
assert(vals(iD).Found && vals(iD).Value == -16 && vals(iV).Value == 25, 'the LAST trial''s values must be read');
assert(~vals(strcmp({Tp.Name}, 'Mode')).Found, 'a parameter the data lacks must not be found');
[~, repBad] = epsych.ParameterDefaults.readDataFile(fullfile(root, 'nope.mat'), Tp);
assert(~isempty(repBad.Message), 'a missing file must say so, not throw');
fprintf('PASS: latest data file and last-trial values\n');

fprintf('\nALL PASS: smoke_test_parameter_defaults\n');
clear cleanupDir
end

% -----------------------------------------------------------------------
function d = localRecord(iface, moduleName, name, value, lo, hi)
d = epsych.ParameterDefaults.blank();
d.Interface = iface;
d.Module = moduleName;
d.Name = name;
d.Value = value;
d.Min = lo;
d.Max = hi;
end

% -----------------------------------------------------------------------
function localWriteSession(file, depths, vol)
% A saved session in the shape a saving function writes: a Data struct array,
% one record per trial, fields named by parameter validName.
Data = struct('Depth', num2cell(depths), 'RewardVol', vol, 'TrialIndex', num2cell(1:numel(depths)), ...
    'isTest', false);
save(file, 'Data');
end

% -----------------------------------------------------------------------
function localRemoveDir(root)
if isfolder(root)
    try
        rmdir(root, 's');
    catch ME
        vprintf(2, ME);
    end
end
end
