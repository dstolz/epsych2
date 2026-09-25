classdef SessionBrowser < handle
    % gui.SessionBrowser
    % obj = gui.SessionBrowser(subjectName)
    % obj = gui.SessionBrowser(subjectName, Roster = R, RunExpt = X)
    % One subject's saved sessions in a sortable table, and a button that
    % reopens the selected one in its behavior GUI.
    %
    % Opened from the Subjects & Projects window: right-click a subject, View
    % Data Files.... The files are found and described by epsych.SessionFiles;
    % this class only lays them out and hands the chosen one to
    % epsych.ReviewSession -- the same door RunExpt's Review Saved Session...
    % opens, so a session reviewed from here looks exactly as it does there.
    %
    % Only between sessions. Describing a subject's files loads each of them on
    % the MATLAB thread, which is the thread the trial loop's timer runs on, so
    % a scan during a session holds up trial dispatch for as long as it takes.
    % The constructor refuses while epsych.RunExpt is RUNNING or finishing, and
    % an open window follows RunExpt.STATE: its Review and Rescan controls grey
    % out when a session starts and come back when it stops. (RunExpt's own
    % Review Saved Session... does stay available during a run -- one file,
    % chosen on purpose, rather than a folder read end to end.)
    %
    % Properties:
    %   SubjectName - whose sessions these are
    %   Locations   - where they were looked for (epsych.SessionFiles.locations)
    %   Sessions    - table from epsych.SessionFiles.scan, in DATA order: every
    %                 row index this class takes or reports is into this table,
    %                 never into the sorted view the operator sees
    %   RunExpt     - the session window being followed, or []
    %   H           - graphics handles
    %
    % Methods:
    %   rescan(obj)      - look again; only files that changed are re-read
    %   review(obj, row) - open Sessions(row,:) for review (default: selection)
    %
    % Example:
    %   gui.SessionBrowser("M001")
    %
    % Documentation: documentation/gui/gui_SessionBrowser.md
    % See also: epsych.SessionFiles, epsych.ReviewSession, gui.SubjectManager

    properties (SetAccess = private)
        SubjectName (1,1) string = ""
        Locations (1,1) struct = struct('Names', string.empty(1,0), ...
            'Roots', string.empty(1,0), 'VideoRoots', string.empty(1,0), 'RecoveryDir', "")
        Sessions table = table()
        RunExpt = []
        H (1,1) struct = struct()
    end

    properties (Access = private)
        Report_ (1,1) struct = struct('Folders', string.empty(1,0), ...
            'Missing', string.empty(1,0), 'NumFiles', 0, 'NumSkipped', 0, 'Cancelled', false)
        StateListener_ = []            % PostSet listener on RunExpt.STATE
        Running_ (1,1) logical = false % session state the controls last showed
    end

    properties (Constant, Access = private)
        FIGURE_TAG (1,:) char = 'EPsychSessionBrowser'
        PREF_TAG   (1,:) char = 'epsych2_gui_SessionBrowser'
        PREF_GROUP (1,:) char = 'ep_RunExpt_Subjects'
        DEFAULT_POSITION (1,4) double = [160 140 1080 640]

        MUTED (1,3) double = [0.35 0.38 0.42]
        GREYED (1,3) double = [0.58 0.60 0.64]
    end

    % -----------------------------------------------------------------------
    methods

        function self = SessionBrowser(subjectName, options)
            % self = gui.SessionBrowser(subjectName, Name=Value)
            % Open the browser for one subject, replacing a window already open
            % for the same one.
            %
            % Parameters:
            %   subjectName - The subject's Name, as the roster has it.
            %   Roster      - epsych.SubjectRoster for project and membership
            %                 data paths and former names. [] looks only in the
            %                 rig's own data path.
            %   RunExpt     - Session window to follow. Default: the one open.
            %   Visible     - Show the window. False is for headless tests.
            arguments
                subjectName (1,1) string {mustBeNonzeroLengthText}
                options.Roster = []
                options.RunExpt = []
                options.Visible (1,1) logical = true
            end

            rx = options.RunExpt;
            if ~localIsRunExpt(rx)
                rx = epsych.SelfTest.findActiveRunExpt();
            end

            if gui.SessionBrowser.sessionIsRunning(rx)
                error('gui:SessionBrowser:SessionRunning', ...
                    ['A session is running. A subject''s data files can be ' ...
                     'browsed once it has stopped.']);
            end

            gui.SessionBrowser.closeFor_(subjectName);

            self.SubjectName = subjectName;
            self.RunExpt = rx;
            self.Locations = epsych.SessionFiles.locations(subjectName, ...
                Roster = options.Roster, RunExpt = rx);

            self.buildUI(options.Visible);
            self.followSession_();
            self.rescan();

            if nargout == 0
                clear self
            end
        end

        function delete(self)
            % delete(self)
            % Stop following the session and close the window, saving its
            % position.
            try
                if ~isempty(self.StateListener_) && isvalid(self.StateListener_)
                    delete(self.StateListener_);
                end
            catch ME
                vprintf(2, ME);
            end

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

        function rescan(self)
            % rescan(self)
            % Look for the subject's files again and redraw the table, keeping
            % the selected file selected when it is still there. Cheap after the
            % first time: epsych.SessionFiles re-reads only files whose size or
            % modification time changed.
            if self.refuseWhileRunning_('Rescanning')
                return
            end

            previous = self.selectedFile_();

            dlg = [];
            if strcmp(self.H.figure.Visible, 'on')
                dlg = uiprogressdlg(self.H.figure, 'Title', 'Data Files', ...
                    'Message', sprintf('Looking for the sessions of %s...', self.SubjectName), ...
                    'Cancelable', 'on');
            end
            closeDialog = onCleanup(@() localCloseDialog(dlg));

            L = self.Locations;
            [T, report] = epsych.SessionFiles.scan(L.Names, ...
                Roots = L.Roots, VideoRoots = L.VideoRoots, ...
                IncludeRecovery = self.H.chkRecovery.Value, ...
                RecoveryDir = L.RecoveryDir, ...
                Progress = @(k, n) localProgress(dlg, k, n));
            clear closeDialog

            self.Sessions = T;
            self.Report_ = report;
            self.populate_(previous);
        end

        function review(self, row)
            % review(self)
            % review(self, row)
            % Reopen a session in its behavior GUI with epsych.ReviewSession.
            %
            % Parameters:
            %   row - Row of Sessions (DATA order). Default: the selected row.
            arguments
                self
                row double = []
            end

            if isempty(row)
                row = self.selectedRow_();
            end
            if isempty(row) || row < 1 || row > height(self.Sessions)
                self.setStatus_('Select a session first.');
                return
            end

            if self.refuseWhileRunning_('Reviewing')
                self.alert_(['A session is running. Saved sessions can be reviewed ' ...
                    'from here once it has stopped.'], 'Review Session', 'warning');
                return
            end

            s = self.Sessions(row, :);
            why = localUnreviewable(s);
            if why ~= ""
                self.alert_(why, 'Review Session', 'info');
                return
            end

            file = char(s.File);
            if ~isfile(file)
                self.alert_(sprintf(['This file is no longer where it was found:\n\n%s' ...
                    '\n\nRescan (F5) to update the list.'], file), 'Review Session', 'warning');
                return
            end

            % A review's windows are not modal, and an always-on-top session
            % window would sit over them.
            rx = self.liveRunExpt_();
            if ~isempty(rx)
                rx.AlwaysOnTop(false);
            end

            fig = self.H.figure;
            fig.Pointer = 'watch';
            drawnow
            restorePointer = onCleanup(@() localRestorePointer(fig));

            try
                epsych.ReviewSession(file);
            catch ME
                vprintf(0, 1, ME);
                self.alert_(sprintf('This session could not be opened for review:\n\n%s', ...
                    ME.message), 'Review Session', 'error');
                return
            end
            clear restorePointer

            self.setStatus_(sprintf('Opened %s for review.', s.FileName));
        end

    end

    % -----------------------------------------------------------------------
    methods (Static)

        function tf = sessionIsRunning(runExpt)
            % tf = gui.SessionBrowser.sessionIsRunning(runExpt)
            % True while a session is RUNNING or finishing (POSTRUN) -- the
            % states in which RunExpt itself refuses configuration changes.
            %
            % Parameters:
            %   runExpt - epsych.RunExpt to ask. [] or a deleted one asks
            %             whichever session window is open, so a caller bound
            %             to no session cannot mistake "not told" for "stopped".
            arguments
                runExpt = []
            end

            if ~localIsRunExpt(runExpt)
                runExpt = epsych.SelfTest.findActiveRunExpt();
            end
            tf = localIsRunExpt(runExpt) && runExpt.STATE >= PRGMSTATE.RUNNING;
        end

    end

    % -----------------------------------------------------------------------
    methods (Access = private)
        buildUI(self, visible)
    end

    methods (Static, Access = private)

        function closeFor_(subjectName)
            % Close a browser already open for this subject. One window per
            % subject: a second request means "show me again", and a fresh
            % window also picks up a roster edited since the first.
            figs = findall(groot, 'Type', 'figure', 'Tag', gui.SessionBrowser.FIGURE_TAG);
            for i = 1:numel(figs)
                prior = figs(i).UserData;
                if isa(prior, 'gui.SessionBrowser') && isvalid(prior) ...
                        && strcmpi(prior.SubjectName, subjectName)
                    delete(prior);
                end
            end
        end

    end

    methods (Access = private)

        % ---- population ------------------------------------------------

        function populate_(self, keepFile)
            % Redraw the table from Sessions and restore the selection.
            n = height(self.Sessions);

            removeStyle(self.H.table);
            self.H.table.Data = self.displayTable_();

            if n == 0
                self.H.table.Visible = 'off';
                self.H.emptyState.Text = self.emptyStateText_();
                self.H.emptyState.Visible = 'on';
            else
                self.H.emptyState.Visible = 'off';
                self.H.table.Visible = 'on';

                % Rows that cannot be reviewed are greyed rather than hidden:
                % a session that recorded nothing, or a damaged file, is still
                % part of the animal's history. Styles follow their DATA row
                % through a header sort.
                dead = find(self.Sessions.Error ~= "" | self.Sessions.Trials == 0);
                if ~isempty(dead)
                    addStyle(self.H.table, uistyle('FontColor', self.GREYED), 'row', dead);
                end
                recovery = find(self.Sessions.Source == "Recovery");
                if ~isempty(recovery)
                    addStyle(self.H.table, uistyle('FontAngle', 'italic'), 'row', recovery);
                end

                row = [];
                if keepFile ~= ""
                    row = find(self.Sessions.File == keepFile, 1);
                end
                if isempty(row), row = 1; end   % the newest
                self.H.table.Selection = row;
                try
                    scroll(self.H.table, 'row', row);
                catch
                end
            end

            self.H.title.Text = char(self.SubjectName);
            self.H.count.Text = self.countText_();
            [where, whereTip] = self.whereText_();
            self.H.status.Text = where;
            self.H.status.Tooltip = whereTip;
            if ~isempty(self.Report_.Missing)
                self.H.status.FontColor = [0.60 0.32 0.02];
            else
                self.H.status.FontColor = self.MUTED;
            end

            self.onSelectionChanged_();
        end

        function D = displayTable_(self)
            % The table the operator sees, built so a header click sorts by
            % value. Date and Trials are typed. Start, Duration and Box are
            % FIXED-WIDTH TEXT instead, because a typed column shows an unknown
            % as NaN -- which every legacy file would put in its Box cell -- and
            % fixed width is what keeps a text sort the numeric one: "09:05" <
            % "10:22", and a box padded to " 2" sorts before "10".
            T = self.Sessions;

            date = T.StartTime;
            date.Format = 'yyyy-MM-dd  eee';
            start = localFixedText(timeofday(T.StartTime), 'hh:mm');
            dur = localFixedText(T.Duration, 'hh:mm:ss');
            box = compose("%2d", T.BoxID);
            box(isnan(T.BoxID)) = "";

            source = T.Source;
            source(T.IsTest) = source(T.IsTest) + " (preview)";

            % What opening the row will give: a full review needs the protocol
            % the snapshot carries; without it only the data displays come back.
            reviewable = repmat("Data only", height(T), 1);
            reviewable(T.HasSnapshot) = "Full";
            reviewable(T.Trials == 0) = "No trials";
            reviewable(T.Error ~= "") = "Unreadable";

            D = table(date, start, dur, T.Trials, box, T.Paradigm, ...
                T.VideoFile ~= "", source, reviewable, T.FileName, ...
                'VariableNames', {'Date','Start','Duration','Trials','Box', ...
                    'Paradigm','Video','Source','Review','File'});
        end

        function txt = countText_(self)
            T = self.Sessions;
            n = height(T);
            if n == 0
                txt = 'no sessions found';
                return
            end

            nSaved = nnz(T.Source == "Saved");
            parts = {sprintf('%d session%s', nSaved, localPlural(nSaved))};
            nRecovery = n - nSaved;
            if nRecovery > 0
                parts{end+1} = sprintf('%d recovery file%s', nRecovery, localPlural(nRecovery));
            end
            nTrials = sum(T.Trials);
            parts{end+1} = sprintf('%d trials', nTrials);

            known = T.StartTime(~isnat(T.StartTime));
            if ~isempty(known)
                parts{end+1} = sprintf('%s to %s', ...
                    char(min(known), 'dd-MMM-yyyy'), char(max(known), 'dd-MMM-yyyy'));
            end
            if self.Report_.Cancelled
                parts{end+1} = 'scan stopped early';
            end
            txt = strjoin(parts, '  ·  ');
        end

        function [txt, tip] = whereText_(self)
            % The status line says where the list came from, since "no
            % sessions" and "looked in the wrong place" look identical
            % otherwise. The full account goes in the tooltip.
            R = self.Report_;
            folders = R.Folders;

            if isempty(folders)
                txt = 'Looked in: (no data folder for this subject was found)';
            elseif isscalar(folders)
                txt = ['Looked in: ' char(folders)];
            else
                txt = sprintf('Looked in %d folders: %s', numel(folders), ...
                    char(strjoin(folders, '; ')));
            end
            if ~isempty(R.Missing)
                txt = sprintf('%s   —   %d data folder%s could not be reached', ...
                    txt, numel(R.Missing), localPlural(numel(R.Missing)));
            end

            lines = {'Searched:'};
            lines = [lines, cellstr("  " + folders)];
            if ~isempty(R.Missing)
                lines = [lines, {'', 'Not found (unmounted share, moved folder?):'}, ...
                    cellstr("  " + R.Missing)];
            end
            if R.NumSkipped > 0
                lines = [lines, {'', sprintf('%d .mat file%s in these folders %s not session data.', ...
                    R.NumSkipped, localPlural(R.NumSkipped), localWere(R.NumSkipped))}];
            end
            tip = strjoin(lines, newline);
        end

        function txt = emptyStateText_(self)
            R = self.Report_;
            L = self.Locations;

            if isempty(L.Roots)
                txt = sprintf(['No data folder is configured for %s: its projects set no ' ...
                    'data path and this rig has none either.'], self.SubjectName);
            elseif isempty(R.Folders)
                txt = sprintf('No folder named "%s" exists under %s.', ...
                    self.SubjectName, char(strjoin(L.Roots, ' or ')));
            else
                txt = sprintf('No session files for %s in %s.', ...
                    self.SubjectName, char(strjoin(R.Folders, ' or ')));
            end

            if ~isempty(R.Missing)
                txt = sprintf('%s\n\nThese data folders could not be reached:\n%s', ...
                    txt, char(strjoin(R.Missing, newline)));
            end

            txt = sprintf(['%s\n\nA session saved somewhere else can still be opened with ' ...
                'Review Saved Session... in the session window (Ctrl+K).'], txt);
        end

        % ---- selection and details -------------------------------------

        function row = selectedRow_(self)
            % DATA row under the selection, or [].
            row = [];
            sel = self.H.table.Selection;
            if isempty(sel) || height(self.Sessions) == 0, return, end
            row = sel(1);
            if row > height(self.Sessions), row = []; end
        end

        function f = selectedFile_(self)
            f = "";
            row = self.selectedRow_();
            if ~isempty(row), f = self.Sessions.File(row); end
        end

        function onSelectionChanged_(self)
            self.showDetails_(self.selectedRow_());
            self.updateEnableStates_();
        end

        function showDetails_(self, row)
            % Everything the table has no room for, for the selected file.
            if isempty(row)
                self.H.details.Value = {''};
                return
            end

            s = self.Sessions(row, :);
            lines = {char(s.File)};

            if ~isnat(s.StartTime)
                when = char(s.StartTime, 'eeee dd-MMM-yyyy HH:mm:ss');
                if ~isnat(s.EndTime) && ~isnan(s.Duration)
                    when = sprintf('%s   to   %s   (%s)', when, ...
                        char(s.EndTime, 'HH:mm:ss'), localDuration(s.Duration));
                end
                lines{end+1} = when;
            end

            what = sprintf('%d trial%s', s.Trials, localPlural(s.Trials));
            if ~isnan(s.BoxID), what = sprintf('%s   ·   Box %d', what, s.BoxID); end
            if s.Paradigm ~= "", what = sprintf('%s   ·   %s', what, s.Paradigm); end
            if s.ProtocolVersion ~= "", what = sprintf('%s   ·   protocol %s', what, s.ProtocolVersion); end
            if s.EPsychVersion ~= "", what = sprintf('%s   ·   EPsych %s', what, s.EPsychVersion); end
            lines{end+1} = what;

            if s.VideoFile ~= ""
                lines{end+1} = ['Video: ' char(s.VideoFile)];
            end

            lines{end+1} = char(localReviewMeaning(s));

            lines{end+1} = '';
            if s.NotesText ~= ""
                lines{end+1} = 'Notes:';
                lines = [lines, cellstr(splitlines(s.NotesText))'];
            else
                lines{end+1} = 'No session notes.';
            end

            self.H.details.Value = lines;
        end

        % ---- session state ---------------------------------------------

        function rx = liveRunExpt_(self)
            % The session window to ask about: the one being followed, else
            % whichever is open now (one may have been opened since).
            rx = self.RunExpt;
            if ~localIsRunExpt(rx)
                rx = epsych.SelfTest.findActiveRunExpt();
            end
        end

        function followSession_(self)
            % Grey out when a session starts and come back when it stops,
            % rather than leaving live-looking controls that then refuse.
            rx = self.RunExpt;
            if ~localIsRunExpt(rx), return, end
            self.StateListener_ = listener(rx, 'STATE', 'PostSet', ...
                @(~,~) self.onSessionState_());
        end

        function onSessionState_(self)
            % Runs inside RunExpt's own state change, so it stays cheap and
            % never lets an error escape into the session.
            try
                if isvalid(self) && isfield(self.H, 'figure') && isgraphics(self.H.figure)
                    self.updateEnableStates_();
                end
            catch ME
                vprintf(2, ME);
            end
        end

        function tf = refuseWhileRunning_(self, what)
            % True (and the controls greyed, and the status line saying why)
            % when a session is running. Checked in the action itself and not
            % only through Enable, so a script or a stale button fails closed.
            tf = gui.SessionBrowser.sessionIsRunning(self.liveRunExpt_());
            if tf
                self.updateEnableStates_();
                self.setStatus_(sprintf('%s is not available while a session is running.', what));
            end
        end

        function updateEnableStates_(self)
            running = gui.SessionBrowser.sessionIsRunning(self.liveRunExpt_());
            row = self.selectedRow_();
            canReview = ~running && ~isempty(row) ...
                && localUnreviewable(self.Sessions(row,:)) == "";

            onoff = @(tf) matlab.lang.OnOffSwitchState(tf);
            self.H.btnReview.Enable   = onoff(canReview);
            self.H.cmnu_review.Enable = onoff(canReview);
            self.H.btnRescan.Enable   = onoff(~running);
            self.H.chkRecovery.Enable = onoff(~running);

            if running ~= self.Running_
                self.Running_ = running;
                if running
                    self.H.root.RowHeight{2} = 28;
                    self.H.banner.Visible = 'on';
                else
                    self.H.root.RowHeight{2} = 0;
                    self.H.banner.Visible = 'off';
                end
            end

            if running
                self.H.btnReview.Tooltip = 'Not while a session is running.';
            elseif isempty(row)
                self.H.btnReview.Tooltip = 'Select a session first.';
            elseif ~canReview
                self.H.btnReview.Tooltip = char(localUnreviewable(self.Sessions(row,:)));
            else
                self.H.btnReview.Tooltip = ['Open this session in its behavior GUI, ' ...
                    'with a trial scrubber (Enter, or double-click the row)'];
            end
        end

        % ---- callbacks -------------------------------------------------

        function onDoubleClick_(self, evt)
            % Double-click reviews the row under the pointer.
            try
                row = evt.InteractionInformation.Row;
            catch
                row = [];
            end
            if isempty(row), return, end
            self.review(row(1));
        end

        function onContextMenuOpening_(self, evt)
            % A right-click acts on the row under the pointer, so select it:
            % the menu then says, and does, the same thing the details show.
            try
                row = evt.InteractionInformation.Row;
                if ~isempty(row) && row(1) <= height(self.Sessions)
                    self.H.table.Selection = row(1);
                    self.onSelectionChanged_();
                end
            catch ME
                vprintf(3, 'gui.SessionBrowser: cannot resolve the right-clicked row: %s', ME.message)
            end
            has = ~isempty(self.selectedRow_());
            self.H.cmnu_copy.Enable = matlab.lang.OnOffSwitchState(has);
            self.H.cmnu_folder.Enable = matlab.lang.OnOffSwitchState(has);
        end

        function onRecoveryToggled_(self)
            try
                setpref(self.PREF_GROUP, 'SessionBrowserRecovery', self.H.chkRecovery.Value);
            catch ME
                vprintf(2, ME);
            end
            self.rescan();
        end

        function copyPath_(self)
            row = self.selectedRow_();
            if isempty(row), return, end
            clipboard('copy', char(self.Sessions.File(row)));
            self.setStatus_(sprintf('Copied the path of %s.', self.Sessions.FileName(row)));
        end

        function showInFolder_(self)
            row = self.selectedRow_();
            if isempty(row), return, end
            folder = char(self.Sessions.Folder(row));
            try
                epsych.SubjectRoster.openLink(folder);
                self.setStatus_(sprintf('Opened %s', folder));
            catch ME
                vprintf(0, 1, ME);
                self.alert_(ME.message, 'Show in Folder', 'warning');
            end
        end

        function alert_(self, message, title, icon)
            % Tell the operator why an action did nothing. uialert refuses a
            % hidden figure, and review() is public -- a script driving a
            % window it never showed must get the reason, not a second error.
            self.setStatus_(strtok(message, newline));
            if strcmp(self.H.figure.Visible, 'on')
                uialert(self.H.figure, message, title, 'Icon', icon);
            else
                vprintf(1, 'gui.SessionBrowser: %s: %s', title, message)
            end
        end

        function onKeyPress_(self, evt)
            switch evt.Key
                case 'return'
                    self.review();
                case 'f5'
                    self.rescan();
                case 'escape'
                    delete(self);
            end
        end

        function setStatus_(self, message)
            self.H.status.Text = message;
            self.H.status.FontColor = self.MUTED;
        end

    end
end




function tf = localIsRunExpt(rx)
tf = ~isempty(rx) && isa(rx, 'epsych.RunExpt') && isvalid(rx);
end


function why = localUnreviewable(s)
% "" when a session row can be opened for review, else the reason it cannot.
why = "";
if s.Error ~= ""
    why = "This file could not be read: " + s.Error;
elseif s.Trials == 0
    why = "No trials were recorded in this file, so there is nothing to review.";
end
end


function txt = localReviewMeaning(s)
% The Review column in a sentence, for the details pane.
why = localUnreviewable(s);
if why ~= ""
    txt = why;
elseif s.HasSnapshot
    txt = "Review: opens in the paradigm's behavior GUI, controls and displays as they were at the end.";
else
    txt = "Review: this file carries no protocol (saved before 2026-08), so a review " + ...
        "shows the data displays without the parameter controls.";
end
end


function txt = localFixedText(d, fmt)
% A duration column as text of one width, blank where it is unknown.
d.Format = fmt;
txt = string(d);
txt(isnan(d)) = "";
end


function txt = localDuration(d)
% "13 min 37 s", "1 h 02 min": a sentence reads a duration better than hh:mm:ss.
s = round(seconds(d));
h = floor(s / 3600);
m = floor(mod(s, 3600) / 60);
if h > 0
    txt = sprintf('%d h %02d min', h, m);
else
    txt = sprintf('%d min %02d s', m, mod(s, 60));
end
end


function s = localPlural(n)
s = '';
if n ~= 1, s = 's'; end
end


function s = localWere(n)
s = 'were';
if n == 1, s = 'was'; end
end


function tf = localProgress(dlg, k, n)
% Advance the scan's progress dialog; false when the operator cancelled.
tf = true;
if isempty(dlg) || ~isvalid(dlg), return, end
dlg.Value = (k - 1) / max(n, 1);
dlg.Message = sprintf('Reading file %d of %d...', k, n);
tf = ~dlg.CancelRequested;
end


function localCloseDialog(dlg)
if ~isempty(dlg) && isvalid(dlg)
    close(dlg);
end
end


function localRestorePointer(fig)
if isgraphics(fig)
    fig.Pointer = 'arrow';
end
end
