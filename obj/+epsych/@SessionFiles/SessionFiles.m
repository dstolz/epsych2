classdef SessionFiles
    % epsych.SessionFiles
    % Find a subject's saved sessions on disk and describe each in one row.
    %
    % A session leaves its data at <DataPath>/<Subject>/<Subject>_<stamp>.mat
    % (epsych.RunExpt.defaultFilename) and a crash-recovery copy in the
    % runtime's temporary data folder, RUNTIME_DATA_<Subject>_Box_NN_<stamp>.mat,
    % with its .epj journal beside it. Nothing records WHICH DataPath a session
    % used -- the rig's, a project's, one membership's -- so locations() gathers
    % every one the roster and the session window know about, and scan() looks
    % in each.
    %
    % This is the headless half of gui.SessionBrowser: no figures and no
    % runtime, so it is testable over a temporary folder and usable from a
    % script ("every session M001 ran, newest first").
    %
    % One row per file (summarize returns a scalar struct, scan a table):
    %   File, Folder, FileName  - where it is
    %   Source                  - "Saved" (a saving function wrote it) or
    %                             "Recovery" (the crash-recovery copy)
    %   IsSession               - false for a .mat that is not session data
    %   IsTest                  - a Preview run
    %   StartTime, EndTime      - session start and the last trial's completion
    %   Duration                - EndTime - StartTime
    %   Trials                  - completed trials recorded
    %   BoxID, Paradigm, ProtocolVersion
    %   HasSnapshot             - the file carries its protocol, so a review
    %                             rebuilds the paradigm's controls, not only
    %                             its data displays
    %   VideoFile               - the recording made alongside it, or ""
    %   NotesText, NumNotes     - the operator's session notes
    %   EPsychVersion, Bytes, Modified
    %   Error                   - why the file could not be read, or ""
    %
    % Things a reader would otherwise re-derive:
    %   * A file is a session when whos shows a struct named Data (saved) or a
    %     scalar struct named info (recovery). Anything else in a subject's
    %     folder -- an analysis file, an export -- is decided from whos alone
    %     and never loaded.
    %   * StartTime is the snapshot's session start where the file has one
    %     (saved since 2026-08), else the time in the file name, else the first
    %     trial's completion. Durations of the oldest files are therefore short
    %     by one trial.
    %   * A recovery .mat whose journal was never merged back holds no trials;
    %     scan() then describes the .epj beside it instead, which is also what
    %     epsych.ReviewSession opens.
    %   * Summaries are cached per file on size and modification time, so a
    %     rescan re-reads only what changed. clearCache() drops them.
    %
    % Usage
    %   L = epsych.SessionFiles.locations("M001", Roster = epsych.SubjectRoster);
    %   T = epsych.SessionFiles.scan(L.Names, Roots = L.Roots, VideoRoots = L.VideoRoots);
    %   s = epsych.SessionFiles.summarize("D:\data\M001\M001_260925T090520.mat");
    %
    % Documentation: documentation/epsych/epsych_SessionFiles.md
    % See also: gui.SessionBrowser, epsych.ReviewSession, epsych.TrialJournal

    properties (Constant)
        RECOVERY_PREFIX (1,:) char = 'RUNTIME_DATA_'   % ep_TimerFcn_Start's recovery file prefix
        VIDEO_EXTENSIONS = [".ts" ".avi" ".mp4" ".mkv" ".mov"]
    end

    methods
        function obj = SessionFiles()
            % Not constructible: a namespace for the static functions below.
            error('epsych:SessionFiles:Static', ...
                'epsych.SessionFiles has only static methods.');
        end
    end

    methods (Static)
        L = locations(subjectName, options)  % Where this subject's data can be
        [T, report] = scan(names, options)   % Every session file under those places
        s = summarize(file, options)         % One file, one row

        function clearCache()
            % epsych.SessionFiles.clearCache()
            % Forget every cached summary, so the next scan reads every file.
            epsych.SessionFiles.cache_('clear');
        end

        function s = blank()
            % s = epsych.SessionFiles.blank()
            % A summary with every field at its "unknown" value. The single
            % authority for the field set: scan() builds its empty table from it.
            s = struct( ...
                'File',            "", ...
                'Folder',          "", ...
                'FileName',        "", ...
                'Source',          "", ...
                'IsSession',       false, ...
                'IsTest',          false, ...
                'StartTime',       NaT, ...
                'EndTime',         NaT, ...
                'Duration',        duration(NaN,0,0), ...
                'Trials',          0, ...
                'BoxID',           NaN, ...
                'Paradigm',        "", ...
                'ProtocolVersion', "", ...
                'HasSnapshot',     false, ...
                'VideoFile',       "", ...
                'NotesText',       "", ...
                'NumNotes',        0, ...
                'EPsychVersion',   "", ...
                'Bytes',           0, ...
                'Modified',        NaT, ...
                'Error',           "");
        end
    end

    methods (Static, Access = private)
        function out = cache_(op, key, value)
            % out = cache_(op, key, value)
            % Per-file summaries, keyed by path. A hit also has to match the
            % file's size and modification time, so an overwritten file is read
            % again rather than described from its predecessor.
            %
            %   cache_('get', key, d)  - summary for key if d still matches, else []
            %   cache_('put', key, s)  - remember s (s.Bytes/s.Modified are the stamp)
            %   cache_('clear')
            persistent C
            if isempty(C)
                C = containers.Map('KeyType','char','ValueType','any');
            end

            out = [];
            switch op
                case 'get'
                    if ~C.isKey(key), return, end
                    s = C(key);
                    d = value;
                    if s.Bytes == d.bytes && isequal(s.Modified, epsych.SessionFiles.modified_(d))
                        out = s;
                    end
                case 'put'
                    C(key) = value;
                case 'clear'
                    C = containers.Map('KeyType','char','ValueType','any');
            end
        end

        function t = modified_(d)
            % A dir() entry's modification time as a datetime: the cache stamp,
            % and what summarize reports as Modified.
            t = datetime(d.datenum, 'ConvertFrom','datenum');
        end

        function p = uniquePaths_(p)
            % p = uniquePaths_(p)
            % Trimmed, non-empty, first occurrence of each, order kept. A
            % trailing separator is dropped (except from a drive root) and, on
            % Windows, case is ignored, so D:\Data\ and d:\data are one root
            % rather than one root scanned twice.
            p = strtrim(reshape(string(p), 1, []));
            p = p(strlength(p) > 0);

            trailing = endsWith(p, ["\" "/"]) & ~endsWith(p, [":\" ":/"]) & strlength(p) > 1;
            p(trailing) = extractBefore(p(trailing), strlength(p(trailing)));

            key = p;
            if ispc, key = lower(key); end
            [~, first] = unique(key, 'stable');
            p = p(first);
        end
    end
end
