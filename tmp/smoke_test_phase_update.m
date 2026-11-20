function smoke_test_phase_update()
% smoke_test_phase_update()
% Prove epsych.Protocol.updatePhase / epsych.Runtime.updatePhase and the
% PhaseSelector menu items over them: a phase saved under an older protocol
% version is rewritten to the session's version, keeping the phase's values
% (hw.Parameter.PHASE_OWNED_FIELDS) and taking the protocol's structure.
%
% Groups:
%   1. dry run reports kept/added/removed/dropped/restructured and writes nothing
%   2. the write: values kept, structure taken, version stamped, Info kept
%   3. a second update finds nothing to do and writes nothing
%   4. the write is undone with restoreVersion from the in-file archive
%   5. a phase stamped with the TARGET version but stale content still updates,
%      archived under its own label so no version string appears twice
%   6. a pinned (archived) target version is honoured
%   7. refusals: newer phase, foreign phase, legacy JSON, missing version
%   8. the interchangeable TDT backends match across types
%   9. the output still fast-parses, and the phase cache serves the new content
%  10. epsych.Runtime.updatePhase targets the session's file and version
%  11. gui.components.PhaseSelector's menu items and scripted methods
%
%   matlab -batch "cd('tmp'); smoke_test_phase_update"
%
% See also: epsych.Protocol.updatePhase, epsych.Runtime.updatePhase,
%   gui.components.PhaseSelector

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(repoRoot);
epsych_startup

root = fullfile(tempdir, 'epsych_phase_update_smoke');
if isfolder(root)
    rmdir(root, 's');
end
mkdir(root);
phaseDir = fullfile(root, 'phases');
mkdir(phaseDir);
cleanupDir = onCleanup(@() localRemoveDir(root));

protFile = fullfile(root, 'protocol.eprot');
phaseFile = fullfile(phaseDir, 'Phase_A.eprot');

% ----- protocol v1 and a phase saved from it -------------------------------
P = epsych.Protocol();
P.Info = 'protocol design';
P.addParameter('Software', 'Delay',   {100}, Unit = 'ms', Type = 'Float');
P.addParameter('Software', 'Depth',   {0.5}, Unit = '',   Type = 'Float');
P.addParameter('Software', 'Doomed',  {1},   Type = 'Float');
P.addParameter('Software', 'Shown',   {2},   Type = 'Float');
P.addParameter('Software', 'Steady',  {9},   Type = 'Float');
p = localParam(P, 'Delay'); p.Min = 0; p.Max = 1000; p.Description = 'old text';
p = localParam(P, 'Depth'); p.Min = 0; p.Max = 1;
P.save(protFile);
v1 = epsych.Protocol.versionOnDisk(protFile);

% A phase is the protocol with the operator's values in it (what
% Runtime.writeParametersProtocol writes).
S = localRead(protFile);
S = localSet(S, 'Delay',  'Value', 250, 'Values', {250}, 'Min', 50);
S = localSet(S, 'Depth',  'Value', 0.8, 'Values', {0.8});
S = localSet(S, 'Doomed', 'Value', 3,   'Values', {3});
S = localSet(S, 'Shown',  'Value', 7,   'Values', {7}, 'isRandom', false);
S.Info = 'Phase A: shaping';
epsych.Protocol.writeProtocolFile(phaseFile, S, Origin = 'phase');
assert(strcmp(epsych.Protocol.versionOnDisk(phaseFile), v1), 'Phase must start at v1');

% ----- protocol v2: structure changes ---------------------------------------
p = localParam(P, 'Delay'); p.Description = 'new text'; p.UpdateEveryTrial = ~p.UpdateEveryTrial;
p = localParam(P, 'Depth'); p.Unit = 'dB'; p.Min = -40; p.Max = 0; p.Values = {0};
p = localParam(P, 'Shown'); p.Visible = false;
P.removeParameter('Software', 'Doomed');
P.addParameter('Software', 'Added', {42}, Type = 'Float');
P.save(protFile);
v2 = epsych.Protocol.versionOnDisk(protFile);
assert(epsych.Protocol.versionNumber(v2) > epsych.Protocol.versionNumber(v1), 'v2 must follow v1');

