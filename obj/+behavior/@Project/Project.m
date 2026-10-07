classdef Project < handle
    % P = behavior.Project.open(root)
    % P = behavior.Project.open(root, Store = folder)
    % What a person decided about a data root, kept in one JSON file.
    %
    % A behavior.Catalog says what is ON DISK; a Project says what somebody
    % DECIDED about it: which sessions are hidden and why, a trial window that
    % overrides the analysis settings for one session, comments on sessions
    % and subjects, the analysis settings themselves, named presets, the
    % compare view's facets, named manual groupings (a level per subject, with
    % per-session overrides), and which sessions are checked for analysis.
    % Everything is in ONE file, <root>/EPsych_Analysis/project.json
    % (behavior.Catalog.StoreFolder), or <Store>/project.json when the root
    % cannot be written and an alternate store folder is given:
    %
    %   P = behavior.Project.open("D:\Data\Lab");
    %   P.hide("ProjA/M01/M01_261001T090000_Pre.mat", true, Reason = "lid open");
    %   P.setWindow("ProjA/M01/M01_261001T090000_Pre.mat", "20+");
    %   P.addGrouping("Treatment", ["Control" "Noise"]);
    %   P.assign("Treatment", "M01", "Noise");
    %   T = P.applyGroupings(catalog.Sessions);   % + Group_Treatment, Hidden, Window, Comment
    %   P.save();
    %
    % OPENING WRITES NOTHING: no folder, no file. A root that is only being
    % looked at stays exactly as it was; the store folder appears at the first
    % save. A file that cannot be read, or one written by a newer EPsych
    % (FormatVersion), opens READ-ONLY with a Warnings entry saying why,
    % keeping whatever could be read -- saving over it would destroy what this
    % version does not understand.
    %
    % SAVING MERGES. A project file on a shared drive may be edited by two
    % people at once, so save() re-reads the file when it changed since it was
    % loaded (bytes and modification time, LoadedStamp) and merges RECORD BY
    % RECORD: session rows by key, subject rows by name, presets and groupings
    % by name -- the later Modified wins, and a record only one side has is
    % kept -- while Settings, Facets and Selection are merged as wholes by
    % their own Modified time. A record one side REMOVED is told apart from one
    % the other side ADDED by the state last read (a record present then and
    % untouched since is a removal, not an addition), so a session un-hidden,
    % or a preset deleted, does not come back from the other writer's copy.
    % The write is atomic (a temp file in the store folder, then movefile) and
    % the previous file is copied to <Store>/.history first, the newest three
    % kept.
    %
    % ENCODING (what makes the file round-trip): every datetime is ISO text to
    % the millisecond (yyyy-MM-dd'T'HH:mm:ss.SSS, so two edits in one second
    % still order; "" = never); windows are TrialWindow text; "find it"
    % numbers are []; records are ARRAYS OF OBJECTS, never objects keyed by
    % path (jsondecode would mangle a key into a field name); and the file
    % holds no NaN, Inf or null. Fields this version does not know are
    % ignored (debug log); fields it expects and the file lacks take their
    % defaults, since the file may predate them.
    %
    % Only session rows that differ from the defaults (not hidden, no window,
    % no comment) are kept, so the file grows with decisions, not with data.
    % Edits are allowed on a ReadOnly project; only save() refuses.
    %
    % Properties (read-only):
    %   Root, Store, File - Data root, store folder, and the project file
    %   FormatVersion     - Version of the file as read (FORMAT_VERSION if new)
    %   Revision          - Saves so far; every save adds one
    %   Saved, Writer     - When, and by whom ("user@host"), it was last saved
    %   Settings          - behavior.Settings; SettingsModified its time
    %   Presets           - struct array: Name, Settings (Settings STRUCT),
    %                       View (GroupBy/ColorBy/XAxis/Value/Kind, or no
    %                       fields), Modified
    %   Facets            - struct: GroupBy, ColorBy, XAxis (facet text),
    %                       Value, Kind, Modified
    %   Groupings         - struct array: Name, Levels (1,:) string, Subjects
    %                       (Subject/Level), Sessions (Key/Level), Modified
    %   Sessions          - table: Key, Hidden, HiddenReason, Window, Comment,
    %                       Modified
    %   Subjects          - table: Subject, Comment, Modified
    %   Selection         - struct: Keys (1,:) string, Modified
    %   Dirty             - Edited since the last load or save
    %   ReadOnly          - save() refuses (see Warnings)
    %   Warnings          - What could not be read or saved, one per line
    %   LoadedStamp       - Exists/Bytes/Modified of the file as last read
    %
    % Documentation: documentation/behavior/behavior_Classes.md
    % See also: behavior.Catalog, behavior.Settings, behavior.Facet,
    %   psychophysics.TrialWindow

    properties (Constant)
        FORMAT_VERSION (1,1) double = 1
        FileName (1,1) string = "project.json"
        HistoryFolder (1,1) string = ".history"
        HistoryKeep (1,1) double = 3
        ViewKinds (1,:) string = ["box" "bar" "strip" "lines" "overlay"]
        TimeFormat (1,1) string = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    end

    properties (SetAccess = private)
        Root (1,1) string = ""
        Store (1,1) string = ""
        File (1,1) string = ""
        FormatVersion (1,1) double = 1
        Revision (1,1) double = 0
        Saved (1,1) datetime = NaT
        Writer (1,1) string = ""
        Settings (1,1) behavior.Settings = behavior.Settings()
        SettingsModified (1,1) datetime = NaT
        Presets struct
        Facets (1,1) struct
        Groupings struct
        Sessions table
        Subjects table
        Selection (1,1) struct
        Dirty (1,1) logical = false
        ReadOnly (1,1) logical = false
        Warnings (:,1) string = strings(0,1)
        LoadedStamp (1,1) struct
    end

    properties (Access = private)
        Base_ (1,1) struct        % record identities as last read or written (merge_)
        CanWrite_ = []            % [] = not probed yet
        CanWritePath_ (1,1) string = ""
    end

    methods (Access = private)
        function P = Project(root, store)
            % Use behavior.Project.open.
            P.Root = root;
            P.Store = store;
            P.File = string(fullfile(store, behavior.Project.FileName));
            P.FormatVersion = behavior.Project.FORMAT_VERSION;
            P.Presets = behavior.Project.emptyPresets_();
            P.Facets = behavior.Project.defaultFacets_();
            P.Groupings = behavior.Project.emptyGroupings_();
            P.Sessions = behavior.Project.emptySessions_();
            P.Subjects = behavior.Project.emptySubjects_();
            P.Selection = struct('Keys', strings(1,0), 'Modified', NaT);
            P.LoadedStamp = behavior.Project.stamp_("");
            P.Base_ = behavior.Project.baseOf_(P);
        end
    end

    methods
        ok = save(P)                       % Merge with the file on disk, then write it
        tf = canWrite(P)                   % Whether the store folder can be written
        s = toStruct(P)                    % The file's content, JSON-ready
        T = applyGroupings(P, T)           % Group_<Name>, Hidden, Window, Comment columns

        function delete(~)
            % Nothing to release: the file is open only while it is read or
            % written.
        end

        % ----------------------------------------------------------- sessions
        function hide(P, keys, tf, options)
            % hide(P, keys, tf, Reason = "")
            % Hide (tf true) or show sessions. A reason is kept only while
            % hidden.
            arguments
                P
                keys string
                tf (1,1) logical = true
                options.Reason (1,1) string = ""
            end
            reason = strtrim(options.Reason);
            if ~tf, reason = ""; end
            for k = reshape(behavior.Project.cleanKey_(keys), 1, [])
                P.editSession_(k, "Hidden", tf, "HiddenReason", reason);
            end
        end

        function setWindow(P, key, text)
            % setWindow(P, key, text)
            % A trial window for one session that overrides Settings.Window;
            % "" clears it. The text is anything psychophysics.TrialWindow.parse
            % reads, stored as its canonical toText ("3:83" -> "3-83"); text
            % it cannot read is refused with an error.
            arguments
                P
                key (1,1) string
                text (1,1) string
            end
            text = strtrim(text);
            if text ~= ""
                try
                    w = psychophysics.TrialWindow.parse(text);
                catch ME
                    error('behavior:Project:InvalidWindow', ...
                        'Cannot use "%s" as a trial window: %s', text, ME.message);
                end
                text = w.toText();
            end
            P.editSession_(behavior.Project.cleanKey_(key), "Window", text);
        end

        function setComment(P, keyOrSubject, text)
            % setComment(P, keyOrSubject, text)
            % A comment on a session (given its key) or on a subject (given its
            % name); "" clears it. A key is anything with a folder separator
            % or ending ".mat"; a subject name never has either.
            arguments
                P
                keyOrSubject (1,1) string
                text (1,1) string
            end
            text = strtrim(text);
            if behavior.Project.isSessionKey_(keyOrSubject)
                P.editSession_(behavior.Project.cleanKey_(keyOrSubject), "Comment", text);
                return
            end
            subject = strtrim(keyOrSubject);
            i = find(behavior.Project.normKey_(P.Subjects.Subject) == behavior.Project.normKey_(subject), 1);
            if isempty(i)
                if text == "", return, end
                P.Subjects = [P.Subjects; table(subject, text, behavior.Project.now_(), ...
                    'VariableNames', {'Subject', 'Comment', 'Modified'})];
            elseif text == ""
                P.Subjects(i, :) = [];
            elseif P.Subjects.Comment(i) == text
                return
            else
                P.Subjects.Comment(i) = text;
                P.Subjects.Modified(i) = behavior.Project.now_();
            end
            P.Dirty = true;
        end

        % ----------------------------------------------------------- settings
        function setSettings(P, s)
            % setSettings(P, s)
            % The analysis settings. Settings equal to the current ones are no
            % edit, so a view echoing them back leaves the project clean.
            arguments
                P
                s (1,1) behavior.Settings
            end
            if isequal(s.toStruct(), P.Settings.toStruct()), return, end
            P.Settings = s;
            P.SettingsModified = behavior.Project.now_();
            P.Dirty = true;
        end

        function savePreset(P, name, options)
            % savePreset(P, name, View = struct())
            % Keep the current Settings under a name (replacing a preset of
            % that name). View, when it has fields, is the compare view the
            % preset also restores: any of GroupBy, ColorBy, XAxis, Value,
            % Kind, the rest taken from the current Facets.
            arguments
                P
                name (1,1) string
                options.View (1,1) struct = struct()
            end
            name = behavior.Project.checkName_(name, "preset");
            rec = struct('Name', name, 'Settings', P.Settings.toStruct(), ...
                'View', P.completeView_(options.View), 'Modified', behavior.Project.now_());
            i = find(string([P.Presets.Name]) == name, 1);
            if isempty(i)
                P.Presets(end+1) = rec;
            else
                P.Presets(i) = rec;
            end
            P.Dirty = true;
        end

        function s = applyPreset(P, name)
            % s = applyPreset(P, name)
            % Make a preset's settings the current ones (and its view the
            % current Facets, when it carries one). Returns the Settings.
            arguments
                P
                name (1,1) string
            end
            i = P.presetIndex_(name);
            [s, w] = behavior.Settings.fromStruct(P.Presets(i).Settings);
            if ~isempty(w)
                P.Warnings = [P.Warnings; "Preset """ + name + """: " + w];
            end
            P.setSettings(s);
            V = P.Presets(i).View;
            if ~isempty(fieldnames(V))
                args = namedargs2cell(V);
                P.setFacets(args{:});
            end
        end

        function deletePreset(P, name)
            % deletePreset(P, name)
            % Remove a preset. One that does not exist is no edit.
            arguments
                P
                name (1,1) string
            end
            i = find(string([P.Presets.Name]) == strtrim(name), 1);
            if isempty(i)
                vprintf(2, 'behavior.Project: there is no preset "%s" to delete', name)
                return
            end
            P.Presets(i) = [];
            P.Dirty = true;
        end

        function renamePreset(P, oldName, newName)
            % renamePreset(P, oldName, newName)
            % A preset under a new name, its settings and view unchanged.
            arguments
                P
                oldName (1,1) string
                newName (1,1) string
            end
            i = P.presetIndex_(oldName);
            newName = behavior.Project.checkName_(newName, "preset");
            if newName == P.Presets(i).Name, return, end
            if any(string([P.Presets.Name]) == newName)
                error('behavior:Project:PresetExists', 'There is already a preset "%s".', newName);
            end
            P.Presets(i).Name = newName;
            P.Presets(i).Modified = behavior.Project.now_();
            P.Dirty = true;
        end

        % ---------------------------------------------------------- groupings
        function addGrouping(P, name, levels)
            % addGrouping(P, name, levels)
            % A named manual grouping (Treatment: Control, Noise). Its column
            % is Group_<matlab.lang.makeValidName(name)>, so two names that
            % would make the same column are refused.
            arguments
                P
                name (1,1) string
                levels string = strings(1,0)
            end
            name = behavior.Project.checkName_(name, "grouping");
            col = behavior.Project.groupColumn_(name);
            if any(arrayfun(@(g) behavior.Project.groupColumn_(g.Name) == col, P.Groupings))
                error('behavior:Project:GroupingExists', ...
                    'There is already a grouping "%s" (or one with the same column, %s).', name, col);
            end
            rec = struct('Name', name, 'Levels', behavior.Project.checkLevels_(levels), ...
                'Subjects', struct('Subject', {}, 'Level', {}), ...
                'Sessions', struct('Key', {}, 'Level', {}), ...
                'Modified', behavior.Project.now_());
            P.Groupings(end+1) = rec;
            P.Dirty = true;
        end

        function assign(P, name, subjectOrKey, level)
            % assign(P, name, subjectOrKey, level)
            % Put subjects (by name) or single sessions (by key -- a
            % per-session override of the subject's level) into one level
            % of a grouping; "" clears the assignment. The level must be one
            % of the grouping's Levels.
            arguments
                P
                name (1,1) string
                subjectOrKey string
                level (1,1) string
            end
            g = P.groupingIndex_(name);
            G = P.Groupings(g);
            level = strtrim(level);
            if level ~= "" && ~ismember(level, G.Levels)
                error('behavior:Project:UnknownLevel', ...
                    'Grouping "%s" has no level "%s" (it has: %s).', G.Name, level, ...
                    strjoin(G.Levels, ", "));
            end
            changed = false;
            for t = reshape(strtrim(subjectOrKey), 1, [])
                if behavior.Project.isSessionKey_(t)
                    [G.Sessions, c] = behavior.Project.setAssignment_(G.Sessions, "Key", ...
                        behavior.Project.cleanKey_(t), level);
                else
                    [G.Subjects, c] = behavior.Project.setAssignment_(G.Subjects, "Subject", t, level);
                end
                changed = changed || c;
            end
            if ~changed, return, end
            G.Modified = behavior.Project.now_();
            P.Groupings(g) = G;
            P.Dirty = true;
        end

        function removeGrouping(P, name)
            % removeGrouping(P, name)
            % Remove a grouping and every assignment in it.
            arguments
                P
                name (1,1) string
            end
            g = find(string([P.Groupings.Name]) == strtrim(name), 1);
            if isempty(g)
                vprintf(2, 'behavior.Project: there is no grouping "%s" to remove', name)
                return
            end
            P.Groupings(g) = [];
            P.Dirty = true;
        end

        function setLevels(P, name, levels)
            % setLevels(P, name, levels)
            % A grouping's levels. Assignments to a level that is no longer
            % there are cleared.
            arguments
                P
                name (1,1) string
                levels string
            end
            g = P.groupingIndex_(name);
            G = P.Groupings(g);
            levels = behavior.Project.checkLevels_(levels);
            if isequal(levels, G.Levels), return, end
            G.Levels = levels;
            dropSubj = ~ismember(string([G.Subjects.Level]), levels);
            dropSess = ~ismember(string([G.Sessions.Level]), levels);
            if any(dropSubj) || any(dropSess)
                vprintf(1, 'behavior.Project: grouping "%s" lost %d subject and %d session assignment(s) with its levels', ...
                    G.Name, sum(dropSubj), sum(dropSess))
            end
            G.Subjects(dropSubj) = [];
            G.Sessions(dropSess) = [];
            G.Modified = behavior.Project.now_();
            P.Groupings(g) = G;
            P.Dirty = true;
        end

        % -------------------------------------------------------- view, check
        function setFacets(P, options)
            % setFacets(P, GroupBy=, ColorBy=, XAxis=, Value=, Kind=)
            % The compare view. GroupBy, ColorBy and XAxis are facet text
            % (behavior.Facet.toText: "tag:1", "manual:Treatment", "month"),
            % refused when behavior.Facet.fromText cannot read it; Value names
            % a result column; Kind is one of ViewKinds. Only the options
            % given change (no defaults, so "not stated" stays distinct).
            arguments
                P
                options.GroupBy (1,1) string
                options.ColorBy (1,1) string
                options.XAxis (1,1) string
                options.Value (1,1) string
                options.Kind (1,1) string
            end
            F = P.Facets;
            for f = reshape(string(fieldnames(options)), 1, [])
                F.(f) = behavior.Project.checkViewField_(f, options.(f));
            end
            if isequal(rmfield(F, 'Modified'), rmfield(P.Facets, 'Modified')), return, end
            F.Modified = behavior.Project.now_();
            P.Facets = F;
            P.Dirty = true;
        end

        function setSelection(P, keys)
            % setSelection(P, keys)
            % The checked (analysed) sessions, in order, duplicates dropped.
            arguments
                P
                keys string
            end
            keys = reshape(behavior.Project.cleanKey_(keys), 1, []);
            [~, ia] = unique(behavior.Project.normKey_(keys), 'stable');
            keys = keys(sort(ia));
            if isequal(keys, P.Selection.Keys), return, end
            P.Selection = struct('Keys', keys, 'Modified', behavior.Project.now_());
            P.Dirty = true;
        end

        % ------------------------------------------------------------ readers
        function tf = isHidden(P, keys)
            % tf = isHidden(P, keys)
            % Whether each session is hidden; logical, the size of keys.
            arguments
                P
                keys string
            end
            [in, loc] = ismember(behavior.Project.normKey_(keys), behavior.Project.normKey_(P.Sessions.Key));
            tf = false(size(keys));
            tf(in) = P.Sessions.Hidden(loc(in));
        end

        function w = windowFor(P, keys)
            % w = windowFor(P, keys)
            % Each session's trial-window override; "" = Settings.Window.
            arguments
                P
                keys string
            end
            w = P.sessionField_(keys, "Window");
        end

        function c = commentFor(P, keyOrSubject)
            % c = commentFor(P, keyOrSubject)
            % The comment on a session (by key) or a subject (by name); "".
            arguments
                P
                keyOrSubject (1,1) string
            end
            if behavior.Project.isSessionKey_(keyOrSubject)
                c = P.sessionField_(keyOrSubject, "Comment");
                return
            end
            i = find(behavior.Project.normKey_(P.Subjects.Subject) == ...
                behavior.Project.normKey_(strtrim(keyOrSubject)), 1);
            c = "";
            if ~isempty(i), c = P.Subjects.Comment(i); end
        end

        function L = groupingLevel(P, name, key, subject)
            % L = groupingLevel(P, name, key, subject)
            % A session's level in a grouping: its own override, else its
            % subject's level, else "". A grouping that does not exist (a
            % saved view may outlive one) is "" too.
            arguments
                P
                name (1,1) string
                key (1,1) string
                subject (1,1) string
            end
            L = "";
            g = find(string([P.Groupings.Name]) == strtrim(name), 1);
            if isempty(g)
                vprintf(3, 'behavior.Project: there is no grouping "%s"', name)
                return
            end
            G = P.Groupings(g);
            i = find(behavior.Project.normKey_([G.Sessions.Key]) == behavior.Project.normKey_(key), 1);
            if ~isempty(i), L = G.Sessions(i).Level; return, end
            i = find(behavior.Project.normKey_([G.Subjects.Subject]) == behavior.Project.normKey_(subject), 1);
            if ~isempty(i), L = G.Subjects(i).Level; end
        end

        function txt = summary(P)
            % txt = summary(P)
            % One line: file, revision, what it holds, and its state.
            if height(P.Sessions) == 0 && height(P.Subjects) == 0 && P.Revision == 0 ...
                    && ~P.LoadedStamp.Exists
                txt = sprintf('%s (new)', P.File);
            else
                txt = sprintf('%s r%d: %d hidden, %d window override(s), %d comment(s), %d grouping(s), %d preset(s), %d selected', ...
                    P.File, P.Revision, sum(P.Sessions.Hidden), sum(P.Sessions.Window ~= ""), ...
                    sum(P.Sessions.Comment ~= "") + height(P.Subjects), numel(P.Groupings), ...
                    numel(P.Presets), numel(P.Selection.Keys));
            end
            if ~isnat(P.Saved)
                txt = sprintf('%s; saved %s by %s', txt, char(P.Saved, 'yyyy-MM-dd HH:mm'), P.Writer);
            end
            if P.Dirty, txt = [txt '; unsaved changes']; end
            if P.ReadOnly, txt = [txt '; READ-ONLY']; end
            txt = string(txt);
        end
    end

    methods (Static)
        P = open(root, options)            % Read the project file, or start one in memory
    end

    methods (Static, Access = private)
        P = fromStruct_(s, root, store)
        [s, why] = readFile_(file)

        function k = cleanKey_(k)
            % A key as stored: "/" between folders, no surrounding blanks.
            k = strtrim(replace(string(k), "\", "/"));
        end

        function k = normKey_(k)
            % behavior.Catalog.keyEquals' rule, in a form ismember can use.
            k = replace(string(k), "\", "/");
            if ispc, k = lower(k); end
        end

        function tf = isSessionKey_(s)
            tf = contains(s, ["/" "\"]) || endsWith(lower(s), ".mat");
        end

        function t = now_()
            % Now, to the millisecond, so a stamp survives its own ISO text
            % exactly and merge_ compares like with like.
            t = behavior.Project.parseIso_(behavior.Project.iso_(datetime('now')));
        end

        function txt = iso_(t)
            if isnat(t)
                txt = "";
            else
                txt = string(char(t, behavior.Project.TimeFormat));
            end
        end

        function t = parseIso_(txt)
            % ISO text to datetime: "" is NaT, and text without milliseconds
            % (a hand-written file) is read too.
            txt = strtrim(string(txt));
            if isempty(txt) || txt == ""
                t = NaT;
                return
            end
            try
                t = datetime(txt, 'InputFormat', behavior.Project.TimeFormat);
            catch
                t = datetime(txt, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss');
            end
        end

        function st = stamp_(file)
            % What says a file changed: existence, bytes and modified time.
            st = struct('Exists', false, 'Bytes', 0, 'Modified', 0);
            if strlength(string(file)) == 0, return, end
            d = dir(file);
            if isscalar(d) && ~d.isdir
                st = struct('Exists', true, 'Bytes', d.bytes, 'Modified', d.datenum);
            end
        end

        function w = writer_()
            user = string(getenv('USERNAME'));
            if user == "", user = string(getenv('USER')); end
            if user == "", user = "unknown"; end
            host = string(getenv('COMPUTERNAME'));
            if host == "", host = string(getenv('HOSTNAME')); end
            if host == "", host = "unknown"; end
            w = user + "@" + host;
        end

        function T = emptySessions_()
            T = table('Size', [0 6], ...
                'VariableTypes', {'string', 'logical', 'string', 'string', 'string', 'datetime'}, ...
                'VariableNames', {'Key', 'Hidden', 'HiddenReason', 'Window', 'Comment', 'Modified'});
        end

        function T = emptySubjects_()
            T = table('Size', [0 3], 'VariableTypes', {'string', 'string', 'datetime'}, ...
                'VariableNames', {'Subject', 'Comment', 'Modified'});
        end

        function S = emptyPresets_()
            S = struct('Name', {}, 'Settings', {}, 'View', {}, 'Modified', {});
        end

        function S = emptyGroupings_()
            S = struct('Name', {}, 'Levels', {}, 'Subjects', {}, 'Sessions', {}, 'Modified', {});
        end

        function F = defaultFacets_()
            F = struct('GroupBy', "none", 'ColorBy', "subject", 'XAxis', "date", ...
                'Value', "Threshold", 'Kind', "box", 'Modified', NaT);
        end

        function tf = isDefaultRow_(row)
            tf = ~row.Hidden && row.HiddenReason == "" && row.Window == "" && row.Comment == "";
        end

        function col = groupColumn_(name)
            col = "Group_" + string(matlab.lang.makeValidName(char(name)));
        end

        function name = checkName_(name, what)
            name = strtrim(name);
            if name == ""
                error('behavior:Project:InvalidName', 'A %s needs a name.', what);
            end
        end

        function levels = checkLevels_(levels)
            levels = reshape(strtrim(string(levels)), 1, []);
            if any(levels == "") || any(levels == behavior.Facet.NONE)
                error('behavior:Project:InvalidLevels', ...
                    'A level cannot be empty or "%s".', behavior.Facet.NONE);
            end
            if numel(unique(levels)) < numel(levels)
                error('behavior:Project:InvalidLevels', 'Each level must be named once.');
            end
        end

        function v = checkViewField_(field, v)
            % One field of a view, validated and in canonical form.
            v = strtrim(string(v));
            switch field
                case {"GroupBy", "ColorBy", "XAxis"}
                    f = behavior.Facet.fromText(v);
                    if f.Kind == "none" && lower(v) ~= "none"
                        error('behavior:Project:InvalidFacet', '"%s" names no facet (%s).', v, field);
                    end
                    v = f.toText();
                case "Value"
                    if v == ""
                        error('behavior:Project:InvalidView', 'The view needs a Value to show.');
                    end
                case "Kind"
                    v = lower(v);
                    if ~ismember(v, behavior.Project.ViewKinds)
                        error('behavior:Project:InvalidView', '"%s" is not a plot kind (%s).', ...
                            v, strjoin(behavior.Project.ViewKinds, ", "));
                    end
            end
        end

        function [list, changed] = setAssignment_(list, idField, id, level)
            % One subject's or session's level in an assignment list; ""
            % removes it.
            i = find(behavior.Project.normKey_([list.(idField)]) == behavior.Project.normKey_(id), 1);
            changed = true;
            if isempty(i)
                if level == "", changed = false; return, end
                list(end+1) = cell2struct({id; level}, {char(idField); 'Level'}, 1);
            elseif level == ""
                list(i) = [];
            elseif list(i).Level == level
                changed = false;
            else
                list(i).Level = level;
            end
        end

        function b = baseOf_(P)
            % The identity and time of every record: what merge_ tells a
            % removal from an addition by.
            b = struct( ...
                'Sessions', behavior.Project.ids_(P.Sessions.Key, P.Sessions.Modified), ...
                'Subjects', behavior.Project.ids_(P.Subjects.Subject, P.Subjects.Modified), ...
                'Presets', behavior.Project.recordIds_(P.Presets), ...
                'Groupings', behavior.Project.recordIds_(P.Groupings));
        end

        function b = ids_(keys, modified)
            b = struct('Keys', reshape(behavior.Project.normKey_(keys), [], 1), ...
                'Modified', reshape(modified, [], 1));
        end

        function b = recordIds_(S)
            if isempty(S)
                b = struct('Keys', strings(0,1), 'Modified', NaT(0,1));
            else
                b = struct('Keys', reshape([S.Name], [], 1), 'Modified', reshape([S.Modified], [], 1));
            end
        end
    end

    methods (Access = private)
        merge_(P, D)
        ok = atomicWrite_(P, txt)

        function editSession_(P, key, varargin)
            % Change fields of one session row; a row back at the defaults
            % is removed, and a change that changes nothing is no edit.
            i = find(behavior.Project.normKey_(P.Sessions.Key) == behavior.Project.normKey_(key), 1);
            if isempty(i)
                row = table(key, false, "", "", "", NaT, 'VariableNames', P.Sessions.Properties.VariableNames);
            else
                row = P.Sessions(i, :);
            end
            new = row;
            for k = 1:2:numel(varargin)
                new.(varargin{k}) = varargin{k+1};
            end
            if new.Hidden == row.Hidden && new.HiddenReason == row.HiddenReason ...
                    && new.Window == row.Window && new.Comment == row.Comment
                return
            end
            if behavior.Project.isDefaultRow_(new)
                P.Sessions(i, :) = [];
            else
                new.Modified = behavior.Project.now_();
                if isempty(i)
                    P.Sessions = [P.Sessions; new];
                else
                    P.Sessions(i, :) = new;
                end
            end
            P.Dirty = true;
        end

        function v = sessionField_(P, keys, field)
            [in, loc] = ismember(behavior.Project.normKey_(keys), behavior.Project.normKey_(P.Sessions.Key));
            v = repmat("", size(keys));
            v(in) = P.Sessions.(field)(loc(in));
        end

        function i = presetIndex_(P, name)
            i = find(string([P.Presets.Name]) == strtrim(name), 1);
            if isempty(i)
                error('behavior:Project:NoPreset', 'There is no preset "%s".', name);
            end
        end

        function g = groupingIndex_(P, name)
            g = find(string([P.Groupings.Name]) == strtrim(name), 1);
            if isempty(g)
                error('behavior:Project:NoGrouping', 'There is no grouping "%s".', name);
            end
        end

        function V = completeView_(P, V)
            % A preset's view: no fields = none; otherwise every field,
            % those not given taken from the current Facets.
            if isempty(fieldnames(V))
                V = struct();
                return
            end
            given = string(fieldnames(V));
            names = ["GroupBy" "ColorBy" "XAxis" "Value" "Kind"];
            bad = setdiff(given, names);
            if ~isempty(bad)
                error('behavior:Project:InvalidView', 'A view has no field "%s".', bad(1));
            end
            out = rmfield(P.Facets, 'Modified');
            for f = reshape(given, 1, [])
                out.(f) = behavior.Project.checkViewField_(f, V.(f));
            end
            V = out;
        end
    end
end
