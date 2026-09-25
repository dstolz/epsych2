function s = summarize(file, options)
% s = epsych.SessionFiles.summarize(file)
% s = epsych.SessionFiles.summarize(file, UseCache = false)
% Describe one session file in one row, reading as little of it as it can.
%
% A saved session is Data (one record per trial) plus, since 2026-08, Info (an
% epsych.SessionSnapshot). A recovery .mat is info plus data_0001..data_NNNN,
% and only the first and last of those are loaded: the count comes from whos.
% An .epj journal is read whole through epsych.TrialJournal, the one reader
% that knows its format.
%
% Parameters:
%   file     - Saved session .mat, crash-recovery .mat, or .epj journal.
%   UseCache - Reuse an earlier summary while the file's size and modification
%              time are unchanged. Default true.
%
% Returns:
%   s - Scalar struct with the fields of epsych.SessionFiles.blank. Never
%       throws for a file that exists: an unreadable session comes back with
%       Error set rather than being dropped, since "this file is damaged" is
%       exactly what someone browsing a subject's sessions needs to see.
%
% See also: epsych.SessionFiles.scan, epsych.SessionSnapshot.fromInfo

arguments
    file (1,1) string
    options.UseCache (1,1) logical = true
end

s = epsych.SessionFiles.blank();
s.File = file;
[folder, base, ext] = fileparts(file);
s.Folder = folder;
s.FileName = base + ext;

d = dir(file);
if isempty(d) || d(1).isdir
    s.Error = "No such file.";
    return
end
d = d(1);
s.Bytes = d.bytes;
s.Modified = epsych.SessionFiles.modified_(d);

key = char(file);
if ispc, key = lower(key); end

if options.UseCache
    hit = epsych.SessionFiles.cache_('get', key, d);
    if ~isempty(hit)
        s = hit;
        return
    end
end

if startsWith(base, epsych.SessionFiles.RECOVERY_PREFIX) || strcmpi(ext, '.epj')
    s.Source = "Recovery";
else
    s.Source = "Saved";
end

try
    [info, first, last, s.Trials, s.IsSession] = localRead(char(file), char(ext));
    if s.IsSession
        s = localDescribe(s, info, first, last, char(base));
    end
catch ME
    % A save interrupted by a crash is still somebody's session. Only a .mat
    % can get here: an .epj reader failure is the journal's own report.
    vprintf(2, 'epsych.SessionFiles: could not read "%s": %s', file, ME.message)
    s.IsSession = true;
    s.Error = string(ME.message);
    s = localDescribe(s, [], [], [], char(base));
end

epsych.SessionFiles.cache_('put', key, s);

end




function [info, first, last, nTrials, isSession] = localRead(file, ext)
% [info, first, last, nTrials, isSession] = localRead(file, ext)
%
% The file's session description (Info/info, [] when it has none), its first
% and last trial records ([] when it has none), and how many trials it holds.
% isSession is false for a .mat that holds neither shape, decided from whos
% alone so that an unrelated file is never loaded.

info = [];
first = [];
last = [];
nTrials = 0;
isSession = false;

if strcmpi(ext, '.epj')
    [S, torn] = epsych.TrialJournal.read(file);
    if torn
        vprintf(2, 'epsych.SessionFiles: "%s" ends in a torn record', file)
    end
    isSession = true;
    if isfield(S, 'info'), info = S.info; end
    names = localDataNames(fieldnames(S));
    nTrials = numel(names);
    if nTrials > 0
        first = S.(names{1});
        last  = S.(names{end});
    end
    return
end

w = whos('-file', file);
names = {w.name};
isStruct = strcmp({w.class}, 'struct');

infoVar = names(ismember(names, {'Info','info'}) & isStruct);

if any(strcmp(names, 'Data') & isStruct)
    % A saved session.
    isSession = true;
    S = localLoad(file, [{'Data'}, infoVar(1:min(1,end))]);
    if ~isempty(infoVar), info = S.(infoVar{1}); end
    [first, last, nTrials] = localRecords(S.Data);