% 1. dry run ------------------------------------------------------------------
before = dir(phaseFile);
r = epsych.Protocol.updatePhase(phaseFile, protFile);
assert(r.ok, 'Dry run failed: %s', r.message);
assert(r.HasChanges && ~r.Written, 'A dry run must report changes and write nothing');
assert(strcmp(r.PhaseVersion, v1) && strcmp(r.TargetVersion, v2), 'Versions must be reported');
assert(isequal(sort(r.Kept), sort(["Delay", "Shown", "Steady"])), ...
    'Kept should be the matched parameters whose meaning is unchanged, got %s', strjoin(r.Kept, ','));
assert(isequal(r.Added, "Added"), 'Added must name the new parameter');
assert(isequal(r.Removed, "Doomed"), 'Removed must name the deleted parameter');
assert(isscalar(r.Dropped) && r.Dropped.Name == "Depth" && contains(r.Dropped.Reason, 'Unit'), ...
    'A unit change must drop the phase''s values with the reason');
assert(all(ismember(["Delay", "Depth", "Shown"], r.Restructured)) && ~ismember("Steady", r.Restructured), ...
    'Restructured must list exactly the parameters whose structure changed');
assert(~r.LooksForeign && r.MatchedFraction == 4/5, 'Four of five phase parameters match');
assert(~any(strcmp({r.Changes.Section}, 'Compiled')), 'The Compiled section is left out');
after = dir(phaseFile);
assert(after.datenum == before.datenum && after.bytes == before.bytes, 'A dry run must not touch the file');
fprintf('PASS: dry run reports kept/added/removed/dropped/restructured and writes nothing\n');

% 2. the write ------------------------------------------------------------------
epsych.Runtime.phaseParameterData(phaseFile);   % warm the cache with the OLD content
r = epsych.Protocol.updatePhase(phaseFile, protFile, DryRun = false);
assert(r.ok && r.Written, 'Update failed: %s', r.message);
assert(startsWith(r.ArchivedAs, [v1 '+pre-update.']), 'The archive label names the old version');
U = localRead(phaseFile);
assert(strcmp(U.protocolVersion, v2), 'The phase must carry the target version');
assert(strcmp(U.Info, 'Phase A: shaping'), 'The phase description must be kept');
d = localGet(U, 'Delay');
assert(d.Value == 250 && isequal(d.Values, {250}) && d.Min == 50 && d.Max == 1000, ...
    'Delay must keep the phase''s Value/Values/Min/Max');
assert(strcmp(d.Description, 'new text'), 'Delay must take the protocol''s Description');
dv2 = localParam(P, 'Delay');
assert(d.UpdateEveryTrial == dv2.UpdateEveryTrial, 'Delay must take the protocol''s UpdateEveryTrial');
dp = localGet(U, 'Depth');
assert(strcmp(dp.Unit, 'dB') && isequal(dp.Values, {0}) && dp.Min == -40 && dp.Max == 0, ...
    'Depth''s meaning changed, so its values must be the protocol''s');
sh = localGet(U, 'Shown');
assert(~sh.Visible && sh.Value == 7, 'Shown must keep 7 and take Visible=false');
assert(isempty(localGet(U, 'Doomed')), 'Doomed must be gone');
ad = localGet(U, 'Added');
assert(~isempty(ad) && isequal(ad.Values, {42}), 'Added must arrive with the protocol''s values');
idx = epsych.Protocol.listVersions(phaseFile);
assert(any(strcmp({idx.Version}, r.ArchivedAs)) && any(strcmp({idx.Origin}, 'update')), ...
    'The old content must be archived in the file with Origin ''update''');
fprintf('PASS: the write keeps values, takes structure, stamps the version, archives the old\n');

