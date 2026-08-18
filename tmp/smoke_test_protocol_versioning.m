function smoke_test_protocol_versioning()
% smoke_test_protocol_versioning()
% Exercise the version history embedded in .eprot files: every save archives
% the version it replaces (epsych.Protocol.writeProtocolFile), listVersions /
% hasVersion / loadVersion read the archive without disturbing anything, and
% restoreVersion rewrites the file back — as a new version or exactly.
%
% Also proves the seams: a legacy file with no archive still loads and lists,
% the version-mint reconcile stops two stale objects from coining the same
% version, a phase-style same-version write replaces content without an
% archive entry, the phase cache drops its entry on every write, fast parse
% stays available with an archive present, and no atomic-write temp files
% survive.
%
%   matlab -batch "cd('tmp'); smoke_test_protocol_versioning"
%
% See also: epsych.Protocol.writeProtocolFile, epsych.Protocol.restoreVersion,
%   documentation/epsych/epsych_Protocol.md

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(repoRoot);
epsych_startup

root = fullfile(tempdir, 'epsych_protocol_versioning_smoke');
if isfolder(root)
    rmdir(root, 's');
end
mkdir(root);
cleanupDir = onCleanup(@() localRemoveDir(root));

fixture = fullfile(repoRoot, 'tmp', 'TEST_NEW_PROTOCOL2.eprot');
assert(isfile(fixture), 'Test protocol fixture is missing: %s', fixture);

f = fullfile(root, 'versioned.eprot');

% 1. Legacy file: no archive, everything still works ------------------------
% A file written before version history existed holds one 'protocol' variable.
legacy = fullfile(root, 'legacy.eprot');
S = load(fixture, '-mat');
protocol = S.protocol;
save(legacy, 'protocol', '-mat');

idx = epsych.Protocol.listVersions(legacy);
assert(isscalar(idx) && idx(1).IsCurrent, ...
    'A legacy file must list exactly its current version');
assert(~epsych.Protocol.hasVersion(legacy, 'v999.000101'), ...
    'A legacy file has no archive to find versions in');
P0 = epsych.Protocol.load(legacy);
assert(isa(P0, 'epsych.Protocol'), 'A legacy file must still load');
assert(strcmp(epsych.Protocol.versionOnDisk(legacy), idx(1).Version), ...
    'versionOnDisk and listVersions must agree on the current version');
fprintf('PASS: a legacy file with no archive loads, lists, and reads its version\n');

% 2. Saves accrue history, newest first -------------------------------------
P = epsych.Protocol.load(fixture);
P.Info = 'first content';
P.save(f);
v1 = epsych.Protocol.versionOnDisk(f);
assert(~isempty(v1), 'A saved file must carry a version');

idx = epsych.Protocol.listVersions(f);
assert(isscalar(idx), 'The first save of a file has nothing to archive');

P.Info = 'second content';
P.save(f);
v2 = epsych.Protocol.versionOnDisk(f);
P.Info = 'third content';
P.save(f);
v3 = epsych.Protocol.versionOnDisk(f);

assert(epsych.Protocol.versionNumber(v3) > epsych.Protocol.versionNumber(v2) ...
    && epsych.Protocol.versionNumber(v2) > epsych.Protocol.versionNumber(v1), ...
    'Each save must increment the comparable part of the version');

idx = epsych.Protocol.listVersions(f);
assert(numel(idx) == 3, 'Three saves should list three versions');
assert(idx(1).IsCurrent && strcmp(idx(1).Version, v3), 'The current version lists first');
assert(strcmp(idx(2).Version, v2) && strcmp(idx(3).Version, v1), ...
    'Archived versions list newest first');
assert(epsych.Protocol.hasVersion(f, v1) && epsych.Protocol.hasVersion(f, v2) ...
    && epsych.Protocol.hasVersion(f, v3), 'Every version the file held must be findable');

