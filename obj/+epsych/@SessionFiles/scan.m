function [T, report] = scan(names, options)
% [T, report] = epsych.SessionFiles.scan(names, Name=Value)
% Every session file for one subject, one row each, newest first.
%
% Looks in <root>/<name>/ for every root and every name -- where
% epsych.RunExpt.defaultFilename puts a session -- and, when asked, in the
% crash-recovery folder for RUNTIME_DATA_<name>_Box_*.mat. It does not recurse:
% a subfolder of a subject's folder is somebody's analysis, not a session.
%
% Parameters:
%   names           - Subject name, then any former names: a folder is named
%                     after whatever the subject was called when it ran.
%   Roots           - Data roots to look under.
%   VideoRoots      - Further roots holding <root>/<subject>/<file>.ts
%                     recordings. Roots are searched for video too, since an
%                     empty video root falls back to the data path.
%   IncludeRecovery - Also list crash-recovery copies. Default false: every
%                     session that saved normally has one of those as well, so
%                     they would double the list -- but a Preview run, a crash,
%                     or a declined save exists ONLY as one.
%   RecoveryDir     - Where the recovery copies are (see locations()).
%   Progress        - @(k, n) called before each of the n files is read;
%                     returning false stops the scan with the rows read so far.
%   UseCache        - Reuse unchanged files' summaries. Default true.
%
% Returns:
%   T      - Table, one row per session file with the fields of blank(),
%            newest first; a file with no start time sorts last.
%   report - Struct: Folders (searched and present), Missing (roots that do not
%            exist), NumFiles (files read), NumSkipped (.mat files that were
%            not session data), Cancelled.
%
% See also: epsych.SessionFiles.locations, epsych.SessionFiles.summarize

arguments
    names (1,:) string
    options.Roots (1,:) string = string.empty(1,0)
    options.VideoRoots (1,:) string = string.empty(1,0)
    options.IncludeRecovery (1,1) logical = false
    options.RecoveryDir (1,1) string = ""
    options.Progress = []
    options.UseCache (1,1) logical = true
end

names = strtrim(names);
names = epsych.SessionFiles.uniquePaths_(names(strlength(names) > 0));
roots = epsych.SessionFiles.uniquePaths_(options.Roots);

report = struct( ...
    'Folders',    string.empty(1,0), ...
    'Missing',    roots(~isfolder(roots)), ...
    'NumFiles',   0, ...
    'NumSkipped', 0, ...
    'Cancelled',  false);

% --- Candidates ----------------------------------------------------------
folders = string.empty(1,0);
for r = roots(isfolder(roots))
    for n = names
        f = fullfile(r, n);
        if isfolder(f), folders(end+1) = f; end
    end
end
folders = epsych.SessionFiles.uniquePaths_(folders);
report.Folders = folders;

files = string.empty(1,0);
for f = folders
    L = dir(fullfile(f, '*.mat'));
    L = L(~[L.isdir]);
    files = [files, reshape(string(fullfile({L.folder}, {L.name})), 1, [])];
end

recoveryDir = epsych.SessionFiles.uniquePaths_(options.RecoveryDir);
if options.IncludeRecovery && ~isempty(recoveryDir) && isfolder(recoveryDir) && ~isempty(names)
    prefix = epsych.SessionFiles.RECOVERY_PREFIX;
    L = dir(fullfile(recoveryDir, [prefix '*.mat']));
    L = L(~[L.isdir]);

    % The name is matched whole: RUNTIME_DATA_M1_Box_ must not find M10's.
    alternatives = strjoin(regexptranslate('escape', cellstr(names)), '|');
    pattern = ['^' prefix '(' alternatives ')_Box_\d+_\d+\.mat$'];
    if ispc
        hit = ~cellfun(@isempty, regexpi({L.name}, pattern, 'once'));
    else
        hit = ~cellfun(@isempty, regexp({L.name}, pattern, 'once'));
    end
    L = L(hit);

    files = [files, reshape(string(fullfile({L.folder}, {L.name})), 1, [])];
    report.Folders(end+1) = recoveryDir;
end

files = epsych.SessionFiles.uniquePaths_(files);

% --- Read ----------------------------------------------------------------
rows = repmat(epsych.SessionFiles.blank(), 1, 0);
n = numel(files);
for k = 1:n
    if ~isempty(options.Progress) && ~options.Progress(k, n)
        report.Cancelled = true;
        break
    end
    report.NumFiles = k;

    s = epsych.SessionFiles.summarize(files(k), UseCache = options.UseCache);
    if ~s.IsSession
        report.NumSkipped = report.NumSkipped + 1;
        continue
    end

    % A seed whose journal was never merged back -- MATLAB killed mid-session
    % -- has its trials only in the .epj beside it, and that is also the file
    % a review has to open.
    if s.Source == "Recovery" && s.Trials == 0 && s.Error == ""
        journal = regexprep(files(k), '\.mat$', '.epj', 'ignorecase');
        if isfile(journal)
            sj = epsych.SessionFiles.summarize(journal, UseCache = options.UseCache);
            if sj.Trials > 0, s = sj; end
        end
    end

    rows(end+1) = s;
end

% --- Recordings ----------------------------------------------------------
videoRoots = epsych.SessionFiles.uniquePaths_([roots, options.VideoRoots]);
rows = localAttachVideo(rows, videoRoots);

% --- Table ---------------------------------------------------------------
if isempty(rows)
    T = struct2table(epsych.SessionFiles.blank(), 'AsArray', true);
    T(1,:) = [];
    return
end

[~, order] = sort([rows.StartTime], 'descend', 'MissingPlacement', 'last');
T = struct2table(reshape(rows(order), [], 1), 'AsArray', true);

end




function rows = localAttachVideo(rows, videoRoots)
% rows = localAttachVideo(rows, videoRoots)
%
% Name the recording made alongside each saved session. epsych.RunExpt names it
% after the data file -- <videoRoot>/<subjectFolder>/<dataFileName>.ts -- and
% a conversion lands beside it as <dataFileName>_conv.mp4, so the exact name is
% preferred and a suffixed one accepted. Each folder is listed once.

listed = containers.Map('KeyType','char','ValueType','any');
exts = epsych.SessionFiles.VIDEO_EXTENSIONS;

for i = 1:numel(rows)
    if rows(i).Source ~= "Saved" || rows(i).Error ~= "", continue, end

    [~, subjectFolder] = fileparts(rows(i).Folder);
    [~, base] = fileparts(rows(i).FileName);

    for vr = videoRoots
        vf = char(fullfile(vr, subjectFolder));
        if ~listed.isKey(vf)
            L = dir(vf);
            L = L(~[L.isdir]);
            v = string({L.name});
            listed(vf) = v(endsWith(lower(v), exts));
        end
        v = listed(vf);
        if isempty(v), continue, end

        exact = v(ismember(lower(v), lower(base + exts)));
        if isempty(exact)
            exact = v(startsWith(v, base + "_", 'IgnoreCase', ispc));
        end
        if ~isempty(exact)
            rows(i).VideoFile = string(fullfile(vf, exact(1)));
            break
        end
    end
end

end