% 9 (here, while the cache was warmed). fast parse + cache ----------------------
[pd, meta] = epsych.Runtime.phaseParameterData(phaseFile);
assert(strcmp(meta.Extra.protocolVersion, v2), 'The phase cache must not serve the pre-update parse');
[pdSlow, metaSlow] = epsych.Runtime.phaseParameterData(phaseFile, UseCache = false, FastParse = false);
assert(isequal(sort(string({pd.Name})), sort(string({pdSlow.Name}))) ...
    && strcmp(metaSlow.Extra.protocolVersion, v2), 'Fast and full parse must agree on the updated file');
fprintf('PASS: the updated phase parses (fast and full) and the cache serves the new content\n');

% 3. idempotent -----------------------------------------------------------------
r2 = epsych.Protocol.updatePhase(phaseFile, protFile, DryRun = false);
assert(r2.ok && ~r2.HasChanges && ~r2.Written, 'A second update must find nothing to do');
fprintf('PASS: an up-to-date phase is left alone\n');

% 4. undo -------------------------------------------------------------------------
rr = epsych.Protocol.restoreVersion(phaseFile, r.ArchivedAs, Mode = 'exact');
assert(rr.ok, 'Undo failed: %s', rr.message);
B = localRead(phaseFile);
assert(strcmp(B.protocolVersion, v1) && ~isempty(localGet(B, 'Doomed')) ...
    && localGet(B, 'Depth').Value == 0.8, 'restoreVersion must give back the phase as it was');
fprintf('PASS: the update is undone from the in-file archive\n');

% 5. stamped with the target version, stale content ------------------------------
stale = fullfile(phaseDir, 'Phase_Stale.eprot');
Sst = B;
Sst.protocolVersion = v2;           % e.g. re-saved from a session built on a stale config
epsych.Protocol.writeProtocolFile(stale, Sst, Origin = 'phase');
r = epsych.Protocol.updatePhase(stale, protFile, DryRun = false);
assert(r.ok && r.Written, 'A same-version stale phase must still update: %s', r.message);
assert(startsWith(r.ArchivedAs, [v2 '+pre-update.']), 'Archived under its own label');
idx = epsych.Protocol.listVersions(stale);
assert(numel(unique({idx.Version})) == numel(idx), 'No version string may appear twice in one file');
assert(isequal(localGet(localRead(stale), 'Depth').Unit, 'dB'), 'Stale structure must be corrected');
fprintf('PASS: a phase stamped with the target version but stale content is corrected\n');

% 6. pinned target ------------------------------------------------------------------
p = localParam(P, 'Steady'); p.Description = 'only in v3';
P.save(protFile);
v3 = epsych.Protocol.versionOnDisk(protFile);
pinned = fullfile(phaseDir, 'Phase_Pinned.eprot');
epsych.Protocol.writeProtocolFile(pinned, S, Origin = 'phase');
r = epsych.Protocol.updatePhase(pinned, protFile, v2, DryRun = false);
assert(r.ok && r.Written && strcmp(r.TargetVersion, v2), 'A pinned version must be the target: %s', r.message);
assert(~strcmp(localGet(localRead(pinned), 'Steady').Description, 'only in v3'), ...
    'The pinned target must be read from the archive, not the current content');
fprintf('PASS: an archived (pinned) target version is honoured\n');

% 7. refusals -------------------------------------------------------------------------
newer = fullfile(phaseDir, 'Phase_Newer.eprot');
Sn = S; Sn.protocolVersion = v3;
epsych.Protocol.writeProtocolFile(newer, Sn, Origin = 'phase');
r = epsych.Protocol.updatePhase(newer, protFile, v2, DryRun = false);
assert(~r.ok && ~r.Written && contains(r.message, 'backwards'), 'A newer phase must be refused');

foreign = fullfile(phaseDir, 'Phase_Foreign.eprot');
Q = epsych.Protocol();
Q.addParameter('Software', 'Unrelated1', {1}, Type = 'Float');
Q.addParameter('Software', 'Unrelated2', {2}, Type = 'Float');
Q.addParameter('Software', 'Steady', {3}, Type = 'Float');
Q.save(foreign);
r = epsych.Protocol.updatePhase(foreign, protFile, DryRun = false);
assert(~r.ok && ~r.Written && r.LooksForeign, 'A foreign-looking phase must be refused by default');
r = epsych.Protocol.updatePhase(foreign, protFile, DryRun = false, AllowForeign = true);
assert(r.ok && r.Written, 'AllowForeign must let it through');

