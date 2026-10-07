classdef Catalog < handle
    % c = behavior.Catalog(root)
    % c = behavior.Catalog(root, CacheFolder = folder, ReadRecovery = true)
    % Every saved session under a data root, listed and described from one
    % load each.
    %
    % A Catalog is what the offline behavioral analysis knows about a data
    % root before it analyses anything: every session file under it, which
    % project and subject it belongs to, the free tags its name carries, and
    % enough from inside it (fields, candidate parameters, outcome counts,
    % trial types, the subject's sex and species, the parameters' units and
    % ranges) to choose an analysis without opening it again. It is the
    % browser's index and the analysis's work list:
    %
    %   c = behavior.Catalog("D:\Data\Lab");
    %   c.scan();
    %   c.Sessions(:, ["Project" "Subject" "Start" "TagText" "Trials"])
    %   keys = c.keysFor(Subject = "SUBJ-ID-1234", Tag = "Post");
    %   c.applyRoster();                 % enrich Subjects from the roster
    %
    % NOTHING IS WRITTEN UNDER ROOT. A data root is somebody's raw data, often
    % a shared or synced drive, and listing it must not change it: no index,
    % no lock, no results beside the sessions. The one file a scan writes is
    % its cache, in CacheFolder -- %LOCALAPPDATA%\EPsych\AnalysisCache by
    % default, else <tempdir>\EPsych\AnalysisCache -- and a CacheFolder inside
    % Root disables the cache rather than break that rule (CacheState then
    % says "disabled (...)"). The analysis store (StoreFolder under Root) is
    % behavior.Project's business, and is never listed as data.
    %
    % SESSIONS ARE FILES, KEYED BY PATH. A session is one saved .mat (a Data
    % struct, as epsych.SessionFiles decides from whos alone), keyed by its
    % path relative to Root with "/" between folders, in its on-disk spelling:
    % "ProjA/SUBJ-ID-1234/SUBJ-ID-1234_261007T114223_PrePassive.mat". A key
    % therefore names the same session on every machine a dataset is copied
    % to, which is what lets a project file, an export and a generated script
    % refer to it. Keys compare case-insensitively on Windows (keyEquals).
    % Hidden folders (".*"), the recycle bin, System Volume Information and
    % the analysis store are never listed; crash-recovery copies
    % (RUNTIME_DATA_*) only with ReadRecovery.
    %
    % SUBJECTS AND PROJECTS COME FROM THE FOLDER TREE. The subject is the
    % folder a session sits in; the project is the folder above that, or
    % Root's own name when the subject folder sits directly under Root. The
    % file name contributes only what no file field records -- its free tags
    % (parseName) -- and a name that disagrees with its folder is a QC flag
    % (name_mismatch), never a refusal. The subject roster, when one is
    % configured, only ENRICHES the Subjects table (applyRoster); it is never
    % written.
    %
    % THE CACHE makes a rescan cost the files that changed. Each file's
    % description is kept against its (key, bytes, modified time); a file
    % whose three still match is not opened again (LastScanReads counts the
    % ones that were). The cache is one MAT-file per Root,
    % <CacheFolder>\catalog_<behavior.hex8(lower(Root))>.mat, rebuilt
    % silently -- nothing is lost but time -- when it is unreadable, belongs
    % to another root, or was written by another CacheVersion.
    %
    % A SCAN IS ATOMIC. Everything is computed into locals and assigned at
    % the end, so a Progress callback that returns false cancels and leaves
    % every property as it was.
    %
    % Properties (read-only):
    %   Root          - Absolute data root, no trailing separator
    %   Sessions      - One row per session file, sorted by Project, then
    %                   Subject in natural order (SUBJ-ID-959 before
    %                   SUBJ-ID-1254), then Start. Columns: Key, File, Folder,
    %                   FileName, Project, ProjectPath, Subject, NameSubject,
    %                   NameOK, Tags, TagText, NumTags, Collision, Start, Date,
    %                   Source, IsSession, IsTest, Trials, Duration, BoxID,
    %                   Paradigm, ProtocolVersion, HasSnapshot, NotesText,
    %                   NumNotes, EPsychVersion, Bytes, Modified, Error,
    %                   Fields, Candidates, Outcome, TrialTypes, NumTest,
    %                   SubjectSex, SubjectSpecies, SubjectWeight,
    %                   ParameterMeta, QCFile
    %   Subjects      - One row per (Project, Subject): NumSessions,
    %                   FirstSession, LastSession, Sex, Species; plus, once
    %                   applyRoster has run, RosterKnown, RosterSex,
    %                   RosterSpecies, RosterProjects, RosterLastProtocol,
    %                   RosterLastProtocolVersion, RosterRetired,
    %                   RosterNameMatch ("current" | "former" | "")
    %   Files         - Every .mat considered, session or not: Key, File,
    %                   IsSession, Bytes, Modified, Error
    %   Warnings      - Unreadable and empty sessions, cache problems
    %   ScannedAt     - When the last completed scan finished
    %   CacheFolder, CacheFile, CacheState ("new" | "loaded" |
    %                   "rebuilt (<why>)" | "disabled (<why>)")
    %   LastScanReads - Files the last scan actually opened
    %   ReadRecovery  - List crash-recovery copies too
    %   Roster, RosterFile - What applyRoster used ([] / "" when none)
    %
    % QCFile flags (file-level; the analysis adds its own): unreadable,
    % no_trials, test_mode, name_mismatch, unparsed_name,
    % not_in_subject_folder.
    %
    % Documentation: documentation/behavior/behavior_Classes.md
    % See also: epsych.SessionFiles.summarize, behavior.hex8,
    %   epsych.SubjectRoster

    properties (Constant)
        CacheVersion (1,1) double = 1
        StoreFolder (1,1) string = "EPsych_Analysis"
        SkipFolders (1,:) string = [".*" "$RECYCLE.BIN" "System Volume Information" "EPsych_Analysis"]
    end

    properties (SetAccess = private)
        Root (1,1) string = ""
        Sessions table = table()
        Subjects table = table()
        Files table = table()
        Warnings (:,1) string = strings(0,1)
        ScannedAt (1,1) datetime = NaT
        CacheFolder (1,1) string = ""
        CacheFile (1,1) string = ""
        CacheState (1,1) string = "new"
        LastScanReads (1,1) double = 0
        ReadRecovery (1,1) logical = false
        Roster = []
        RosterFile (1,1) string = ""
    end

    properties (Access = private)
        RosterApplied_ (1,1) logical = false   % keep the roster columns across rescans
    end

    methods
        function obj = Catalog(root, options)
            % c = behavior.Catalog(root)
            % c = behavior.Catalog(root, CacheFolder = folder, ReadRecovery = true)
            %
            % Parameters:
            %   root         - Data root folder. Must exist.
            %   CacheFolder  - Where the scan cache goes. Default
            %                  defaultCacheFolder(); "" disables the cache,
            %                  and so does a folder inside root.
            %   ReadRecovery - Also list crash-recovery copies
            %                  (RUNTIME_DATA_*). Default false: a session that
            %                  saved normally has one of those too.
            arguments
                root (1,1) string
                options.CacheFolder (1,1) string = behavior.Catalog.defaultCacheFolder()
                options.ReadRecovery (1,1) logical = false
            end

            if ~isfolder(root)
                error('behavior:Catalog:NoRoot', 'The data root "%s" is not a folder.', root);
            end

            obj.Root = behavior.Catalog.absolute_(root);
            obj.ReadRecovery = options.ReadRecovery;

            if strtrim(options.CacheFolder) == ""
                obj.CacheState = "disabled (no cache folder)";
            else
                obj.CacheFolder = behavior.Catalog.absolute_(options.CacheFolder);
                if behavior.Catalog.isInside_(obj.CacheFolder, obj.Root)
                    obj.CacheState = "disabled (the cache folder is inside the data root)";
                    vprintf(1, 'behavior.Catalog: the cache folder is inside the data root, so scans of "%s" are not cached', obj.Root)
                else
                    obj.CacheFile = fullfile(obj.CacheFolder, ...
                        "catalog_" + behavior.hex8(lower(char(obj.Root))) + ".mat");
                end
            end

            obj.Sessions = behavior.Catalog.sessionsTable_(behavior.Catalog.blankRow_([]));
            obj.Subjects = behavior.Catalog.subjectsTable_(obj.Sessions);
            obj.Files = behavior.Catalog.filesTable_(strings(0,1), strings(0,1), ...
                false(0,1), zeros(0,1), NaT(0,1), strings(0,1));
        end

        ok = scan(obj, options)          % List and describe every session under Root
        applyRoster(obj, roster)          % Enrich Subjects from the subject roster
        row = session(obj, key)           % One Sessions row by key
        keys = keysFor(obj, options)      % Keys matching a subject/project/tag filter
    end

    methods (Static)
        p = parseName(base)               % Subject prefix, start, collision letter, tags
        key = keyFor(root, file)          % Path relative to root with "/"
        tf = keyEquals(a, b)              % Key comparison (case-insensitive on Windows)
        f = defaultCacheFolder()          % %LOCALAPPDATA%\EPsych\AnalysisCache, else tempdir
    end

    methods (Access = private)
        s = describeFile_(obj, file)
        [records, state] = loadCache_(obj)
        msg = saveCache_(obj, records)
    end

    methods (Static, Access = private)
        x = extra_(Data, info)
        T = sessionsTable_(R)
        T = subjectsTable_(S)
        T = rosterColumns_(T, R)

        function x = blankExtra_()
            % What extra_ returns for a session with nothing in it, and what a
            % row gets when summarize could not run extra_ at all.
            x = struct( ...
                'Fields',         {strings(1,0)}, ...
                'Candidates',     table(strings(0,1), strings(0,1), zeros(0,1), false(0,1), ...
                                      'VariableNames', {'Field','Class','NumUnique','IsParameter'}), ...
                'Outcome',        struct('Hit',0,'Miss',0,'CorrectReject',0,'FalseAlarm',0,'Abort',0), ...
                'TrialTypes',     table(zeros(0,1), zeros(0,1), 'VariableNames', {'TrialType','Count'}), ...
                'NumTest',        0, ...
                'SubjectName',    "", ...
                'SubjectSex',     "", ...
                'SubjectSpecies', "", ...
                'SubjectWeight',  NaN, ...
                'ParameterMeta',  table(strings(0,1), strings(0,1), strings(0,1), zeros(0,1), ...
                                      zeros(0,1), strings(0,1), strings(0,1), strings(0,1), ...
                                      'VariableNames', {'Field','Name','Unit','Min','Max','Type','Interface','Module'}));
        end

        function r = blankRow_(n)
            % One Sessions row at its "unknown" values (n = [] for the
            % prototype alone). Every column's type is decided here, which is
            % what lets sessionsTable_ build a typed empty table.
            x = behavior.Catalog.blankExtra_();
            r = struct( ...
                'Key', "", 'File', "", 'Folder', "", 'FileName', "", ...
                'Project', "", 'ProjectPath', "", 'Subject', "", 'NameSubject', "", ...
                'NameOK', false, 'Tags', {strings(1,0)}, 'TagText', "", 'NumTags', 0, ...
                'Collision', "", 'Start', NaT, 'Date', NaT, 'Source', "", ...
                'IsSession', false, 'IsTest', false, 'Trials', 0, 'Duration', duration(NaN,0,0), ...
                'BoxID', NaN, 'Paradigm', "", 'ProtocolVersion', "", 'HasSnapshot', false, ...
                'NotesText', "", 'NumNotes', 0, 'EPsychVersion', "", 'Bytes', 0, ...
                'Modified', NaT, 'Error', "", ...
                'Fields', {x.Fields}, 'Candidates', x.Candidates, 'Outcome', x.Outcome, ...
                'TrialTypes', x.TrialTypes, 'NumTest', 0, 'SubjectSex', "", ...
                'SubjectSpecies', "", 'SubjectWeight', NaN, 'ParameterMeta', x.ParameterMeta, ...
                'QCFile', {strings(1,0)});
            if ~isempty(n)
                r = repmat(r, 1, n);
            end
        end

        function T = filesTable_(key, file, isSession, bytes, modified, err)
            T = table(key, file, isSession, bytes, modified, err, 'VariableNames', ...
                {'Key','File','IsSession','Bytes','Modified','Error'});
        end

        function k = naturalKey_(s)
            % k = naturalKey_(s)
            % Sort key that orders text the way a person reads numbers in it:
            % every digit run zero-padded, so SUBJ-ID-959 sorts before
            % SUBJ-ID-1254. Case is ignored.
            k = string(regexprep(cellstr(lower(string(s))), '(\d+)', '${pad($1,24,''left'',''0'')}'));
            k = reshape(k, size(s));
        end

        function p = absolute_(p)
            % p = absolute_(p)
            % An absolute path with no trailing separator (except a drive
            % root). An existing folder is resolved through dir, which also
            % collapses "." and "..".
            p = string(strtrim(p));
            if ispc
                isAbs = ~isempty(regexp(p, '^([A-Za-z]:[\\/]|[\\/]{2})', 'once'));
            else
                isAbs = startsWith(p, "/");
            end
            if ~isAbs
                p = string(fullfile(pwd, p));
            end
            if isfolder(p)
                d = dir(p);
                d = d(strcmp({d.name}, '.'));
                if ~isempty(d)
                    p = string(d(1).folder);
                end
            end
            if ispc
                p = replace(p, "/", "\");
            end
            if strlength(p) > 1 && endsWith(p, filesep) && ~endsWith(p, ":" + filesep)
                p = extractBefore(p, strlength(p));
            end
        end

        function tf = isInside_(p, root)
            % Whether folder p is root or anywhere below it.
            a = p + filesep;
            b = root + filesep;
            if endsWith(root, filesep), b = root; end
            tf = startsWith(a, b, 'IgnoreCase', ispc);
        end
    end
end