vars = {whos('-file', f).name};
assert(all(ismember({'protocol', 'history', 'historyIndex', 'historyFormat'}, vars)), ...
    'A versioned file carries the four MAT variables');
fprintf('PASS: saves archive the superseded version, newest first\n');

% 3. loadVersion round-trips archived content -------------------------------
[Pv1, Sv1] = epsych.Protocol.loadVersion(f, v1);
assert(strcmp(Pv1.Info, 'first content') && strcmp(Sv1.protocolVersion, v1), ...
    'An archived version must come back with its own content and version');
Pcur = epsych.Protocol.loadVersion(f, '');
assert(strcmp(Pcur.Info, 'third content'), 'An empty version means the current one');
try
    epsych.Protocol.loadVersion(f, 'v999.000101');
    error('smoke:versioning', 'loadVersion must refuse a version the file never held');
catch ME
    assert(strcmp(ME.identifier, 'epsych:Protocol:VersionNotFound'), ...
        'Unexpected error for a missing version: %s', ME.identifier);
end
fprintf('PASS: loadVersion returns archived content exactly, and refuses clearly\n');

% 4. Same-version writes replace content without archiving ------------------
% IncrementVersion=false is a content update: within one file a version string
% identifies content, so nothing is pushed and nothing is duplicated.
P.Info = 'third content, corrected';
P.save(f, IncrementVersion = false);
assert(strcmp(epsych.Protocol.versionOnDisk(f), v3), ...
    'A save without increment must keep the version');
idx = epsych.Protocol.listVersions(f);
assert(numel(idx) == 3, 'A same-version save must not grow the archive');
Pcheck = epsych.Protocol.load(f);
assert(strcmp(Pcheck.Info, 'third content, corrected'), ...
    'A same-version save must still replace the content');
fprintf('PASS: a same-version save replaces content without an archive entry\n');

% 5. Version minting reconciles with the disk -------------------------------
% Two stale objects saving over each other must not coin the same version for
% different content.
A = epsych.Protocol.load(f);
B = epsych.Protocol.load(f);
B.Info = 'edit by B';
B.save(f);
vB = epsych.Protocol.versionOnDisk(f);
A.Info = 'edit by A';
A.save(f);
vA = epsych.Protocol.versionOnDisk(f);
assert(epsych.Protocol.versionNumber(vA) > epsych.Protocol.versionNumber(vB), ...
    'A stale object must mint past the file on disk, not collide with it');
idx = epsych.Protocol.listVersions(f);
assert(numel(unique({idx.Version})) == numel(idx), ...
    'No version string may appear twice in one file');
PvB = epsych.Protocol.loadVersion(f, vB);
assert(strcmp(PvB.Info, 'edit by B'), 'The overwritten edit must survive in the archive');
fprintf('PASS: version minting reconciles with the file on disk\n');

% 6. restoreVersion, Mode=newversion ----------------------------------------
nBefore = numel(epsych.Protocol.listVersions(f));
rep = epsych.Protocol.restoreVersion(f, v1);
assert(rep.ok, 'Restore as new version failed: %s', rep.message);
vNew = epsych.Protocol.versionOnDisk(f);
assert(strcmp(rep.NewVersion, vNew) && ~strcmp(vNew, v1), ...
    'A newversion restore mints a new version string');
assert(epsych.Protocol.versionNumber(vNew) > epsych.Protocol.versionNumber(vA), ...
    'The minted version must move the counter forward');
Prest = epsych.Protocol.load(f);
assert(strcmp(Prest.Info, 'first content'), ...
    'The restored content must be the archived version''s');
assert(epsych.Protocol.hasVersion(f, v1), ...
    'A newversion restore leaves the source entry in the archive');
assert(epsych.Protocol.hasVersion(f, vA), ...
    'The content being replaced must be archived, so the restore is undoable');
assert(numel(epsych.Protocol.listVersions(f)) == nBefore + 1, ...
    'A newversion restore grows the list by exactly the new version');
