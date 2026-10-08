classdef Study < handle
    % behavior.Study  One data root as the offline analysis sees it, headless.
    %
    % A Study ties the three things the analysis works from into one object
    % with one set of events: the Catalog (what is on disk), the Project (what
    % a person decided), and the Settings in force (the Project's). Every
    % result is computed through it and remembered, so the window, a script
    % and a test all ask the same object the same questions and get the same
    % answers:
    %
    %   S = behavior.Study("D:\Data\Lab");          % scans, opens the project
    %   T = S.sessions();                           % one row per visible session
    %   S.select(T.Key(1:4));
    %   R = S.results();                            % behavior.Aggregate.thresholds
    %   s = S.Settings;  s.Window = "last 100";  S.setSettings(s);   % forgets every result
    %
    % THE MEMO. A session's result depends on exactly four things: the file
    % (its bytes and modification time, as the Catalog recorded them), the
    % settings (their hash) and the session's trial window. result(key) is
    % memoized on those, so a repaint costs nothing, a settings change costs
    % one analysis per session, and a rescan that finds a file changed costs
    % that file alone. Nothing is written to disk for a result; the analysis
    % is cheap enough to recompute, which is also why the memo is per object.
    %
    % SESSIONS ARE LOADED ON DEMAND and the last few kept (LRU_SIZE), so paging
    % through a subject's sessions does not reload the one just left.
    %
    % PSIGNIFIT FITS AHEAD OF TIME. A psignifit fit takes seconds, everything
    % else about a session milliseconds, so prepare(key) makes a result at
    % once unless its fit is not cached -- then it returns that fit's job and
    % keeps nothing. behavior.Precompute runs those jobs on background
    % workers and calls result(key) as each fit lands; with ParallelFits,
    % results() does the same for its own keys before its loop. IsComputing
    % tells a timer-driven Precompute to wait while a result is being made,
    % so the two never interleave.
    %
    % EVENTS, so a window can follow rather than poll: CatalogChanged (after a
    % scan), ProjectChanged (after any decision: hide, window override,
    % comment, grouping, facet, preset, save), SettingsChanged, SelectionChanged,
    % ResultsChanged (after results() computed anything new), Busy (long work
    % starting or ending, with a message in the event data). The Study never
    % opens a window and never touches a preference; the window owns both.
    %
    % Properties (read-only):
    %   Root, Catalog, Project, Roster   - the parts (Roster [] when none)
    %   Settings (dependent)             - Project.Settings
    %   Selection (dependent)            - the checked keys, Project.Selection.Keys
    %   RosterMode                       - "auto" | "none" | the file used
    %   IsComputing (dependent)          - a result is being made now
    %
    % Properties (settable):
    %   ParallelFits                     - results() fits on background workers
    %                                      (default false)
    %
    % See also: behavior.Catalog, behavior.Project, behavior.Session,
    %   behavior.Aggregate, behavior.Settings

    properties (SetAccess = private)
        Root (1,1) string = ""
        Catalog = []
        Project = []
        Roster = []
        RosterMode (1,1) string = "auto"
    end

    properties (Dependent)
        Settings
        Selection
        IsComputing    % a result is being computed now (behavior.Precompute waits)
    end

    properties
        % results() hands its psignifit fits to background workers (see
        % behavior.Precompute) instead of fitting one after another. Off by
        % default, so a script's Study computes exactly as it always has.
        ParallelFits (1,1) logical = false
    end

    properties (Constant)
        LRU_SIZE = 8
    end

    properties (Access = private)
        Memo_          % containers.Map: memo key -> result struct
        Loaded_        % containers.Map: lowered session key -> behavior.Session
        LoadOrder_ (1,:) string = strings(1, 0)   % least recently used first
        Computing_ (1,1) double = 0   % depth of result/results/prepare calls
    end

    events
        CatalogChanged
        ProjectChanged
        SettingsChanged
        SelectionChanged
        ResultsChanged
        Busy
    end

    methods
        function obj = Study(root, options)
            % S = behavior.Study(root)
            % S = behavior.Study(root, Store = folder, Roster = "auto"|"none"|file, Scan = true)
            %
            % Parameters:
            %   root   - the data root (Project -> Subject -> session files)
            %   Store  - alternate project store folder ("" = <root>/EPsych_Analysis)
            %   Roster - "auto" (the configured epsych.SubjectRoster, if any),
            %            "none", or an .esub path; enriches Catalog.Subjects only
            %   Scan   - scan the root now (default true; a window passes false
            %            and calls rescan with a progress callback)
            arguments
                root (1,1) string
                options.Store (1,1) string = ""
                options.Roster (1,1) string = "auto"
                options.Scan (1,1) logical = true
                options.CacheFolder (1,1) string = behavior.Catalog.defaultCacheFolder()
                options.ReadRecovery (1,1) logical = false
            end

            obj.Memo_ = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.Loaded_ = containers.Map('KeyType', 'char', 'ValueType', 'any');

            obj.Catalog = behavior.Catalog(root, CacheFolder = options.CacheFolder, ...
                ReadRecovery = options.ReadRecovery);
            obj.Root = obj.Catalog.Root;
            obj.Project = behavior.Project.open(obj.Root, Store = options.Store);
            obj.RosterMode = options.Roster;

            if options.Scan
                obj.rescan();
            end
        end

        function s = get.Settings(obj)
            s = obj.Project.Settings;
        end

        function keys = get.Selection(obj)
            keys = reshape(string(obj.Project.Selection.Keys), 1, []);
        end

        function tf = get.IsComputing(obj)
            tf = obj.Computing_ > 0;
        end

        % ------------------------------------------------------------------
        function ok = rescan(obj, options)
            % ok = rescan(obj, Progress = @(k, n) true, UseCache = true)
            % Scan the root again (unchanged files come from the cache), apply the
            % roster, forget results whose file changed, and announce it.
            arguments
                obj
                options.Progress = []
                options.UseCache (1,1) logical = true
            end
            obj.busy_("Scanning " + obj.Root);
            try
                ok = obj.Catalog.scan(Progress = options.Progress, UseCache = options.UseCache);
                if ok
                    obj.applyRoster_();
                    obj.pruneMemo_();
                    obj.Loaded_ = containers.Map('KeyType', 'char', 'ValueType', 'any');
                    obj.LoadOrder_ = strings(1, 0);
                end
            catch ME
                obj.busy_("");
                rethrow(ME);
            end
            obj.busy_("");
            if ok
                notify(obj, 'CatalogChanged');
            end
        end

        function T = sessions(obj, options)
            % T = sessions(obj, IncludeHidden = false)
            % The catalog's sessions with the project's decisions on them:
            % Hidden, HiddenReason, Window (override text), Comment, one
            % Group_<Name> column per grouping, and the roster columns.
            arguments
                obj
                options.IncludeHidden (1,1) logical = false
            end
            T = obj.Project.applyGroupings(obj.Catalog.Sessions);
            T = obj.joinRoster_(T);
            if ~options.IncludeHidden && ismember("Hidden", string(T.Properties.VariableNames))
                T = T(~logical(T.Hidden), :);
            end
        end

        function keys = visibleKeys(obj)
            % keys = visibleKeys(obj)
            % Every session key that is not hidden, in catalog order.
            T = obj.sessions();
            keys = reshape(string(T.Key), 1, []);
        end

        % ------------------------------------------------------------------
        function sess = session(obj, key)
            % sess = session(obj, key)
            % The loaded behavior.Session for a key, from the LRU when it is there.
            arguments
                obj
                key (1,1) string
            end
            row = obj.Catalog.session(key);
            lk = obj.lowerKey_(string(row.Key));
            if obj.Loaded_.isKey(lk)
                sess = obj.Loaded_(lk);
                obj.LoadOrder_(obj.LoadOrder_ == lk) = [];
                obj.LoadOrder_(end+1) = lk;
                return
            end
            sess = behavior.Session.load(row, Root = obj.Root);
            obj.Loaded_(lk) = sess;
            obj.LoadOrder_(end+1) = lk;
            while numel(obj.LoadOrder_) > obj.LRU_SIZE
                obj.Loaded_.remove(char(obj.LoadOrder_(1)));
                obj.LoadOrder_(1) = [];
            end
        end

        function R = result(obj, key)
            % R = result(obj, key)
            % The analysis of one session under the current settings and its
            % window, memoized on the file, the settings hash and the window.
            arguments
                obj
                key (1,1) string
            end
            row = obj.Catalog.session(key);
            win = obj.Project.windowFor(string(row.Key));
            mk = obj.memoKey_(row, win);
            if obj.Memo_.isKey(mk)
                R = obj.Memo_(mk);
                return
            end
            busy = obj.computing_();
            sess = obj.session(key);
            R = sess.analyze(obj.Settings, Window = win);
            obj.Memo_(mk) = R;
            delete(busy);
        end

        function [done, job] = prepare(obj, key)
            % [done, job] = prepare(obj, key)
            % Make a session's result now unless it needs a psignifit fit
            % that is not cached: then return the job that would make it
            % (behavior.fit.Psignifit.submit), and keep nothing -- result(key)
            % makes the result once the fit is in the cache. What
            % behavior.Precompute is built on.
            %
            % Returns:
            %   done - the result is current (it was, or it is now)
            %   job  - [] when done; else the fit's job plus SessionKey and
            %          MemoKey (what isCurrentJob compares)
            arguments
                obj
                key (1,1) string
            end
            job = [];
            row = obj.Catalog.session(key);
            win = obj.Project.windowFor(string(row.Key));
            mk = obj.memoKey_(row, win);
            done = obj.Memo_.isKey(mk);
            if done
                return
            end
            busy = obj.computing_();
            sess = obj.session(key);
            [R, job] = sess.analyze(obj.Settings, Window = win, DeferFit = true);
            delete(busy);
            if isempty(job)
                obj.Memo_(mk) = R;
                done = true;
            else
                job.SessionKey = string(row.Key);
                job.MemoKey = mk;
            end
        end

        function tf = isCurrent(obj, key)
            % tf = isCurrent(obj, key)
            % Whether the session's result under the current settings and
            % window is already made (result(key) would cost nothing).
            arguments
                obj
                key (1,1) string
            end
            row = obj.Catalog.session(key);
            tf = obj.Memo_.isKey(obj.memoKey_(row, obj.Project.windowFor(string(row.Key))));
        end

        function tf = isCurrentJob(obj, job)
            % tf = isCurrentJob(obj, job)
            % Whether a job from prepare is still the one its session needs:
            % false once the settings, its window or its file changed, or
            % the session left the catalog.
            arguments
                obj
                job (1,1) struct
            end
            tf = false;
            try
                row = obj.Catalog.session(job.SessionKey);
            catch
                return
            end
            tf = obj.memoKey_(row, obj.Project.windowFor(string(row.Key))) == job.MemoKey;
        end

        function [T, R] = results(obj, keys, options)
            % [T, R] = results(obj)             the checked sessions
            % [T, R] = results(obj, keys, Progress = @(k, n) true)
            % behavior.Aggregate.thresholds over the sessions' results, with the
            % study-level QC flag parameter_differs (a session analysed on a
            % different parameter than most of the others). R is the results
            % themselves, one struct per key, in the keys' order.
            %
            % With ParallelFits, psignifit fits that are not cached are first
            % made several at a time on background workers
            % (behavior.Precompute.run); Progress then counts sessions made,
            % and stopping it keeps only the results already made.
            arguments
                obj
                keys (1,:) string = obj.Selection
                options.Progress = []
            end
            n = numel(keys);
            R = cell(n, 1);
            computed = false;
            stopped = false;
            if n > 0
                obj.busy_(sprintf("Analysing %d session(s)", n));
            end
            busy = obj.computing_();
            try
                if obj.ParallelFits && n > 1 && behavior.Precompute.isParallel(obj.Settings)
                    P = behavior.Precompute(obj);
                    stopped = ~P.run(keys, Progress = options.Progress);
                    computed = P.Computed > 0;
                    delete(P);
                end
                for k = 1:n
                    if stopped
                        if obj.isCurrent(keys(k))
                            R{k} = obj.result(keys(k));
                        end
                        continue
                    end
                    if ~isempty(options.Progress) && ~options.Progress(k, n)
                        break
                    end
                    row = obj.Catalog.session(keys(k));
                    mk = obj.memoKey_(row, obj.Project.windowFor(string(row.Key)));
                    computed = computed || ~obj.Memo_.isKey(mk);
                    R{k} = obj.result(keys(k));
                end
            catch ME
                delete(busy);
                obj.busy_("");
                rethrow(ME);
            end
            delete(busy);
            obj.busy_("");
            R = R(~cellfun(@isempty, R));
            T = behavior.Aggregate.thresholds(R, obj.sessions(IncludeHidden = true));
            T = obj.flagParameterDiffers_(T);
            if ~isempty(R)
                R = vertcat(R{:});
            else
                R = struct([]);
            end
            if computed
                notify(obj, 'ResultsChanged');
            end
        end

        function T = subjects(obj, keys)
            % T = subjects(obj, keys)
            % The catalog's Subjects rows for the subjects the keys belong to.
            arguments
                obj
                keys (1,:) string = obj.Selection
            end
            S = obj.Catalog.Sessions;
            subj = unique(string(S.Subject(ismember(obj.lowerKey_(string(S.Key)), obj.lowerKey_(keys)))));
            T = obj.Catalog.Subjects(ismember(string(obj.Catalog.Subjects.Subject), subj), :);
        end

        function n = recomputeAll(obj, options)
            % n = recomputeAll(obj, Progress = @(k, n) true)
            % Forget every result and compute the visible sessions again.
            arguments
                obj
                options.Progress = []
            end
            obj.Memo_ = containers.Map('KeyType', 'char', 'ValueType', 'any');
            keys = obj.visibleKeys();
            obj.results(keys, Progress = options.Progress);
            n = numel(keys);
        end

        function invalidate(obj, keys)
            % invalidate(obj, keys)
            % Forget the results of these sessions (any settings, any window).
            arguments
                obj
                keys (1,:) string
            end
            lk = obj.lowerKey_(keys);
            for mk = reshape(string(obj.Memo_.keys()), 1, [])
                head = extractBefore(mk, "|");
                if ismember(head, lk)
                    obj.Memo_.remove(char(mk));
                end
            end
        end

        % ------------------------------------------------------------------
        function select(obj, keys)
            % select(obj, keys)
            % Make these the checked sessions (unknown keys are refused).
            arguments
                obj
                keys (1,:) string
            end
            known = obj.lowerKey_(string(obj.Catalog.Sessions.Key));
            bad = keys(~ismember(obj.lowerKey_(keys), known));
            if ~isempty(bad)
                error('behavior:Study:UnknownKey', ...
                    'Not in the catalog: %s', strjoin(bad, ', '));
            end
            obj.Project.setSelection(keys);
            notify(obj, 'SelectionChanged');
        end

        function setSettings(obj, settings)
            % setSettings(obj, settings)
            % Adopt new analysis settings; a changed hash forgets every result.
            arguments
                obj
                settings (1,1) behavior.Settings
            end
            % The QC limits are outside the settings hash by design (they
            % change flags, not numbers), but a result carries its flags, so
            % they are part of what makes a memoized result current.
            changed = settings.hash() ~= obj.Settings.hash() || ~isequal(settings.QC, obj.Settings.QC);
            obj.Project.setSettings(settings);
            if changed
                obj.Memo_ = containers.Map('KeyType', 'char', 'ValueType', 'any');
            end
            notify(obj, 'SettingsChanged');
            notify(obj, 'ProjectChanged');
        end

        function s = applyPreset(obj, name)
            % s = applyPreset(obj, name)
            % Make a saved preset the settings (and the compare view, when the
            % preset carries one); returns the settings now in force.
            arguments
                obj
                name (1,1) string
            end
            before = obj.Settings;
            s = obj.Project.applyPreset(name);
            if s.hash() ~= before.hash() || ~isequal(s.QC, before.QC)
                obj.Memo_ = containers.Map('KeyType', 'char', 'ValueType', 'any');
            end
            notify(obj, 'SettingsChanged');
            notify(obj, 'ProjectChanged');
        end

        function savePreset(obj, name, options)
            % savePreset(obj, name, View = facets)
            arguments
                obj
                name (1,1) string
                options.View (1,1) struct = struct()
            end
            obj.Project.savePreset(name, View = options.View);
            notify(obj, 'ProjectChanged');
        end

        function deletePreset(obj, name)
            arguments
                obj
                name (1,1) string
            end
            obj.Project.deletePreset(name);
            notify(obj, 'ProjectChanged');
        end

        function renamePreset(obj, oldName, newName)
            arguments
                obj
                oldName (1,1) string
                newName (1,1) string
            end
            obj.Project.renamePreset(oldName, newName);
            notify(obj, 'ProjectChanged');
        end

        function setLevels(obj, name, levels)
            % setLevels(obj, name, levels)
            % The levels (and their order) of a grouping.
            arguments
                obj
                name (1,1) string
                levels (1,:) string
            end
            obj.Project.setLevels(name, levels);
            notify(obj, 'ProjectChanged');
        end

        function setWindow(obj, key, text)
            % setWindow(obj, key, text)
            % A trial window for one session ("" = the settings' window).
            arguments
                obj
                key (1,1) string
                text (1,1) string
            end
            obj.Project.setWindow(key, text);
            obj.invalidate(key);
            notify(obj, 'ProjectChanged');
        end

        function hide(obj, keys, tf, options)
            % hide(obj, keys, tf, Reason = "")
            arguments
                obj
                keys (1,:) string
                tf (1,1) logical = true
                options.Reason (1,1) string = ""
            end
            obj.Project.hide(keys, tf, Reason = options.Reason);
            notify(obj, 'ProjectChanged');
        end

        function setComment(obj, keyOrSubject, text)
            arguments
                obj
                keyOrSubject (1,1) string
                text (1,1) string
            end
            obj.Project.setComment(keyOrSubject, text);
            notify(obj, 'ProjectChanged');
        end

        function addGrouping(obj, name, levels)
            arguments
                obj
                name (1,1) string
                levels (1,:) string
            end
            obj.Project.addGrouping(name, levels);
            notify(obj, 'ProjectChanged');
        end

        function assign(obj, name, subjectOrKey, level)
            arguments
                obj
                name (1,1) string
                subjectOrKey (1,1) string
                level (1,1) string
            end
            obj.Project.assign(name, subjectOrKey, level);
            notify(obj, 'ProjectChanged');
        end

        function removeGrouping(obj, name)
            arguments
                obj
                name (1,1) string
            end
            obj.Project.removeGrouping(name);
            notify(obj, 'ProjectChanged');
        end

        function setFacets(obj, options)
            % setFacets(obj, GroupBy = "tag:1", ColorBy = "subject", XAxis = "date", Value = "Threshold", Kind = "box", ColorMap = "auto", ShowMean = true, Spread = "auto")
            % The compare view (behavior.Project.setFacets).
            arguments
                obj
                options.GroupBy (1,1) string
                options.ColorBy (1,1) string
                options.XAxis (1,1) string
                options.Value (1,1) string
                options.Kind (1,1) string
                options.ColorMap (1,1) string
                options.ShowMean (1,1)
                options.Spread (1,1) string
            end
            args = namedargs2cell(options);
            obj.Project.setFacets(args{:});
            notify(obj, 'ProjectChanged');
        end

        function ok = save(obj)
            % ok = save(obj)
            % Write the project file (behavior.Project.save).
            ok = obj.Project.save();
            notify(obj, 'ProjectChanged');
        end

        function tf = isHidden(obj, key)
            tf = obj.Project.isHidden(key);
        end

        function w = windowFor(obj, key)
            w = obj.Project.windowFor(key);
        end
    end

    methods (Access = private)
        function applyRoster_(obj)
            % Enrich Catalog.Subjects as RosterMode asks; never a hard failure.
            try
                switch obj.RosterMode
                    case "none"
                        return
                    case "auto"
                        obj.Catalog.applyRoster([]);
                    otherwise
                        obj.Catalog.applyRoster(obj.RosterMode);
                end
                obj.Roster = obj.Catalog.Roster;
            catch ME
                vprintf(1, 'behavior.Study: the roster was not applied: %s', ME.message);
            end
        end

        function T = joinRoster_(obj, T)
            % RosterKnown / RosterSex / RosterSpecies onto the sessions, by subject.
            S = obj.Catalog.Subjects;
            cols = ["RosterKnown" "RosterSex" "RosterSpecies"];
            if height(S) == 0 || ~all(ismember(cols, string(S.Properties.VariableNames)))
                return
            end
            n = height(T);
            known = false(n, 1);
            sex = strings(n, 1);
            species = strings(n, 1);
            subjKey = string(S.Project) + "/" + string(S.Subject);
            [tf, where] = ismember(string(T.Project) + "/" + string(T.Subject), subjKey);
            known(tf) = logical(S.RosterKnown(where(tf)));
            sex(tf) = string(S.RosterSex(where(tf)));
            species(tf) = string(S.RosterSpecies(where(tf)));
            T.RosterKnown = known;
            T.RosterSex = sex;
            T.RosterSpecies = species;
        end

        function pruneMemo_(obj)
            % Drop memo entries whose session is gone or whose file changed.
            S = obj.Catalog.Sessions;
            live = strings(height(S), 1);
            for k = 1:height(S)
                live(k) = obj.memoHead_(S(k, :));
            end
            for mk = reshape(string(obj.Memo_.keys()), 1, [])
                head = extractBefore(mk, "||");
                if ~ismember(head, live)
                    obj.Memo_.remove(char(mk));
                end
            end
        end

        function mk = memoKey_(obj, row, win)
            % The QC limits join the key (not the hash): a limit change must
            % re-flag, and a result carries its flags.
            mk = obj.memoHead_(row) + "||" + obj.Settings.hash() + "|" + ...
                string(jsonencode(obj.Settings.QC)) + "|" + win;
        end

        function head = memoHead_(obj, row)
            % key|bytes|modified : what identifies the file's content.
            m = row.Modified;
            if isdatetime(m) && ~isnat(m)
                stamp = string(m, 'yyyyMMddHHmmssSSS');
            else
                stamp = "";
            end
            head = obj.lowerKey_(string(row.Key)) + "|" + string(double(row.Bytes)) + "|" + stamp;
        end

        function k = lowerKey_(~, keys)
            % Keys as the memo and the LRU spell them (behavior.Catalog.keyEquals's rule).
            k = reshape(strrep(string(keys), '\', '/'), size(keys));
            if ispc
                k = lower(k);
            end
        end

        function T = flagParameterDiffers_(~, T)
            % A session analysed on a different parameter than most of the rest.
            n = height(T);
            T.ParameterDiffers = false(n, 1);
            if n < 2, return, end
            p = string(T.Parameter);
            p = p(p ~= "");
            if isempty(p), return, end
            modal = mode(categorical(p));
            differs = string(T.Parameter) ~= string(modal) & string(T.Parameter) ~= "";
            T.ParameterDiffers = differs;
            for k = find(differs)'
                flags = strsplit(T.QC(k), "|");
                flags = flags(strlength(flags) > 0);
                T.QC(k) = strjoin([flags "parameter_differs"], "|");
                T.NumQC(k) = numel(flags) + 1;
            end
        end

        function busy_(obj, message)
            notify(obj, 'Busy', behavior.StudyEvent(message));
        end

        function c = computing_(obj)
            % IsComputing is true until the returned object is deleted (or
            % goes out of scope, which is what an error does to it).
            obj.Computing_ = obj.Computing_ + 1;
            c = onCleanup(@() obj.doneComputing_());
        end

        function doneComputing_(obj)
            if isvalid(obj)
                obj.Computing_ = max(0, obj.Computing_ - 1);
            end
        end
    end
end
