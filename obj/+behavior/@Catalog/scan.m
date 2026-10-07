function ok = scan(obj, options)
% ok = scan(obj)
% ok = scan(obj, Progress = @(k, n) true, UseCache = false)
% List every session file under Root and describe each from one load.
%
% Unchanged files are described from the cache instead of being opened again
% (LastScanReads counts the ones that were). The scan is atomic: everything is
% computed into locals and assigned at the end, so a cancelled scan leaves
% every property as it was. The cache is written after the assignment, outside
% Root.
%
% Parameters:
%   Progress - @(k, n) called before each of the n files is considered;
%              returning false cancels the scan.
%   UseCache - Reuse cached descriptions of unchanged files. Default true.
%              false re-reads every file (and rewrites the cache).
%
% Returns:
%   ok - false when Progress cancelled the scan, true otherwise.
%
% See also: behavior.Catalog.parseName, epsych.SessionFiles.summarize

arguments
    obj
    options.Progress = []
    options.UseCache (1,1) logical = true
end

ok = false;
root = obj.Root;
[~, rootName] = fileparts(root);
if strlength(rootName) == 0, rootName = root; end

% --- Candidates ----------------------------------------------------------
L = dir(fullfile(root, '**', '*.mat'));
L = L(~[L.isdir]);
files = string(fullfile({L.folder}, {L.name}));
files = reshape(files, [], 1);
bytes = reshape([L.bytes], [], 1);
stamps = reshape([L.datenum], [], 1);

keep = true(numel(files), 1);
keys = strings(numel(files), 1);
for k = 1:numel(files)
    keys(k) = behavior.Catalog.keyFor(root, files(k));
    parts = split(keys(k), "/");
    keep(k) = ~localSkipped(parts(1:end-1), parts(end), obj.ReadRecovery);
end
files = files(keep); bytes = bytes(keep); stamps = stamps(keep); keys = keys(keep);

% --- Cache -----------------------------------------------------------------
cacheState = obj.CacheState;
cached = containers.Map('KeyType', 'char', 'ValueType', 'any');
if obj.CacheFile ~= ""
    [records, cacheState] = obj.loadCache_();
    for r = reshape(records, 1, [])
        cached(char(r.Key)) = r;
    end
end

% --- Describe ----------------------------------------------------------------
n = numel(files);
summaries = cell(n, 1);
newRecords = cell(n, 1);
reads = 0;
for k = 1:n
    if ~isempty(options.Progress) && ~options.Progress(k, n)
        vprintf(1, 'behavior.Catalog: scan of "%s" cancelled', root)
        return
    end

    ck = localCacheKey(keys(k));
    s = [];
    if options.UseCache && cached.isKey(ck)
        r = cached(ck);
        if r.Bytes == bytes(k) && r.Modified == stamps(k)
            s = r.Summary;
        end
    end
    if isempty(s)
        s = obj.describeFile_(files(k));
        reads = reads + 1;
    end
    % The location is the listing's, not the cache's: the same file under
    % the same key, wherever it was described from.
    s.File = files(k);
    [s.Folder, b, e] = fileparts(files(k));
    s.FileName = b + e;

    summaries{k} = s;
    newRecords{k} = struct('Key', string(ck), 'Bytes', bytes(k), ...
        'Modified', stamps(k), 'Summary', s);
end
newRecords = vertcat(newRecords{:});

% --- Files -------------------------------------------------------------------
S = [summaries{:}];
if isempty(S)
    S = repmat(epsych.SessionFiles.blank(), 0, 1);
end
S = reshape(S, [], 1);
Files = behavior.Catalog.filesTable_(keys, files, reshape([S.IsSession], [], 1), bytes, ...
    localModified(S), reshape([S.Error], [], 1));

% --- Sessions ----------------------------------------------------------------
isSession = reshape([S.IsSession], [], 1);
idx = find(isSession);
rows = behavior.Catalog.blankRow_(numel(idx));
warnings = cell(numel(idx), 1);
for j = 1:numel(idx)
    [rows(j), warnings{j}] = localRow(rows(j), S(idx(j)), keys(idx(j)), rootName);
end
warnings = vertcat(strings(0, 1), warnings{:});
Sessions = behavior.Catalog.sessionsTable_(rows);
Sessions = localSort(Sessions);

% --- Subjects ----------------------------------------------------------------
Subjects = behavior.Catalog.subjectsTable_(Sessions);
if obj.RosterApplied_
    Subjects = behavior.Catalog.rosterColumns_(Subjects, obj.Roster);
end

% --- Assign ------------------------------------------------------------------
obj.Files = Files;
obj.Sessions = Sessions;
obj.Subjects = Subjects;
obj.Warnings = warnings;
obj.LastScanReads = reads;
obj.ScannedAt = datetime('now');
obj.CacheState = cacheState;
ok = true;