elseif any(strcmp(names, 'info') & isStruct)
    % A crash-recovery seed: info, then one data_NNNN variable per trial once
    % the journal has been merged into it.
    isSession = true;
    dataNames = localDataNames(names);
    nTrials = numel(dataNames);
    vars = {'info'};
    if nTrials > 0
        vars = unique([vars, dataNames(1), dataNames(end)], 'stable');
    end
    S = localLoad(file, vars);
    info = S.info;
    if nTrials > 0
        first = S.(dataNames{1});
        last  = S.(dataNames{end});
    end
end

end




function [first, last, n] = localRecords(Data)
% [first, last, n] = localRecords(Data)
%
% First and last trial records of a saved Data array, and how many there are.
% A record whose every field is empty is not a trial: older saving functions
% wrote one such placeholder for a session that completed none.

first = [];
last = [];
n = 0;

if isempty(Data) || isempty(fieldnames(Data)), return, end

Data = reshape(Data, 1, []);
c = struct2cell(Data);                       % fields x 1 x trials
filled = reshape(any(~cellfun(@isempty, c), 1), 1, []);
idx = find(filled);
n = numel(idx);
if n == 0, return, end

first = Data(idx(1));
last  = Data(idx(end));

end




function names = localDataNames(names)
% The data_NNNN names in trial order. Sorted by the NUMBER, not the text: the
% padding is four digits, so past trial 9999 a text sort would put data_10000
% before data_9999.

names = reshape(names(~cellfun(@isempty, regexp(names, '^data_\d+$', 'once'))), 1, []);
if isempty(names), return, end
[~, order] = sort(str2double(extractAfter(names, 'data_')));
names = names(order);

end




function S = localLoad(file, vars)
% S = localLoad(file, vars)
%
% load() with its warnings held back. A file saved with a class this
% installation has since changed warns once per variable, and a scan of one
% subject would otherwise fill the command window with them; the summary does
% not depend on those objects, so the warning is logged at debug level instead.

lastwarn('');
ws = warning('off', 'all');
restore = onCleanup(@() warning(ws));

S = load(file, vars{:});

clear restore
msg = lastwarn;
if ~isempty(msg)
    vprintf(3, 'epsych.SessionFiles: loading "%s" warned: %s', file, msg)
end

end




function s = localDescribe(s, info, first, last, base)
% s = localDescribe(s, info, first, last, base)
%
% Fill the descriptive fields from what the file said about itself, falling
% back on its name and its trial records for what it did not say.

snap = epsych.SessionSnapshot.fromInfo(localScalar(info), Quiet = true);

s.HasSnapshot = epsych.SessionSnapshot.isSnapshot(localScalar(info)) ...
    && isstruct(snap.Protocol) && ~isempty(fieldnames(snap.Protocol));

% --- When ------------------------------------------------------------
[nameTime, nameHasTime] = localNameTime(base);
firstTime = localRecordTime(first);
lastTime  = localRecordTime(last);

start = localDatetime(snap.StartTime);
if isnat(start) && nameHasTime, start = nameTime;  end
if isnat(start),                start = firstTime; end
if isnat(start),                start = nameTime;  end   % a date with no time
s.StartTime = start;

s.EndTime = lastTime;
if isnat(s.EndTime), s.EndTime = firstTime; end

if ~isnat(s.StartTime) && ~isnat(s.EndTime) && s.EndTime >= s.StartTime
    s.Duration = s.EndTime - s.StartTime;
end

% --- What ------------------------------------------------------------
box = snap.BoxID;
if isempty(box)
    try
        box = snap.Subject.BoxID;
    catch
    end
end
if isnumeric(box) && isscalar(box)
    s.BoxID = double(box);
else
    tok = regexp(base, '_Box_(\d+)_', 'tokens', 'once');
    if ~isempty(tok), s.BoxID = str2double(tok{1}); end
end

s.IsTest = localFlag(snap.isTest);
if ~s.IsTest && isstruct(first) && isfield(first, 'isTest')
    s.IsTest = localFlag(first.isTest);
end

try
    s.Paradigm = localText(snap.Protocol.Options.trialFunc);
catch
end
try
    s.ProtocolVersion = localText(snap.Protocol.protocolVersion);
catch
end

s.NotesText = localText(snap.NotesText, newline);
s.NumNotes = numel(snap.Notes);

s.EPsychVersion = localVersion(snap.EPsychMeta);

end