json = fullfile(phaseDir, 'Legacy.json');
fid = fopen(json, 'w'); fprintf(fid, '{"Parameters": []}'); fclose(fid);
r = epsych.Protocol.updatePhase(json, protFile);
assert(~r.ok && contains(r.message, 'JSON'), 'A legacy JSON phase must be refused');
r = epsych.Protocol.updatePhase(pinned, protFile, 'v999.000101');
assert(~r.ok && contains(r.message, 'v999.000101'), 'A version the protocol never held must be refused');
r = epsych.Protocol.updatePhase(fullfile(root, 'missing.eprot'), protFile);
assert(~r.ok, 'A missing phase must be refused, not thrown');
fprintf('PASS: newer, foreign, JSON, unknown-version and missing phases are refused cleanly\n');

% 8. interchangeable backends ---------------------------------------------------------
tdtProt = fullfile(root, 'tdt_protocol.eprot');
tdtPhase = fullfile(phaseDir, 'Phase_TDT.eprot');
T = localRead(protFile);
T.InterfaceData{1}.Type = 'TDT_Synapse';
epsych.Protocol.writeProtocolFile(tdtProt, T);
Sx = S;
Sx.InterfaceData{1}.Type = 'TDT_RPcox';
epsych.Protocol.writeProtocolFile(tdtPhase, Sx, Origin = 'phase');
r = epsych.Protocol.updatePhase(tdtPhase, tdtProt);
assert(r.ok && ismember("Delay", r.Kept) && ~r.LooksForeign, ...
    'An RPcox phase must match a Synapse protocol''s parameters');
fprintf('PASS: a phase saved under TDT_RPcox matches a TDT_Synapse protocol\n');

% 10. Runtime.updatePhase ---------------------------------------------------------------
R = epsych.Runtime;
cleanupRuntime = onCleanup(@() delete(R));
r = R.updatePhase(phaseFile);
assert(~r.ok && ~r.Written, 'A runtime with no protocol must refuse');
R.Protocol = epsych.Protocol.load(protFile);   % current = v3
r = R.updatePhase(phaseFile);
assert(~r.ok && contains(r.message, 'not loaded from a file'), 'A runtime with no ProtocolFile must refuse');
R.ProtocolFile = string(protFile);
R.Protocol = epsych.Protocol.loadVersion(protFile, v2);   % a held membership running v2
R.Interfaces = R.Protocol.Interfaces;   % as RunExpt.ExptDispatch does; hw.Software connects in memory
r = R.updatePhase(phaseFile, DryRun = false);
assert(r.ok && r.Written && strcmp(r.TargetVersion, v2), ...
    'Runtime.updatePhase must target the version the session runs: %s', r.message);
fprintf('PASS: Runtime.updatePhase targets the session''s protocol file at its running version\n');

% 11. PhaseSelector --------------------------------------------------------------------------
% Bring Phase_A back to v1 so there is something to update.
epsych.Protocol.writeProtocolFile(phaseFile, S, Origin = 'phase');
delete(json); delete(foreign); delete(newer);
% The component remembers its folder machine-wide (and that preference
% outranks the folder passed in), so point it here and put the operator's
% folder back afterwards.
prefGroup = 'epsych2_gui_PhaseSelector';
prefKey = 'LastPhasePath';
hadPref = ispref(prefGroup, prefKey);
oldPref = '';
if hadPref, oldPref = getpref(prefGroup, prefKey); end
cleanupPref = onCleanup(@() localRestorePref(prefGroup, prefKey, hadPref, oldPref));
setpref(prefGroup, prefKey, phaseDir);