if obj.CacheFile ~= ""
    msg = obj.saveCache_(newRecords);
    if msg ~= ""
        obj.Warnings(end+1, 1) = "The scan cache could not be written: " + msg;
    end
end

vprintf(2, 'behavior.Catalog: %d sessions in %d files under "%s" (%d read, cache %s)', ...
    height(Sessions), n, root, reads, cacheState)

end




function tf = localSkipped(folders, name, readRecovery)
% A file is not listed when any folder between Root and it is hidden or one of
% Catalog.SkipFolders, when it is itself hidden, or when it is a recovery copy
% and those were not asked for.

skip = behavior.Catalog.SkipFolders;
patterns = skip(contains(skip, "*"));
exact = skip(~contains(skip, "*"));

tf = startsWith(name, ".");
if ~readRecovery && startsWith(name, epsych.SessionFiles.RECOVERY_PREFIX)
    tf = true;
end
for f = reshape(folders, 1, [])
    if any(strcmpi(f, exact))
        tf = true;
        return
    end
    for p = patterns
        if ~isempty(regexp(char(f), ['^' regexptranslate('wildcard', char(p)) '$'], 'once'))
            tf = true;
            return
        end
    end
end

end




function k = localCacheKey(key)
k = char(key);
if ispc, k = lower(k); end
end




function t = localModified(S)
t = NaT(numel(S), 1);
for k = 1:numel(S)
    t(k) = S(k).Modified;
end
end




function [r, warnings] = localRow(r, s, key, rootName)
% [r, warnings] = localRow(r, s, key, rootName)
%
% One Sessions row from a summary: where the folder tree puts it, what its name
% says, and what summarize's Extra callback read from inside it.

warnings = strings(0, 1);

parts = split(key, "/");
folders = reshape(parts(1:end-1), 1, []);
p = behavior.Catalog.parseName(parts(end));

qc = strings(1, 0);
switch numel(folders)
    case 0
        % A session saved straight into Root has no subject folder.
        subject = p.NameSubject;
        if subject == "", subject = "(none)"; end
        r.Project = rootName;
        r.ProjectPath = "";
        qc(end+1) = "not_in_subject_folder";
    case 1
        subject = folders(1);
        r.Project = rootName;
        r.ProjectPath = "";
    otherwise
        subject = folders(end);
        r.Project = folders(end-1);
        r.ProjectPath = strjoin(folders(1:end-1), "/");
end

r.Key = key;
r.File = s.File;
r.Folder = s.Folder;
r.FileName = s.FileName;
r.Subject = subject;
r.NameSubject = p.NameSubject;
r.NameOK = p.Parsed && strcmpi(p.NameSubject, subject);
r.Tags = p.Tags;
r.TagText = strjoin(p.Tags, "_");
r.NumTags = numel(p.Tags);
r.Collision = p.Collision;

r.Start = p.Start;
if isnat(r.Start), r.Start = s.StartTime; end
r.Date = dateshift(r.Start, 'start', 'day');

for f = ["Source" "IsSession" "IsTest" "Trials" "Duration" "BoxID" "Paradigm" ...
        "ProtocolVersion" "HasSnapshot" "NotesText" "NumNotes" "EPsychVersion" ...
        "Bytes" "Modified" "Error"]
    r.(f) = s.(f);
end

x = s.Extra;
if isempty(fieldnames(x))
    x = behavior.Catalog.blankExtra_();
end
r.Fields = x.Fields;
r.Candidates = x.Candidates;
r.Outcome = x.Outcome;
r.TrialTypes = x.TrialTypes;
r.NumTest = x.NumTest;
r.SubjectSex = x.SubjectSex;
r.SubjectSpecies = x.SubjectSpecies;
r.SubjectWeight = x.SubjectWeight;
r.ParameterMeta = x.ParameterMeta;

% --- File-level QC -----------------------------------------------------------
if s.Error ~= ""
    qc(end+1) = "unreadable";
    warnings(end+1, 1) = key + ": could not be read (" + s.Error + ")";
elseif s.Trials == 0
    qc(end+1) = "no_trials";
    warnings(end+1, 1) = key + ": holds no trials";
end
if s.IsTest
    qc(end+1) = "test_mode";
end
if ~p.Parsed
    qc(end+1) = "unparsed_name";
elseif ~r.NameOK && ~isempty(folders)
    qc(end+1) = "name_mismatch";
end
r.QCFile = qc;

end




function T = localSort(T)
% Project, then Subject, each in natural order, then Start (undated last), then
% Key so equal starts (a collision copy) keep one order on every machine.

if height(T) < 2, return, end
K = table(behavior.Catalog.naturalKey_(T.Project), behavior.Catalog.naturalKey_(T.Subject), ...
    T.Start, lower(T.Key), 'VariableNames', {'P','S','T','K'});
[~, order] = sortrows(K, {'P','S','T','K'});
T = T(order, :);

end
