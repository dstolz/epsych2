function sess = load(fileOrRow, options)
% sess = behavior.Session.load(file)
% sess = behavior.Session.load(file, Root = root)
% sess = behavior.Session.load(catalogRow)
% Load one saved session.
%
% From a behavior.Catalog row (Catalog.session(key), or a struct with the
% same fields) the session takes its identity -- Key, Project, Subject,
% Tags, Collision, Start, ParameterMeta, Candidates, QCFile -- from the row,
% which is what the browser showed, and only the trial records and snapshot
% from the file. From a bare path it works the identity out as the catalog
% would: the subject is the folder the file sits in, the project the folder
% above (Root's own name when the subject folder is directly under Root), the
% tags come from the name, and the parameters from the snapshot.
%
% The file is read by epsych.SessionFiles.summarize, so every session shape
% (saved .mat, crash-recovery seed, .epj journal) loads as the catalog read
% it, with load warnings held back. A file that cannot be read does NOT
% throw: the session comes back with Error set and no records, so that
% analyze can report it alongside every other session.
%
% Parameters:
%   fileOrRow - file name, or a one-row Catalog Sessions table / struct
%   Root      - the data root, for the Key and the project of a bare path
%               (default ""; a row's Root is worked out from its File and Key)
%
% Returns:
%   sess - behavior.Session
%
% See also: behavior.Catalog.session, epsych.SessionFiles.summarize

arguments
    fileOrRow
    options.Root (1,1) string = ""
end

sess = behavior.Session();
fromRow = istable(fileOrRow) || isstruct(fileOrRow);

if fromRow
    if istable(fileOrRow)
        if height(fileOrRow) ~= 1
            error('behavior:Session:NotOneRow', 'Load one session at a time (got %d rows).', height(fileOrRow));
        end
        sess.Row = fileOrRow;
        r = table2struct(fileOrRow);
    else
        r = fileOrRow;
        sess.Row = struct2table(r, 'AsArray', true);
    end
    file = string(r.File);
else
    file = string(fileOrRow);
end

% --- The one load --------------------------------------------------------------
s = epsych.SessionFiles.summarize(file, UseCache = false, ...
    Extra = @(D, snap) struct('Data', {D}, 'Snapshot', {snap}));

sess.File = file;
sess.Error = s.Error;
if s.Error == "" && ~s.IsSession
    sess.Error = "Not a session file: it holds neither Data nor a recovery info.";
end
if sess.Error == ""
    % Extra ran: summarize calls it on every session it read without error.
    sess.Data = reshape(s.Extra.Data, 1, []);
    sess.Snapshot = s.Extra.Snapshot;
end
sess.Fields = behavior.Session.fieldsOf_(sess.Data);

if fromRow
    sess.Key = r.Key;
    sess.Project = r.Project;
    sess.ProjectPath = r.ProjectPath;
    sess.Subject = r.Subject;
    sess.Tags = reshape(string(r.Tags), 1, []);
    sess.Collision = r.Collision;
    sess.Start = r.Start;
    sess.ParameterMeta = r.ParameterMeta;
    sess.Candidates = r.Candidates;
    sess.QCFile = reshape(string(r.QCFile), 1, []);
    if options.Root ~= ""
        sess.Root = options.Root;
    else
        sess.Root = localRootFromKey(file, sess.Key);
    end
    return
end

% --- Identity from the path, as the catalog works it out -------------------
[folder, base, ext] = fileparts(file);
p = behavior.Catalog.parseName(base + ext);
qc = strings(1, 0);

if options.Root ~= ""
    sess.Root = options.Root;
    sess.Key = behavior.Catalog.keyFor(options.Root, file);
    parts = split(sess.Key, "/");
    folders = reshape(parts(1:end-1), 1, []);
    [~, rootName] = fileparts(options.Root);
    switch numel(folders)
        case 0
            subject = p.NameSubject;
            if subject == "", subject = "(none)"; end
            sess.Project = rootName;
            qc(end+1) = "not_in_subject_folder";
        case 1
            subject = folders(1);
            sess.Project = rootName;
        otherwise
            subject = folders(end);
            sess.Project = folders(end-1);
            sess.ProjectPath = strjoin(folders(1:end-1), "/");
    end
else
    sess.Key = replace(file, "\", "/");
    [above, subject] = fileparts(folder);
    [~, sess.Project] = fileparts(above);
end
sess.Subject = subject;
sess.Tags = p.Tags;
sess.Collision = p.Collision;
sess.Start = p.Start;
if isnat(sess.Start), sess.Start = s.StartTime; end

if isempty(sess.Snapshot)
    sess.ParameterMeta = behavior.Session.parameterTable([]);
else
    sess.ParameterMeta = behavior.Session.parameterTable(sess.Snapshot.Protocol);
end
sess.Candidates = behavior.Session.candidates(sess.Data, sess.ParameterMeta);

% The catalog's file-level flags, for a session no scan has described.
if sess.Error ~= ""
    qc(end+1) = "unreadable";
elseif s.Trials == 0
    qc(end+1) = "no_trials";
end
if s.IsTest, qc(end+1) = "test_mode"; end
if ~p.Parsed
    qc(end+1) = "unparsed_name";
elseif ~strcmpi(p.NameSubject, subject)
    qc(end+1) = "name_mismatch";
end
sess.QCFile = qc;

end




function root = localRootFromKey(file, key)
% The root a row's File sits under: File with its Key taken off the end.
rel = replace(key, "/", filesep);
root = "";
if endsWith(file, rel, 'IgnoreCase', ispc) && strlength(file) > strlength(rel)
    root = extractBefore(file, strlength(file) - strlength(rel) + 1);
    root = regexprep(root, '[\\/]$', '');
end
end