fig = uifigure('Visible', 'off');
cleanupFig = onCleanup(@() delete(fig));
ps = gui.components.PhaseSelector(R, string(phaseDir));
assert(ps.PhasePath == string(phaseDir), 'The component must scan the test folder');
ps.createGUI(uigridlayout(fig, [1 1]));
cm = ps.h_ContextMenu;
items = findobj(cm, 'Type', 'uimenu');
upd = items(startsWith({items.Text}, {'Update Selected', 'Selected Phase'}));
all_ = items(startsWith({items.Text}, 'Update All'));
assert(isscalar(upd) && isscalar(all_), 'Both update items must be on the menu');

ps.h_PhaseSelect.Value = 'Phase_A';
ps.onPhaseSelectionChanged(ps.h_PhaseSelect);
cm.ContextMenuOpeningFcn(cm, []);
assert(upd.Enable == "on" && contains(upd.Text, v1) && contains(upd.Text, v2), ...
    'With a stale phase selected the item must offer the update, got "%s"', upd.Text);
assert(all_.Enable == "on", 'Update All must be offered with .eprot phases present');

rep = ps.updateSelectedPhase(Confirm = false);
assert(rep.Written, 'updateSelectedPhase must write: %s', rep.message);
assert(any(contains(ps.DisplayNames, "Phase_A (" + v2 + ")")), 'The dropdown label must show the new version');
assert(string(ps.h_PhaseSelect.Value) == "Phase_A", 'The selection must survive the rescan');
cm.ContextMenuOpeningFcn(cm, []);
assert(upd.Enable == "off" && startsWith(upd.Text, 'Selected Phase Matches'), ...
    'An up-to-date phase must grey the item and say so, got "%s"', upd.Text);

epsych.Protocol.writeProtocolFile(phaseFile, S, Origin = 'phase');   % stale again
reps = ps.updateAllPhases(Confirm = false);
assert(~isempty(reps) && all([reps.Written]), 'updateAllPhases must write the stale phases');
assert(any(endsWith(string({reps.PhaseFile}), 'Phase_A.eprot')), 'Phase_A must be among them');
again = ps.updateAllPhases(Confirm = false);
assert(isempty(again), 'A second Update All must find nothing to write');

R.ReviewMode = true;
cm.ContextMenuOpeningFcn(cm, []);
assert(upd.Enable == "off" && all_.Enable == "off", 'A review must never offer phase updates');
R.ReviewMode = false;
fprintf('PASS: PhaseSelector''s menu items and scripted update methods\n');

stray = dir(fullfile(phaseDir, '*.tmp'));
assert(isempty(stray), 'Atomic writes must not leave temp files behind');

fprintf('\nAll phase update smoke tests passed.\n');
end


function p = localParam(P, name)
p = P.findInterface('Software').find_parameter(name, includeInvisible = true);
p = p(1);
end


function S = localRead(f)
L = load(f, '-mat', 'protocol');
S = L.protocol;
end


function S = localSet(S, name, varargin)
for i = 1:numel(S.InterfaceData)
    for m = 1:numel(S.InterfaceData{i}.Modules)
        params = S.InterfaceData{i}.Modules{m}.Parameters;
        for k = 1:numel(params)
            if strcmp(params{k}.Name, name)
                for j = 1:2:numel(varargin)
                    params{k}.(varargin{j}) = varargin{j+1};
                end
            end
        end
        S.InterfaceData{i}.Modules{m}.Parameters = params;
    end
end
end


function s = localGet(S, name)
s = [];
for i = 1:numel(S.InterfaceData)
    for m = 1:numel(S.InterfaceData{i}.Modules)
        params = S.InterfaceData{i}.Modules{m}.Parameters;
        for k = 1:numel(params)
            if strcmp(params{k}.Name, name)
                s = params{k};
                return
            end
        end
    end
end
end


function localRestorePref(group, key, had, old)
if had
    setpref(group, key, old);
elseif ispref(group, key)
    rmpref(group, key);
end
end


function localRemoveDir(root)
if isfolder(root)
    try
        rmdir(root, 's');
    catch
    end
end
end
