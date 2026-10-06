classdef ParameterDefaultsEditor < handle
    % gui.ParameterDefaultsEditor
    % E = gui.ParameterDefaultsEditor.open(roster, subjectId, projectId)
    % E = gui.ParameterDefaultsEditor.open(..., RunExpt = X, Visible = false)
    % Edit the parameter values one subject runs with in one project.
    %
    % Opened from the Subjects & Projects window: right-click a subject,
    % Parameter Defaults for This Row..., or Subject > Parameter Defaults....
    % Lists every parameter of the subject's protocol that a default can mean
    % something on, beside the protocol's own value and range. A value typed in
    % the Default column (or a bound in Min/Max) replaces the protocol's for
    % this subject every time Run or Preview is pressed; a blank cell leaves the
    % protocol alone. Nothing is written until Save.
    %
    % Values can also be taken from where the subject has been:
    %   Copy from Session         - what the running (or just stopped) session
    %                               holds now, values and bounds
    %   Copy from Last Data File  - the last trial of the subject's most
    %                               recent saved session, values only
    % Either copies only what DIFFERS from the protocol, so a copy never turns
    % every parameter into a default, and never clears one the operator set.
    %
    % All of the arithmetic -- which parameters qualify, parsing, range and
    % pairing checks, reading a session or a file -- is epsych.ParameterDefaults;
    % this class holds the rows being edited and lays them out. The editing
    % methods are public so a script (or a test) can do what the table does.
    %
    % One window per membership: open() raises the one already open rather
    % than building a second that could overwrite its edits.
    %
    % Properties (read-only):
    %   Roster, SubjectID, ProjectID, SubjectName, ProjectName, RunExpt
    %   Protocol       - the epsych.Protocol the rows come from, or []
    %   ProtocolFile   - its path ('' when the subject has none)
    %   Rows           - one struct per parameter (see buildRows_)
    %   IsModified     - unsaved edits exist
    %
    % Methods:
    %   setDefault(obj, param, text)        - type into the Default column
    %   setBound(obj, param, 'Min'|'Max', text)
    %   clearDefaults(obj, params)          - blank rows ([] = all)
    %   copyFromSession(obj)                - Copy from Session
    %   copyFromDataFile(obj, file)         - Copy from a data file ('' = latest)
    %   D = collect(obj)                    - the rows as roster records
    %   ok = save(obj)                      - write them to the roster
    %   close(obj)                          - close, asking about unsaved edits
    %
    % Events:
    %   DefaultsSaved - after save() wrote the roster
    %
    % Documentation: documentation/gui/gui_ParameterDefaultsEditor.md
    % See also: epsych.ParameterDefaults, epsych.SubjectRoster.setParameterDefaults,
    %   gui.SubjectManager

    events
        DefaultsSaved
    end

    properties (SetAccess = private)
        Roster = []
        SubjectID (1,:) char = ''
        ProjectID (1,:) char = ''
        SubjectName (1,:) char = ''
        ProjectName (1,:) char = ''
        RunExpt = []
        Protocol = []
        ProtocolFile (1,:) char = ''
        ProtocolText (1,:) char = ''   % what the header says about the protocol
        Rows struct = struct([])
        IsModified (1,1) logical = false
        H (1,1) struct = struct()
    end

    properties (Access = private)
        DisplayIdx_ = []                % Rows index of each table row, in table order
        Refreshing_ (1,1) logical = false
        LiveFilter_ = string.empty      % text being typed in the filter; 0x0 = use its Value
    end

    properties (Constant, Access = private)
        FIGURE_TAG (1,:) char = 'EPsychParameterDefaultsEditor'
        PREF_TAG   (1,:) char = 'epsych2_gui_ParameterDefaultsEditor'
        PREF_GROUP (1,:) char = 'ep_RunExpt_Subjects'
        DEFAULT_POSITION (1,4) double = [180 150 1000 600]

        COL_DEFAULT (1,1) double = 5
        COL_MIN     (1,1) double = 6
        COL_MAX     (1,1) double = 7

        MUTED  (1,3) double = [0.35 0.38 0.42]
        WARN   (1,3) double = [0.70 0.35 0.00]
        SET_BG (1,3) double = [0.87 0.93 1.00]   % a saved default
        NEW_BG (1,3) double = [0.88 0.97 0.86]   % copied or typed, not yet saved
        OFF_BG (1,3) double = [0.93 0.93 0.93]   % a cell that cannot take a value
    end

    % -----------------------------------------------------------------------
    methods (Static)
        function E = open(roster, subjectId, projectId, options)
            % E = gui.ParameterDefaultsEditor.open(roster, subjectId, projectId)
            % E = gui.ParameterDefaultsEditor.open(..., RunExpt = X, Visible = tf)
            % Show the editor for one membership, raising the window already
            % open for it instead of building a second.
            arguments
                roster (1,1) epsych.SubjectRoster
                subjectId (1,:) char
                projectId (1,:) char
                options.RunExpt = []
                options.Visible (1,1) logical = true
            end

            s = roster.findSubject(subjectId);
            p = roster.findProject(projectId);
            if ~isempty(s) && ~isempty(p)
                figs = findall(groot, 'Type', 'figure', 'Tag', gui.ParameterDefaultsEditor.FIGURE_TAG);
                for i = 1:numel(figs)
                    prior = figs(i).UserData;
                    if isa(prior, 'gui.ParameterDefaultsEditor') && isvalid(prior) ...
                            && strcmp(prior.SubjectID, s.SubjectID) ...
                            && strcmp(prior.ProjectID, p.ProjectID) ...
                            && strcmpi(prior.Roster.FilePath, roster.FilePath)
                        if options.Visible
                            figure(figs(i));
                        end
                        E = prior;
                        return
                    end
                end
            end

            E = gui.ParameterDefaultsEditor(roster, subjectId, projectId, ...
                RunExpt = options.RunExpt, Visible = options.Visible);
        end
    end

    % -----------------------------------------------------------------------
    methods

        function self = ParameterDefaultsEditor(roster, subjectId, projectId, options)
            % self = gui.ParameterDefaultsEditor(roster, subjectId, projectId, Name=Value)
            % Prefer gui.ParameterDefaultsEditor.open, which reuses an open window.
            %
            % Parameters:
            %   roster    - epsych.SubjectRoster holding the membership.
            %   subjectId - SubjectID or Name.
            %   projectId - ProjectID or Name.
            %   RunExpt   - session window Copy from Session reads. Default:
            %               the one open.
            %   Visible   - show the window; false is for headless tests.
            arguments
                roster (1,1) epsych.SubjectRoster
                subjectId (1,:) char
                projectId (1,:) char
                options.RunExpt = []
                options.Visible (1,1) logical = true
            end

            s = roster.findSubject(subjectId);
            if isempty(s)
                error('gui:ParameterDefaultsEditor:NoSuchSubject', 'No subject matches "%s".', subjectId);
            end
            p = roster.findProject(projectId);
            if isempty(p)
                error('gui:ParameterDefaultsEditor:NoSuchProject', 'No project matches "%s".', projectId);
            end
            if isempty(roster.findMembership(s.SubjectID, p.ProjectID))
                error('gui:ParameterDefaultsEditor:NoMembership', ...
                    '"%s" is not a member of "%s"; parameter defaults live on the membership.', ...
                    s.Name, p.Name);
            end

            self.Roster = roster;
            self.SubjectID = s.SubjectID;
            self.ProjectID = p.ProjectID;
            self.SubjectName = s.Name;
            self.ProjectName = p.Name;

            rx = options.RunExpt;
            if isempty(rx) || ~isa(rx, 'epsych.RunExpt') || ~isvalid(rx)
                rx = epsych.SelfTest.findActiveRunExpt();
            end
            self.RunExpt = rx;

            self.loadProtocol_();
            self.buildRows_(roster.parameterDefaults(s.SubjectID, p.ProjectID));
            self.buildUI(options.Visible);
            self.repaint_();

            if isempty(self.Protocol)
                self.setStatus_(self.ProtocolText, true);
            else
                self.setStatus_(sprintf(['%d parameter(s) can take a default. Type a value in ' ...
                    'the Default column; leave it blank to use the protocol''s.'], ...
                    nnz(~[self.Rows.Stale])));
            end

            if nargout == 0
                clear self
            end
        end

        function delete(self)
            % Close the window, remembering where it was.
            try
                if isfield(self.H, 'figure') && isgraphics(self.H.figure)
                    gui.BehaviorGUI.saveFigurePosition(self.PREF_TAG, self.H.figure.Position);
                    self.H.figure.UserData = [];
                    self.H.figure.CloseRequestFcn = '';
                    delete(self.H.figure);
                end
            catch ME
                vprintf(2, ME);
            end
        end

        % ---- editing ---------------------------------------------------

        function [ok, message] = setDefault(self, param, text)
            % [ok, message] = setDefault(self, param, text)
            % Set (or with blank text, clear) one row's default value, exactly
            % as typing into the Default column does. Refused -- nothing
            % changes -- when the text is not a value of the parameter's type
            % or falls outside its range.
            %
            % Parameters:
            %   param - row index, or the parameter's Name, Module.Name, or key.
            %   text  - what was typed; a value is accepted too.
            i = self.rowIndex_(param);
            if isempty(i)
                ok = false;
                message = sprintf('No parameter "%s" in this list.', string(param));
                return
            end
            r = self.Rows(i);

            if ~(ischar(text) || isstring(text))
                text = epsych.ParameterDefaults.formatValue(text);
            end

            if isempty(r.Param)
                [ok, message] = self.staleEdit_(i, strlength(strtrim(string(text))) == 0, r.Min, r.Max);
            else
                [value, ok, message] = epsych.ParameterDefaults.parseValue(text, r.Param);
                if ok
                    [ok, message] = self.trySet_(i, value, r.Min, r.Max, 'typed');
                end
            end
            if ok
                self.repaint_();
            end
        end

        function [ok, message] = setBound(self, param, which, text)
            % [ok, message] = setBound(self, param, 'Min'|'Max', text)
            % Set (or with blank text, clear) one row's Min or Max override.
            arguments
                self
                param
                which (1,:) char {mustBeMember(which, {'Min','Max'})}
                text
            end
            i = self.rowIndex_(param);
            if isempty(i)
                ok = false;
                message = sprintf('No parameter "%s" in this list.', string(param));
                return
            end
            r = self.Rows(i);

            if isnumeric(text)
                b = double(text);
                if isempty(b), b = NaN; end
            else
                t = strtrim(char(string(text)));
                if isempty(t)
                    b = NaN;
                else
                    b = str2double(t);
                    if isnan(b) || ~isfinite(b)
                        ok = false;
                        message = sprintf('"%s" is not a number. Leave %s blank to keep the protocol''s.', t, which);
                        return
                    end
                end
            end

            lo = r.Min; hi = r.Max;
            if strcmp(which, 'Min'), lo = b; else, hi = b; end

            if isempty(r.Param)
                [ok, message] = self.staleEdit_(i, isempty(r.Value), lo, hi);
            else
                [ok, message] = self.trySet_(i, r.Value, lo, hi, 'typed');
            end
            if ok
                self.repaint_();
            end
        end

        function clearDefaults(self, params)
            % clearDefaults(self)
            % clearDefaults(self, params)
            % Blank the named rows -- value and bounds -- or every row.
            if nargin < 2 || isempty(params)
                idx = 1:numel(self.Rows);
            elseif isnumeric(params)
                idx = params(params >= 1 & params <= numel(self.Rows));
            else
                if ~iscell(params), params = cellstr(string(params)); end
                idx = cellfun(@(p) self.rowIndex_(p), params, 'UniformOutput', false);
                idx = [idx{:}];
            end
            idx = reshape(unique(idx), 1, []);
            n = 0;
            for i = idx
                if localHasDefault(self.Rows(i))
                    self.Rows(i).Value = [];
                    self.Rows(i).Min = NaN;
                    self.Rows(i).Max = NaN;
                    self.Rows(i).Origin = 'cleared';
                    self.Rows(i).Problem = '';
                    n = n + 1;
                end
            end
            if n > 0
                self.IsModified = true;
            end
            self.repaint_();
            self.setStatus_(sprintf('Cleared %d default(s). Save to keep the change.', n));
        end

        function report = copyFromSession(self)
            % report = copyFromSession(self)
            % Take the values -- and bounds -- that the subject's session holds
            % now wherever they differ from the protocol.
            %
            % Refused until the subject has run in this session: before that
            % the session holds nothing but the protocol itself.
            report = struct('Copied', {{}}, 'Kept', {{}}, 'Failed', {{}}, 'Message', '');

            if isempty(self.Protocol)
                report.Message = self.ProtocolText;
                self.setStatus_(report.Message, true);
                return
            end

            live = ~[self.Rows.Stale];
            idx = find(live);
            [vals, rep] = epsych.ParameterDefaults.readSession(self.RunExpt, ...
                self.SubjectName, self.Rows(idx));
            if ~rep.Found
                report.Message = rep.Message;
                self.setStatus_(report.Message, true);
                return
            end
            if ~rep.HasRun
                report.Message = sprintf(['%s has not run in this session yet, so the session ' ...
                    'holds only the protocol. Run it first, or type the values.'], self.SubjectName);
                self.setStatus_(report.Message, true);
                return
            end

            for k = 1:numel(idx)
                i = idx(k);
                v = vals(k);
                if ~v.Found, continue, end
                r = self.Rows(i);
                e = r.Eligibility;

                value = r.Value;
                lo = r.Min;
                hi = r.Max;
                touched = false;

                if e.CanSetBounds
                    if isfinite(v.Min) && v.Min ~= r.Param.Min && ~isequaln(v.Min, r.Min)
                        lo = v.Min; touched = true;
                    end
                    if isfinite(v.Max) && v.Max ~= r.Param.Max && ~isequaln(v.Max, r.Max)
                        hi = v.Max; touched = true;
                    end
                end

                if e.CanSetValue && isscalar(r.Param.Values)
                    if ~isempty(v.Error)
                        report.Failed{end+1} = sprintf('%s (%s)', r.Label, v.Error);
                    else
                        [cand, usable] = localCandidate(v.Value, r.Param);
                        if usable && ~localSame(cand, r.Param.Values{1})
                            if ~localSame(cand, r.Value)
                                value = cand; touched = true;
                            end
                        elseif usable && localHasValue(r) && ~localSame(cand, r.Value)
                            report.Kept{end+1} = r.Label;
                        end
                    end
                end

                if ~touched, continue, end
                [ok, why] = self.trySet_(i, value, lo, hi, 'session');
                if ok
                    report.Copied{end+1} = r.Label;
                else
                    report.Failed{end+1} = why;
                end
            end

            report.Message = localCopyMessage('the session', report);
            self.repaint_();
            self.setStatus_(report.Message, ~isempty(report.Failed));
        end

        function report = copyFromDataFile(self, file)
            % report = copyFromDataFile(self)
            % report = copyFromDataFile(self, file)
            % Take the values the last trial of a saved session recorded,
            % wherever they differ from the protocol. With no file (or ''),
            % the subject's most recent saved session.
            %
            % Refused while a session runs: finding the latest file reads the
            % subject's folders on the thread the trial loop runs on.
            arguments
                self
                file (1,:) char = ''
            end
            report = struct('Copied', {{}}, 'Kept', {{}}, 'Failed', {{}}, 'Message', '', 'File', '');

            if isempty(self.Protocol)
                report.Message = self.ProtocolText;
                self.setStatus_(report.Message, true);
                return
            end
            if isempty(file) && gui.SessionBrowser.sessionIsRunning(self.RunExpt)
                report.Message = ['A session is running. The latest data file can be ' ...
                    'found once it has stopped.'];
                self.setStatus_(report.Message, true);
                return
            end

            if isempty(file)
                [f, ~, msg] = epsych.ParameterDefaults.latestDataFile(self.SubjectName, ...
                    Roster = self.Roster, RunExpt = self.RunExpt);
                if strlength(f) == 0
                    report.Message = msg;
                    self.setStatus_(report.Message, true);
                    return
                end
                file = char(f);
            end
            report.File = file;

            live = ~[self.Rows.Stale];
            idx = find(live);
            [vals, rep] = epsych.ParameterDefaults.readDataFile(file, self.Rows(idx));
            if ~isempty(rep.Message)
                report.Message = rep.Message;
                self.setStatus_(report.Message, true);
                return
            end

            for k = 1:numel(idx)
                i = idx(k);
                v = vals(k);
                if ~v.Found, continue, end
                r = self.Rows(i);
                if ~(r.Eligibility.CanSetValue && isscalar(r.Param.Values)), continue, end

                [cand, usable] = localCandidate(v.Value, r.Param);
                if ~usable, continue, end
                if localSame(cand, r.Param.Values{1})
                    if localHasValue(r) && ~localSame(cand, r.Value)
                        report.Kept{end+1} = r.Label;
                    end
                    continue
                end
                if localSame(cand, r.Value), continue, end

                [ok, why] = self.trySet_(i, cand, r.Min, r.Max, 'data file');
                if ok
                    report.Copied{end+1} = r.Label;
                else
                    report.Failed{end+1} = why;
                end
            end

            [~, fn, fe] = fileparts(file);
            report.Message = localCopyMessage(sprintf('%s%s (trial %d)', fn, fe, rep.NumTrials), report);
            self.repaint_();
            self.setStatus_(report.Message, ~isempty(report.Failed));
        end

        function D = collect(self)
            % D = collect(self)
            % Every row that sets something, as the records the roster stores.
            % A row matched to a renamed module is written under the name the
            % protocol uses NOW, so saving migrates it.
            D = epsych.ParameterDefaults.empty();
            for i = 1:numel(self.Rows)
                r = self.Rows(i);
                if ~localHasDefault(r), continue, end
                d = epsych.ParameterDefaults.blank();
                d.Interface = r.Interface;
                d.Module = r.Module;
                d.Name = r.Name;
                d.Value = r.Value;
                d.Min = r.Min;
                d.Max = r.Max;
                D(end+1) = d;
            end
        end

        function ok = save(self)
            % ok = save(self)
            % Write the rows to the roster, replacing the membership's defaults.
            ok = false;
            D = self.collect();
            [valid, msg] = epsych.ParameterDefaults.validate(D);
            if ~valid
                self.alert_(msg, 'Parameter Defaults', 'warning');
                return
            end

            try
                self.Roster.setParameterDefaults(self.SubjectID, self.ProjectID, D);
            catch ME
                vprintf(0, 1, ME);
                self.alert_(ME.message, 'Parameter Defaults', 'error');
                return
            end

            for i = 1:numel(self.Rows)
                self.Rows(i).Origin = '';
            end
            self.IsModified = false;
            ok = true;
            self.repaint_();

            msg = sprintf('Saved %d default(s) for %s. They apply the next time Run or Preview is pressed.', ...
                numel(D), self.SubjectName);
            if gui.SessionBrowser.sessionIsRunning(self.RunExpt)
                msg = [msg ' The session running now is not changed.'];
            end
            self.setStatus_(msg);
            notify(self, 'DefaultsSaved');
        end

        function close(self)
            % close(self)
            % Close the window, asking first when there are unsaved edits and
            % the window is on screen.
            if ~self.IsModified || ~isfield(self.H, 'figure') || ~isgraphics(self.H.figure) ...
                    || ~strcmp(self.H.figure.Visible, 'on')
                delete(self);
                return
            end
            uiconfirm(self.H.figure, sprintf('Save the changes to %s''s parameter defaults?', ...
                self.SubjectName), 'Parameter Defaults', ...
                'Options', {'Save', 'Discard', 'Cancel'}, 'DefaultOption', 1, ...
                'CancelOption', 3, 'CloseFcn', @(~, evt) self.onCloseAnswer_(evt.SelectedOption));
        end
    end

    % -----------------------------------------------------------------------
    methods (Access = private)
        buildUI(self, visible)

        function loadProtocol_(self)
            % The protocol the rows come from: the membership's, loaded the way
            % assignToSession would load it -- including out of the version
            % archive when the membership is held on an older version.
            self.Protocol = [];
            pfn = self.Roster.lastProtocol(self.SubjectID, self.ProjectID);
            self.ProtocolFile = pfn;

            if isempty(pfn)
                self.ProtocolText = ['No protocol is remembered for this subject and the ' ...
                    'project has no default, so there are no parameters to list. Set a ' ...
                    'protocol for it first.'];
                return
            end
            [~, fn, fe] = fileparts(pfn);
            if ~isfile(pfn)
                self.ProtocolText = sprintf('The protocol file is missing: %s', pfn);
                return
            end

            m = self.Roster.findMembership(self.SubjectID, self.ProjectID);
            held = '';
            if ~isempty(m) && m.ProtocolPinned && ~isempty(m.LastProtocolVersion) ...
                    && strcmpi(strrep(m.LastProtocol, '/', filesep), strrep(pfn, '/', filesep)) ...
                    && ~strcmp(epsych.Protocol.versionOnDisk(pfn), m.LastProtocolVersion) ...
                    && epsych.Protocol.hasVersion(pfn, m.LastProtocolVersion)
                held = m.LastProtocolVersion;
            end

            ws = warning('off', 'MATLAB:dispatcher:UnresolvedFunctionHandle');
            restore = onCleanup(@() warning(ws));
            try
                if isempty(held)
                    self.Protocol = epsych.Protocol.load(pfn);
                    self.ProtocolText = sprintf('Protocol: %s%s (%s)', fn, fe, ...
                        char(self.Protocol.meta.protocolVersion));
                else
                    self.Protocol = epsych.Protocol.loadVersion(pfn, held);
                    self.ProtocolText = sprintf('Protocol: %s%s, held on %s', fn, fe, held);
                end
            catch ME
                vprintf(0, 1, ME);
                self.Protocol = [];
                self.ProtocolText = sprintf('The protocol could not be loaded: %s', ME.message);
            end
        end

        function buildRows_(self, D)
            % One row per parameter that can take a default, then one per
            % stored default the protocol does not have.
            rows = repmat(localBlankRow(), 1, 0);
            if ~isempty(self.Protocol)
                T = epsych.ParameterDefaults.parameters(self.Protocol);
                for k = 1:numel(T)
                    r = localBlankRow();
                    r.Key = T(k).Key;
                    r.Label = T(k).Label;
                    r.Interface = T(k).Interface;
                    r.Module = T(k).Module;
                    r.Name = T(k).Name;
                    r.Param = T(k).Param;
                    r.Eligibility = T(k).Eligibility;
                    r.Unit = T(k).Param.Unit;
                    r.Hidden = ~T(k).Param.Visible;
                    r.ProtocolText = localProtocolText(T(k).Param);
                    r.RangeText = localRangeText(T(k).Param.Min, T(k).Param.Max);
                    rows(end+1) = r;
                end
            end

            for k = 1:numel(D)
                d = D(k);
                i = find(strcmp({rows.Key}, epsych.ParameterDefaults.key(d)), 1);
                if isempty(i) && ~isempty(self.Protocol)
                    P = epsych.ParameterDefaults.resolve(self.Protocol, d);
                    if ~isempty(P)
                        i = find(arrayfun(@(r) ~isempty(r.Param) && r.Param == P, rows), 1);
                    end
                end

                if isempty(i) || localHasDefault(rows(i))
                    r = localBlankRow();
                    r.Key = epsych.ParameterDefaults.key(d);
                    r.Label = epsych.ParameterDefaults.label(d);
                    r.Interface = d.Interface;
                    r.Module = d.Module;
                    r.Name = d.Name;
                    r.Stale = true;
                    r.Eligibility = struct('CanSetValue', false, 'CanSetBounds', false, ...
                        'Reason', 'not in this protocol');
                    r.Value = d.Value;
                    r.Min = d.Min;
                    r.Max = d.Max;
                    if isempty(self.Protocol)
                        r.Problem = 'no protocol to check against';
                    elseif ~isempty(i)
                        r.Problem = 'a second default for the same parameter';
                    else
                        r.Problem = 'not in this protocol; skipped at Run';
                    end
                    rows(end+1) = r;
                    continue
                end

                rows(i).Value = d.Value;
                rows(i).Min = d.Min;
                rows(i).Max = d.Max;
                [ok, why] = epsych.ParameterDefaults.check(d, rows(i).Param);
                if ~ok
                    rows(i).Problem = [why ' Skipped at Run until fixed.'];
                end
            end

            self.Rows = rows;
        end

        function [ok, message] = trySet_(self, i, value, lo, hi, origin)
            % Accept a candidate value and bounds for row i if epsych.
            % ParameterDefaults.check agrees, recording where it came from.
            r = self.Rows(i);
            d = epsych.ParameterDefaults.blank();
            d.Interface = r.Interface;
            d.Module = r.Module;
            d.Name = r.Name;
            d.Value = value;
            d.Min = lo;
            d.Max = hi;

            [ok, message] = epsych.ParameterDefaults.check(d, r.Param);
            if ~ok, return, end

            changed = ~localSame(value, r.Value) || ~isequaln(lo, r.Min) || ~isequaln(hi, r.Max);
            self.Rows(i).Value = value;
            self.Rows(i).Min = lo;
            self.Rows(i).Max = hi;
            self.Rows(i).Problem = '';
            if changed
                self.Rows(i).Origin = origin;
                self.IsModified = true;
            end
            message = '';
        end

        function [ok, message] = staleEdit_(self, i, valueCleared, lo, hi)
            % A default the protocol does not have can only be cleared: there
            % is nothing to check a new value against.
            if valueCleared && isnan(lo) && isnan(hi)
                self.Rows(i).Value = [];
                self.Rows(i).Min = NaN;
                self.Rows(i).Max = NaN;
                self.Rows(i).Origin = 'cleared';
                self.IsModified = true;
                ok = true;
                message = '';
                return
            end
            ok = false;
            message = sprintf(['%s is not in this protocol, so its default can only be ' ...
                'cleared. It is kept -- and skipped at Run -- until then.'], self.Rows(i).Label);
        end

        function i = rowIndex_(self, param)
            % A row by index, key, Module.Name, or Name (when unambiguous).
            i = [];
            if isnumeric(param)
                if isscalar(param) && param >= 1 && param <= numel(self.Rows)
                    i = param;
                end
                return
            end
            p = char(string(param));
            i = find(strcmp({self.Rows.Key}, p), 1);
            if isempty(i), i = find(strcmp({self.Rows.Label}, p), 1); end
            if isempty(i)
                hits = find(strcmp({self.Rows.Name}, p));
                if isscalar(hits), i = hits; end
            end
        end

        % ---- display ---------------------------------------------------

        function repaint_(self)
            % Refill the table from Rows through the filter, and restyle it.
            if ~isfield(self.H, 'table') || ~isgraphics(self.H.table), return, end
            self.Refreshing_ = true;
            cleanup = onCleanup(@() self.endRefresh_());

            if isempty(self.LiveFilter_)
                filt = lower(strtrim(self.H.filter.Value));
            else
                filt = lower(strtrim(char(self.LiveFilter_)));
            end
            onlySet = self.H.chkOnlySet.Value;
            showHidden = self.H.chkHidden.Value;

            keep = false(1, numel(self.Rows));
            for i = 1:numel(self.Rows)
                r = self.Rows(i);
                has = localHasDefault(r);
                keep(i) = (showHidden || ~r.Hidden || has || r.Stale) ...
                    && (~onlySet || has || r.Stale) ...
                    && (isempty(filt) || contains(lower(r.Label), filt));
            end
            idx = find(keep);
            self.DisplayIdx_ = idx;

            data = cell(numel(idx), 8);
            for k = 1:numel(idx)
                r = self.Rows(idx(k));
                data{k,1} = r.Label;
                data{k,2} = r.Unit;
                data{k,3} = r.ProtocolText;
                data{k,4} = r.RangeText;
                data{k,5} = epsych.ParameterDefaults.formatValue(r.Value);
                data{k,6} = localBoundText(r.Min);
                data{k,7} = localBoundText(r.Max);
                data{k,8} = localNote(r);
            end
            self.H.table.Data = data;

            removeStyle(self.H.table);
            cols = [self.COL_DEFAULT self.COL_MIN self.COL_MAX];
            for k = 1:numel(idx)
                r = self.Rows(idx(k));
                if r.Stale || ~isempty(r.Problem)
                    addStyle(self.H.table, uistyle('FontColor', self.WARN), 'row', k);
                end
                if ~r.Eligibility.CanSetValue
                    addStyle(self.H.table, uistyle('BackgroundColor', self.OFF_BG), ...
                        'cell', [k self.COL_DEFAULT]);
                end
                if ~r.Eligibility.CanSetBounds
                    addStyle(self.H.table, uistyle('BackgroundColor', self.OFF_BG), ...
                        'cell', [k self.COL_MIN; k self.COL_MAX]);
                end
                if localHasDefault(r)
                    if any(strcmp(r.Origin, {'typed','session','data file'}))
                        bg = self.NEW_BG;
                    else
                        bg = self.SET_BG;
                    end
                    on = cols([~isempty(r.Value), ~isnan(r.Min), ~isnan(r.Max)]);
                    addStyle(self.H.table, uistyle('BackgroundColor', bg, 'FontWeight', 'bold'), ...
                        'cell', [repmat(k, numel(on), 1), on(:)]);
                end
            end

            nSet = nnz(arrayfun(@localHasDefault, self.Rows));
            self.H.count.Text = sprintf('%d shown  ·  %d with defaults', numel(idx), nSet);

            mark = '';
            if self.IsModified, mark = ' *'; end
            self.H.figure.Name = sprintf('Parameter Defaults — %s in %s%s', ...
                self.SubjectName, self.ProjectName, mark);
            self.H.btnSave.Enable = matlab.lang.OnOffSwitchState(self.IsModified);
            hasProtocol = ~isempty(self.Protocol);
            self.H.btnCopySession.Enable = matlab.lang.OnOffSwitchState(hasProtocol);
            self.H.btnCopyFile.Enable = matlab.lang.OnOffSwitchState(hasProtocol);
            self.H.btnClearAll.Enable = matlab.lang.OnOffSwitchState(nSet > 0);
        end

        function endRefresh_(self)
            if isvalid(self), self.Refreshing_ = false; end
        end

        function setStatus_(self, message, warn)
            if nargin < 3, warn = false; end
            if ~isfield(self.H, 'status') || ~isgraphics(self.H.status), return, end
            self.H.status.Text = message;
            if warn
                self.H.status.FontColor = self.WARN;
            else
                self.H.status.FontColor = self.MUTED;
            end
        end

        function alert_(self, message, title, icon)
            % uialert refuses a hidden figure, and save() is public -- a script
            % driving a window it never showed gets the reason in the log.
            self.setStatus_(strtok(message, newline), true);
            if isfield(self.H, 'figure') && isgraphics(self.H.figure) ...
                    && strcmp(self.H.figure.Visible, 'on')
                uialert(self.H.figure, message, title, 'Icon', icon);
            else
                vprintf(1, 'gui.ParameterDefaultsEditor: %s: %s', title, message)
            end
        end

        % ---- callbacks -------------------------------------------------

        function onFilterChanging_(self, value)
            % Keystrokes go to LiveFilter_, never back into the field: setting
            % Value from inside ValueChangingFcn re-renders the field mid-edit
            % and drops characters (see gui.SubjectManager).
            self.LiveFilter_ = string(value);
            self.repaint_();
        end

        function onFilterChanged_(self)
            % The edit was committed; the field's own Value is the filter again.
            self.LiveFilter_ = string.empty;
            self.repaint_();
        end

        function onCellEdit_(self, evt)
            if self.Refreshing_, return, end
            k = evt.Indices(1);
            c = evt.Indices(2);
            if k > numel(self.DisplayIdx_), return, end
            i = self.DisplayIdx_(k);

            switch c
                case self.COL_DEFAULT
                    [ok, msg] = self.setDefault(i, evt.NewData);
                case self.COL_MIN
                    [ok, msg] = self.setBound(i, 'Min', evt.NewData);
                case self.COL_MAX
                    [ok, msg] = self.setBound(i, 'Max', evt.NewData);
                otherwise
                    ok = true; msg = '';
            end

            % An accepted edit has already repainted; a refused one is put back
            % by redrawing from Rows, which it left alone.
            if ~ok
                self.repaint_();
            end
            if ok
                self.setStatus_('Edited. Save to keep the change.');
            else
                self.setStatus_(msg, true);
            end
        end

        function onClearSelected_(self)
            sel = self.H.table.Selection;
            if isempty(sel)
                self.setStatus_('Select the rows to reset first.', true);
                return
            end
            % Row selection: a vector of row indices, whichever way it is shaped.
            sel = unique(sel(:))';
            sel = sel(sel <= numel(self.DisplayIdx_));
            if isempty(sel), return, end
            self.clearDefaults(self.DisplayIdx_(sel));
        end

        function onClearAll_(self)
            n = nnz(arrayfun(@localHasDefault, self.Rows));
            if n == 0, return, end
            uiconfirm(self.H.figure, sprintf(['Reset all %d of %s''s parameters to the protocol''s values? ' ...
                'Nothing is written until Save.'], n, self.SubjectName), 'Reset All to Protocol', ...
                'Options', {'Reset All', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, ...
                'Icon', 'warning', ...
                'CloseFcn', @(~, evt) localIf(strcmp(evt.SelectedOption, 'Reset All'), ...
                    @() self.clearDefaults()));
        end

        function onCopyDataFile_(self)
            % Name the file before copying from it: the newest session is not
            % always the right one for a subject in two projects.
            if gui.SessionBrowser.sessionIsRunning(self.RunExpt)
                self.alert_(['A session is running. The latest data file can be found ' ...
                    'once it has stopped.'], 'Copy from Last Data File', 'info');
                return
            end

            dlg = uiprogressdlg(self.H.figure, 'Title', 'Copy from Last Data File', ...
                'Message', sprintf('Looking for %s''s sessions...', self.SubjectName), ...
                'Indeterminate', 'on');
            closeDialog = onCleanup(@() delete(dlg));
            [file, row, msg] = epsych.ParameterDefaults.latestDataFile(self.SubjectName, ...
                Roster = self.Roster, RunExpt = self.RunExpt);
            clear closeDialog

            if strlength(file) == 0
                uiconfirm(self.H.figure, sprintf('%s\n\nChoose a data file yourself?', msg), ...
                    'Copy from Last Data File', 'Options', {'Choose File...', 'Cancel'}, ...
                    'DefaultOption', 1, 'CancelOption', 2, 'Icon', 'info', ...
                    'CloseFcn', @(~, evt) self.onDataFileAnswer_(evt.SelectedOption, ''));
                return
            end

            when = '';
            if ~isnat(row.StartTime)
                when = char(row.StartTime, 'dd-MMM-yyyy HH:mm');
            end
            [~, fn, fe] = fileparts(file);
            uiconfirm(self.H.figure, sprintf(['Copy the last trial''s values from\n\n%s%s\n' ...
                '%s, %d trial(s)\n\nOnly values that differ from the protocol are copied.'], ...
                fn, fe, when, row.Trials), 'Copy from Last Data File', ...
                'Options', {'Copy', 'Choose Another File...', 'Cancel'}, ...
                'DefaultOption', 1, 'CancelOption', 3, ...
                'CloseFcn', @(~, evt) self.onDataFileAnswer_(evt.SelectedOption, char(file)));
        end

        function onDataFileAnswer_(self, answer, file)
            switch answer
                case 'Copy'
                    self.copyFromDataFile(file);
                case {'Choose File...', 'Choose Another File...'}
                    start = pwd;
                    if ~isempty(file), start = fileparts(file); end
                    [fn, pn] = uigetfile({'*.mat', 'Session Data (*.mat)'}, ...
                        'Copy Parameter Values from a Data File', start);
                    figure(self.H.figure);
                    if isequal(fn, 0), return, end
                    self.copyFromDataFile(fullfile(pn, fn));
            end
        end

        function onCloseAnswer_(self, answer)
            switch answer
                case 'Save'
                    if self.save()
                        delete(self);
                    end
                case 'Discard'
                    delete(self);
            end
        end

        function onKey_(self, evt)
            ctrl = any(strcmp(evt.Modifier, 'control'));
            switch evt.Key
                case 'escape'
                    self.close();
                case 's'
                    if ctrl && self.IsModified, self.save(); end
                case 'f'
                    if ctrl, focus(self.H.filter); end
            end
        end
    end
end

% =======================================================================
function r = localBlankRow()
% A row with every field at its "nothing set" value.
r = struct('Key', '', 'Label', '', 'Interface', '', 'Module', '', 'Name', '', ...
    'Param', [], ...
    'Eligibility', struct('CanSetValue', false, 'CanSetBounds', false, 'Reason', ''), ...
    'Unit', '', 'Hidden', false, 'ProtocolText', '', 'RangeText', '', ...
    'Value', [], 'Min', NaN, 'Max', NaN, ...
    'Stale', false, 'Origin', '', 'Problem', '');
end

% -----------------------------------------------------------------------
function tf = localHasDefault(r)
tf = ~isempty(r.Value) || ~isnan(r.Min) || ~isnan(r.Max);
end

% -----------------------------------------------------------------------
function tf = localHasValue(r)
tf = ~isempty(r.Value);
end

% -----------------------------------------------------------------------
function txt = localProtocolText(P)
% What the protocol gives this parameter, the way the Default column would show
% it. A randomized parameter's value is its draw range, so say that instead.
if P.isRandom
    txt = sprintf('random %g – %g', P.Min, P.Max);
else
    txt = epsych.ParameterDefaults.formatLevels(P);
end
end

% -----------------------------------------------------------------------
function txt = localRangeText(lo, hi)
if ~isfinite(lo) && ~isfinite(hi)
    txt = '';
else
    txt = sprintf('%g – %g', lo, hi);
end
end

% -----------------------------------------------------------------------
function txt = localBoundText(b)
if isnan(b)
    txt = '';
else
    txt = sprintf('%g', b);
end
end

% -----------------------------------------------------------------------
function txt = localNote(r)
% The row's qualifiers, most important first.
bits = {};
if ~isempty(r.Problem)
    bits{end+1} = r.Problem;
elseif r.Stale
    bits{end+1} = 'not in this protocol';
end
if ~isempty(r.Eligibility.Reason) && ~r.Stale
    bits{end+1} = r.Eligibility.Reason;
end
if ~isempty(r.Param)
    n = numel(r.Param.Values);
    if n > 1
        bits{end+1} = sprintf('roved ×%d', n);
    end
    u = r.Param.UserData;
    if isstruct(u) && isscalar(u) && isfield(u, 'Pair') && ~isempty(u.Pair)
        bits{end+1} = sprintf('paired: %s', char(string(u.Pair)));
    end
end
if r.Hidden
    bits{end+1} = 'hidden';
end
switch r.Origin
    case 'session',   bits{end+1} = 'from session';
    case 'data file', bits{end+1} = 'from data file';
end
txt = strjoin(bits, '; ');
end

% -----------------------------------------------------------------------
function [v, usable] = localCandidate(v, P)
% A value read from a session or a data file, made into what the Default column
% would hold. Hardware reads come back through single precision (0.1 reads as
% 0.100000001490116), so numbers are rounded to 7 significant digits: the value
% the operator meant, not the float the DSP stored.
usable = false;
if isempty(v), return, end
switch P.Type
    case {'Float','Integer'}
        if ~(isnumeric(v) || islogical(v)) || ~isscalar(v) || ~isfinite(double(v)), return, end
        v = str2double(sprintf('%.7g', double(v)));
        if strcmp(P.Type, 'Integer'), v = round(v); end
    case 'Boolean'
        if ~(isnumeric(v) || islogical(v)) || ~isscalar(v) || ~any(double(v) == [0 1]), return, end
        v = logical(v);
    otherwise
        if isstring(v) && isscalar(v), v = char(v); end
        if ~ischar(v), return, end
end
usable = true;
end

% -----------------------------------------------------------------------
function tf = localSame(a, b)
% Equal as a default would be: numbers to 7 significant digits (see
% localCandidate), text exactly, and two empties always.
if isempty(a) && isempty(b)
    tf = true;
elseif (isnumeric(a) || islogical(a)) && (isnumeric(b) || islogical(b))
    a = double(a); b = double(b);
    tf = isequal(size(a), size(b)) && all(abs(a(:) - b(:)) <= 1e-7 * max(1, abs(b(:))));
else
    tf = isequal(a, b);
end
end

% -----------------------------------------------------------------------
function msg = localCopyMessage(source, report)
n = numel(report.Copied);
if n == 0
    msg = sprintf('Nothing in %s differs from the protocol or the defaults already set.', source);
else
    msg = sprintf('Copied %d default(s) from %s: %s. Save to keep them.', n, source, ...
        strjoin(report.Copied, ', '));
end
if ~isempty(report.Kept)
    msg = sprintf(['%s %s match the protocol there, so their defaults were left alone ' ...
        '(clear them to use the protocol''s).'], msg, strjoin(report.Kept, ', '));
end
if ~isempty(report.Failed)
    msg = sprintf('%s Not copied: %s.', msg, strjoin(report.Failed, '; '));
end
end

% -----------------------------------------------------------------------
function localIf(tf, fcn)
if tf, fcn(); end
end