rep = epsych.Protocol.restoreVersion(f, vNew);
assert(~rep.ok, 'Restoring the current version as a new version must refuse');
fprintf('PASS: restore-as-new-version keeps the counter monotonic and is undoable\n');

% 7. restoreVersion, Mode=exact ---------------------------------------------
rep = epsych.Protocol.restoreVersion(f, vB, Mode = 'exact');
assert(rep.ok, 'Exact restore failed: %s', rep.message);
assert(strcmp(epsych.Protocol.versionOnDisk(f), vB), ...
    'An exact restore rewinds the file''s version string');
Prest = epsych.Protocol.load(f);
assert(strcmp(Prest.Info, 'edit by B'), 'An exact restore rewinds the content');
idx = epsych.Protocol.listVersions(f);
assert(sum(strcmp({idx.Version}, vB)) == 1, ...
    'The restored version must leave the archive, not exist in both places');
assert(epsych.Protocol.hasVersion(f, vNew), ...
    'The version being left must move into the archive');
rep = epsych.Protocol.restoreVersion(f, vB, Mode = 'exact');
assert(rep.ok, 'An exact restore of the current version is a no-op success');
rep = epsych.Protocol.restoreVersion(f, 'v999.000101', Mode = 'exact');
assert(~rep.ok, 'Restoring a version the file never held must refuse');
fprintf('PASS: exact restore rewinds version and content, keeping versions unique\n');

% 8. Phase-style writes preserve the archive --------------------------------
% Runtime.writeParametersProtocol routes through the same writer with a
% same-version struct: content replaced, archive untouched.
before = epsych.Protocol.listVersions(f);
S = load(f, '-mat');
phaseStruct = S.protocol;
phaseStruct.Info = 'phase overlay';
epsych.Protocol.writeProtocolFile(f, phaseStruct, Origin = 'phase');
after = epsych.Protocol.listVersions(f);
assert(isequal({before.Version}, {after.Version}), ...
    'A same-version phase write must leave the archive exactly as it was');
Pph = epsych.Protocol.load(f);
assert(strcmp(Pph.Info, 'phase overlay'), 'The phase write must land its content');
fprintf('PASS: a phase-style write updates content and preserves the archive\n');

% 9. Every write drops the phase cache entry --------------------------------
epsych.Protocol.load(f);   % ensure the file parses before caching it
epsych.Runtime.phaseParameterData(string(f));
hit = epsych.Runtime.phaseCache('get', string(f));
assert(hit, 'The phase cache should hold the file after a parse');
P9 = epsych.Protocol.load(f);
P9.save(f);
hit = epsych.Runtime.phaseCache('get', string(f));
assert(~hit, 'A save must drop the phase cache entry for the path');
fprintf('PASS: writes invalidate the phase cache\n');

% 10. Fast parse works with an archive present ------------------------------
[fastPD, fastMD] = epsych.Runtime.phaseParameterData(string(f), ...
    UseCache = false, FastParse = true);
[slowPD, slowMD] = epsych.Runtime.phaseParameterData(string(f), ...
    UseCache = false, FastParse = false);
assert(isequal({fastPD.Name}, {slowPD.Name}), ...
    'Fast and full parse must see the same parameters with an archive present');
assert(isequal(fastMD.Extra.protocolVersion, slowMD.Extra.protocolVersion), ...
    'Fast and full parse must agree on the file''s version');
fprintf('PASS: fast parse is unaffected by the embedded archive\n');

% 11. Atomic writes leave no droppings --------------------------------------
stray = dir(fullfile(root, '*.tmp'));
assert(isempty(stray), 'Atomic writes must not leave temp files behind');
fprintf('PASS: no atomic-write temp files survive\n');

fprintf('\nAll protocol versioning smoke tests passed.\n');

end

% -----------------------------------------------------------------------
function localRemoveDir(root)
if isfolder(root)
    try
        rmdir(root, 's');
    catch
    end
end
end