function tf = localFlag(v)
% A scalar logical from a stored flag that may be empty or numeric.
tf = false;
if (islogical(v) || isnumeric(v)) && ~isempty(v)
    tf = logical(v(1));
end
end




function t = localText(v, sep)
% A scalar string from stored text of any shape, "" for anything else. Every
% field of a summary must stay scalar, or scan cannot stack them into a table.
if nargin < 2, sep = " "; end
t = "";
if (ischar(v) || isstring(v) || iscellstr(v)) && ~isempty(v)
    t = strjoin(reshape(string(v), 1, []), sep);
end
end




function info = localScalar(info)
% Multi-subject sessions write one file per subject, so Info is scalar; only a
% hand-built file has an array, and epsych.ReviewSession opens its first.
if isstruct(info) && numel(info) > 1
    info = info(1);
end
end




function [t, hasTime] = localNameTime(base)
% [t, hasTime] = localNameTime(base)
%
% The session time a file name carries, in the three shapes names have taken:
%   <name>_260925T090520      epsych.RunExpt.defaultFilename (to the second)
%   RUNTIME_DATA_..._2609250905xx  the recovery seed, read to the MINUTE: seeds
%                             written before 2026-09-25 carry hundredths in the
%                             last two digits ('SS' in ep_TimerFcn_Start's
%                             format), later ones seconds, and a name cannot
%                             say which
%   <name>_25-Sep-2025        older saving functions (a date only)

t = NaT;
hasTime = false;

tok = regexp(base, '(\d{6}T\d{6})', 'tokens', 'once');
if ~isempty(tok)
    t = localParse(tok{1}, 'yyMMdd''T''HHmmss');
    hasTime = ~isnat(t);
    return
end

tok = regexp(base, '_Box_\d+_(\d{10})\d{2}$', 'tokens', 'once');
if ~isempty(tok)
    t = localParse(tok{1}, 'yyMMddHHmm');
    hasTime = ~isnat(t);
    return
end

tok = regexp(base, '(\d{2}-[A-Za-z]{3}-\d{4})', 'tokens', 'once');
if ~isempty(tok)
    t = localParse(tok{1}, 'dd-MMM-yyyy');
end

end




function t = localParse(txt, fmt)
% A datetime from text, or NaT when the text only looks like a timestamp.
try
    t = datetime(txt, 'InputFormat', fmt, 'Locale', 'en_US');
catch
    t = NaT;
end
end




function t = localRecordTime(rec)
% When a trial record was written: computerTimestamp, or inaccurateTimestamp in
% files from before it was renamed.
t = NaT;
if ~isstruct(rec) || isempty(rec), return, end
for f = {'computerTimestamp', 'inaccurateTimestamp'}
    if isfield(rec, f{1}) && ~isempty(rec.(f{1}))
        t = localDatetime(rec.(f{1}));
        if ~isnat(t), return, end
    end
end
end




function t = localDatetime(v)
% A scalar datetime from whatever an older file stored: datetime, datenum, or
% a clock vector. Anything else is NaT.
t = NaT;
try
    if isdatetime(v) && ~isempty(v)
        t = v(1);
    elseif isnumeric(v) && isscalar(v) && v > 7e5
        t = datetime(v, 'ConvertFrom', 'datenum');
    elseif isnumeric(v) && numel(v) == 6
        t = datetime(reshape(v, 1, []));
    end
catch
    t = NaT;
end
t.Format = 'default';
end




function v = localVersion(meta)
% "v2.3.2 (698e7a6)" from EPsychInfo.meta, or whichever half of it survives.
v = "";
if ~isstruct(meta) || ~isscalar(meta), return, end

tag = "";
if isfield(meta, 'LatestTag') && ~isempty(meta.LatestTag)
    tag = string(meta.LatestTag);
elseif isfield(meta, 'Version') && ~isempty(meta.Version)
    tag = "v" + string(meta.Version);
end

sha = "";
if isfield(meta, 'Checksum') && ~isempty(meta.Checksum)
    sha = extractBefore(string(meta.Checksum) + "       ", 8);
    sha = strtrim(sha);
end

if tag ~= "" && sha ~= ""
    v = tag + " (" + sha + ")";
else
    v = tag + sha;
end
end
