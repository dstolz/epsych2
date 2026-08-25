classdef ParameterDebugger < handle
    % gui.ParameterDebugger
    % obj = gui.ParameterDebugger()
    % obj = gui.ParameterDebugger(source)
    % Read and write every parameter a protocol defines, from one window.
    %
    % Opened from the session window's Help menu, this is the generic answer to
    % "is the hardware actually seeing what I think it is?". It lists every
    % hw.Parameter reachable from a protocol -- across every interface and
    % module -- and lets the operator read one, read a selection, or read them
    % all, and write any parameter that is writable. Nothing is polled: every
    % read happens because the operator asked for it, so opening this window
    % cannot perturb the timing of the session it is being used to debug.
    %
    % It is deliberately a window of its own rather than part of a behavior GUI. A
    % behavior GUI shows the handful of controls a paradigm needs and is written per
    % experiment; this shows everything, including the parameters no GUI
    % exposes, and works the same against any protocol on any backend.
    %
    % Colour is the read report. The Value cell turns pale green when the read
    % came back, pale red when it threw, blue when this window wrote the value,
    % amber when a written value did not read back as written, and grey when
    % the parameter cannot be read at all (write-only, or a buffer skipped by
    % Read All). A row that has never been read stays uncoloured, so "I have
    % not asked yet" never looks like "it came back empty".
    %
    % Source of parameters, in the order they are offered: each subject's
    % protocol in RunExpt.CONFIG, plus the live session's interfaces when a run
    % is in progress. Before a run these are the same objects a run will use
    % (ExptDispatch hands RUNTIME subject 1's protocol interfaces), which is
    % why the window is useful while a config is merely loaded -- reads then
    % return the design-time values held in the objects, marked "offline"
    % because no backend was asked.
    %
    % The Find box narrows the list as it is typed, matching the interface,
    % module, and parameter name together; tick Regex to give it a pattern
    % instead of a substring, and Esc (or the button beside it) clears it. A
    % filter change keeps the read report, because narrowing a list is not new
    % evidence about the parameters left in it -- only a rebuild starts over.
    %
    % Columns sort on a header click and drag into whatever order suits the
    % question. Both are display-only: every action here works from the DATA
    % index uitable reports, never the position a row happens to be drawn at.
    %
    % Properties:
    %   RunExpt   - epsych.RunExpt this window was opened from, or []
    %   Rows      - One record per listed parameter, in table order
    %   H         - Graphics handles
    %
    % Methods:
    %   refresh       - Rebuild the parameter list from the selected source
    %   readAll       - Read every listed parameter
    %   readRows      - Read the given rows
    %   writeRow      - Parse text and write it to one row's parameter
    %   fireTrigger   - Fire the selected trigger parameter
    %   trackSelected - Plot the selected parameters against time (Ctrl+T)
    %
    % Examples:
    %   gui.ParameterDebugger                    % bind to the open session
    %   gui.ParameterDebugger(myProtocol)        % any protocol, no session
    %   gui.ParameterDebugger(RUNTIME.Interfaces)
    %
    % See also: documentation/gui/gui_ParameterDebugger.md,
    %   epsych.RunExpt.OpenParameterDebugger, gui.Parameter_Monitor,
    %   gui.Parameter_Control, hw.Parameter

    properties (SetAccess = private)
        RunExpt             % epsych.RunExpt this window belongs to, or []
        Rows = []           % one record per table row, in table order
        H = struct()        % graphics handles
    end

    properties (Dependent)
        % True while a read sweep or a rebuild owns the row list. Callbacks
        % that would rewrite Rows drop their request while this is set; it is
        % public so a test can assert the guard is lowered again afterwards.
        IsBusy
    end

    properties (Access = private)
        Sources_ = []       % struct array of Label/Interfaces the dropdown offers
        Interfaces_ = []    % interfaces behind the rows now listed

        % How many parameters the last rebuild dropped for being invisible, so
        % an empty table only suggests "Show hidden" when that would actually
        % reveal something.
        HiddenSkipped_ (1,1) double = 0
        Seed_ = []          % what the constructor was handed, when not a RunExpt
        Refreshing_ (1,1) logical = false  % guards callbacks fired by repopulation

        % Selected source label, so rebuilding the list after a run starts
        % (which replaces RunExpt.RUNTIME) does not drop the operator back to
        % the first subject.
        LastSource_ (1,:) char = ''

        % What the Find box holds. Kept here rather than read back off the
        % widget because filtering happens on every keystroke, and until the
        % operator presses Enter the widget's own Value is still the old text.
        FilterText_ (1,:) char = ''

        % Live plot windows this one opened. They are not owned: a tracker has
        % its own window and its own timer and outlives this one, so this is
        % only how "Track Selected" finds the plot to add the next line to.
        Trackers_ = gui.ParameterTracker.empty(1,0)
    end

    properties (Constant)
        % Row states, exposed so a test can assert on an outcome without
        % matching the colour it happens to be painted.
        STATE_UNREAD = 0
        STATE_OK     = 1
        STATE_FAIL   = 2
        STATE_WROTE  = 3
        STATE_STALE  = 4
        STATE_SKIP   = 5
    end

    properties (Constant, Access = private)
        FIGURE_TAG (1,:) char = 'EPsychParameterDebugger'
        PREF_TAG   (1,:) char = 'epsych2_gui_ParameterDebugger'

        DEFAULT_POSITION (1,4) double = [100 100 1180 660]

        % Value-cell tints, matching the pale palette gui.SelfTest established:
        % the text carries the meaning, the colour only makes a row findable by
        % eye across a table of two hundred parameters.
        COLOR_OK    (1,3) double = [0.90 0.97 0.90]
        COLOR_FAIL  (1,3) double = [1.00 0.88 0.88]
        COLOR_WROTE (1,3) double = [0.92 0.95 1.00]
        COLOR_STALE (1,3) double = [1.00 0.96 0.85]
        COLOR_SKIP  (1,3) double = [0.94 0.94 0.94]

        MUTED_COLOR (1,3) double = [0.55 0.58 0.62]

        % Largest array still shown as an editable literal. Beyond this the
        % cell shows a summary instead: pasting a thousand numbers into a table
        % cell is not editing, and rendering them makes every refresh crawl.
        MAX_INLINE_ELEMENTS (1,1) double = 24

        % Types whose value is potentially megabytes off the device. Read All
        % skips them unless asked; reading one on purpose always works.
        BULK_TYPES = {'Buffer','Coefficient Buffer'}
    end

    methods
        refresh(self)                  % Rebuild the parameter list from the selected source
        readRows(self, rows, options)  % Read the given rows and colour the result

        function self = ParameterDebugger(source, options)
            % self = gui.ParameterDebugger(source)
            % self = gui.ParameterDebugger(source, Visible=false)
            % Open the debugger, replacing any window already open.
            %
            % Parameters:
            %   source          - epsych.RunExpt, epsych.Runtime, epsych.Protocol,
            %                     or an hw.Interface array. Defaults to the live
            %                     session, or [] when none is open.
            %   options.Visible - Show the window (default true). False builds it
            %                     without putting it on screen, which is how the
            %                     smoke test and the screenshot generator drive
            %                     it; same option, same reason, as gui.BehaviorGUI.
            %
            % Returns:
            %   self   - gui.ParameterDebugger instance.
            arguments
                source = epsych.SelfTest.findActiveRunExpt()
                options.Visible (1,1) logical = true
            end

            % One window at a time. Detach UserData and CloseRequestFcn first
            % so deleting it cannot re-enter this object's own teardown.
            %
            % The position is saved here rather than left to the prior object's
            % destructor: that destructor only saves while its figure is still
            % a graphics object, so deleting the figure first would silently
            % throw away wherever the operator had dragged the window. Reopening
            % from the Help menu is the ordinary way to get a second window, so
            % that loss would happen constantly.
            existing = findall(groot, 'Type','figure', 'Tag', self.FIGURE_TAG);
            for i = 1:numel(existing)
                if ~isgraphics(existing(i)), continue, end
                prior = existing(i).UserData;
                gui.BehaviorGUI.saveFigurePosition(self.PREF_TAG, existing(i).Position);
                existing(i).UserData = [];
                existing(i).CloseRequestFcn = '';
                delete(existing(i));
                if isobject(prior) && isvalid(prior)
                    delete(prior);
                end
            end

            if isa(source, 'epsych.RunExpt') && isvalid(source)
                self.RunExpt = source;
            elseif ~isempty(source)
                self.Seed_ = source;
            end

            self.buildUI(options.Visible);
            self.refresh();

            if nargout == 0
                clear self
            end
        end

        function delete(self)
            % delete(self)
            % Tear down the window, saving its position.
            try
                if isfield(self.H,'figure') && isgraphics(self.H.figure)
                    gui.BehaviorGUI.saveFigurePosition(self.PREF_TAG, self.H.figure.Position);
                    self.H.figure.UserData = [];
                    self.H.figure.CloseRequestFcn = '';
                    delete(self.H.figure);
                end
            catch ME
                vprintf(2, ME);
            end
        end

        function tf = get.IsBusy(self)
            tf = self.Refreshing_;
        end

        function readAll(self)
            % readAll(self)
            % Read every listed parameter. Bulk types are skipped unless the
            % "Include buffers" box is ticked.
            self.readRows(1:numel(self.Rows));
        end

        function readSelected(self)
            % readSelected(self)
            % Read the rows currently selected in the table. Selecting a bulk
            % parameter is an explicit enough request to read it.
            rows = self.selectedRows_();
            if isempty(rows)
                self.setStatus_('Select one or more rows first, or use Read All.');
                return
            end
            self.readRows(rows, Force = true);
        end

        function writeRow(self, row, text)
            % writeRow(self, row, text)
            % Parse text as a value for one row's parameter and write it.
            %
            % The write is followed immediately by a read-back, because on a
            % live backend the only proof a write landed is what the device
            % returns afterwards. A value that reads back differently is not an
            % error -- clamping, an Expression, and a coarse hardware
            % quantiser all do it legitimately -- so it is reported amber with
            % both values rather than red.
            arguments
                self
                row (1,1) double {mustBeInteger, mustBePositive}
                text (1,:) char
            end

            if row > numel(self.Rows), return, end
            R = self.Rows(row);
            P = R.Parameter;

            if ~isvalid(P)
                self.markRow_(row, self.STATE_FAIL, R.ValueText, 'parameter deleted');
                self.setStatus_('That parameter no longer exists. Rebuild the list (Ctrl+R).');
                return
            end

            if strcmp(P.Access, 'Read')
                self.markRow_(row, R.State, R.ValueText, R.Note);
                self.setStatus_(sprintf('"%s" is read-only.', R.Name));
                return
            end

            if P.isTrigger
                self.markRow_(row, R.State, R.ValueText, R.Note);
                self.setStatus_(sprintf('"%s" is a trigger; use Fire Trigger to send it.', R.Name));
                return
            end

            [value, ok, why] = self.parseValue_(P, text);
            if ~ok
                self.markRow_(row, self.STATE_FAIL, R.ValueText, why);
                self.setStatus_(sprintf('"%s": %s', R.Name, why));
                return
            end

            try
                P.Value = value;
            catch ME
                vprintf(0, 1, ME);
                self.markRow_(row, self.STATE_FAIL, R.ValueText, ME.message);
                self.setStatus_(sprintf('Writing "%s" failed: %s', R.Name, ME.message));
                return
            end

            vprintf(1, 'Parameter Debugger wrote "%s" = %s', R.Name, text);

            % Session-record note: a hand-write to live hardware belongs in the
            % data set's record (Info.Notes), and this window is available even
            % for a session running with no behavior GUI at all. The typed
            % value is recorded; what the device actually holds is the trial
            % record's job. No-op outside a live session.
            rx = self.RunExpt;
            if ~isempty(rx) && isvalid(rx)
                epsych.SessionNotes.log(rx.RUNTIME, ...
                    'Parameter Debugger wrote %s = %s', R.Name, text);
            end

            % Read-back. A parameter that cannot be read leaves the written
            % value standing, marked as written rather than as confirmed.
            %
            % What is shown is the value after clamping, not the text typed:
            % set.Value clamps to [Min Max] on the way in, so displaying the
            % typed number would claim the device holds something it does not.
            % clampValue previews the same arithmetic without writing again.
            % An Expression or isRandom can still transform the value beyond
            % this, which is exactly why the note says the value is unverified.
            if strcmp(P.Access, 'Write')
                [shown, wasClamped] = P.clampValue(value);
                note = 'written (write-only, cannot be read back)';
                if wasClamped
                    note = 'written, clamped to bounds (cannot be read back)';
                end
                self.markValue_(row, self.STATE_WROTE, P, shown, note);
                self.setStatus_(sprintf('Wrote "%s". It is write-only, so it cannot be read back.', R.Name));
                return
            end

            try
                readBack = P.Value;
            catch ME
                self.markValue_(row, self.STATE_WROTE, P, value, ME.message);
                self.setStatus_(sprintf('Wrote "%s", but reading it back failed: %s', R.Name, ME.message));
                return
            end

            backText = self.valueText_(P, readBack);
            if isequaln(readBack, value)
                self.markValue_(row, self.STATE_WROTE, P, readBack, ...
                    ['written ' self.timestamp_(R.Interface)]);
                self.setStatus_(sprintf('Wrote "%s" = %s.', R.Name, backText));
            else
                self.markValue_(row, self.STATE_STALE, P, readBack, ...
                    sprintf('wrote %s, read %s', text, backText));
                self.setStatus_(sprintf('"%s" was written as %s but reads back as %s.', ...
                    R.Name, text, backText));
            end
        end

        function fireTrigger(self)
            % fireTrigger(self)
            % Fire the trigger parameter(s) among the selected rows.
            rows = self.selectedRows_();
            if isempty(rows)
                self.setStatus_('Select a trigger row first.');
                return
            end

            fired = 0;
            for row = rows
                R = self.Rows(row);
                if ~isvalid(R.Parameter) || ~R.Parameter.isTrigger, continue, end
                try
                    R.Parameter.Trigger();
                    fired = fired + 1;
                    self.markRow_(row, self.STATE_WROTE, R.ValueText, ...
                        ['fired ' self.timestamp_(R.Interface)]);
                catch ME
                    vprintf(0, 1, ME);
                    self.markRow_(row, self.STATE_FAIL, R.ValueText, ME.message);
                end
            end

            if fired == 0
                self.setStatus_('No trigger parameter among the selected rows.');
            else
                self.setStatus_(sprintf('Fired %d trigger(s).', fired));
            end
        end

        function T = trackSelected(self, options)
            % T = trackSelected(self)
            % T = trackSelected(self, NewPlot=true)
            % Plot the selected parameters against time in a gui.ParameterTracker.
            %
            % The table answers "what is it now"; a tracker answers "is it
            % moving". Only scalar parameters can be plotted, so a selection
            % that also contains a buffer or a string tracks what it can and
            % says what it left out.
            %
            % By default the parameters join the tracker this window opened
            % last, because comparing two values on one time axis is the usual
            % reason to track a second one. NewPlot=true always opens another.
            arguments
                self
                options.NewPlot (1,1) logical = false
            end

            T = gui.ParameterTracker.empty(1,0);
            rows = self.selectedRows_();
            if isempty(rows)
                self.setStatus_('Select the parameters to track first.');
                return
            end

            P = [self.Rows(rows).Parameter];
            ok = arrayfun(@(p) isvalid(p) && gui.ParameterTracker.isTrackable(p), P);
            if ~any(ok)
                self.setStatus_(['Nothing selected can be plotted: only scalar ' ...
                    'numeric and boolean parameters can be tracked.']);
                return
            end

            self.Trackers_ = self.Trackers_(isvalid(self.Trackers_));

            if ~options.NewPlot && ~isempty(self.Trackers_)
                T = self.Trackers_(end);
                T.addParameters(P(ok));
                figure(T.H.figure);
            else
                T = gui.ParameterTracker(P(ok), Available = self.trackableParameters_());
                self.Trackers_(end+1) = T;
            end

            if all(ok)
                self.setStatus_(sprintf('Tracking %d parameter(s).', sum(ok)));
            else
                self.setStatus_(sprintf(['Tracking %d parameter(s); %d could not be ' ...
                    'plotted (not a scalar value).'], sum(ok), sum(~ok)));
            end

            if nargout == 0
                clear T
            end
        end

        function assignToBase(self)
            % assignToBase(self)
            % Put the selected hw.Parameter into the base workspace as P, so
            % the command window can take over where this window stops.
            rows = self.selectedRows_();
            if isempty(rows)
                self.setStatus_('Select a row first.');
                return
            end

            name = self.Rows(rows(1)).Name;
            assignin('base', 'P', self.Rows(rows(1)).Parameter);
            vprintf(1, 'Parameter Debugger assigned "%s" to the base workspace variable P', name);
            self.setStatus_(sprintf('"%s" assigned to the command window as P.', name));
        end

        function copyToClipboard(self)
            % copyToClipboard(self)
            % Copy the table as tab-separated text, for pasting into a bug
            % report or a lab notebook: the selection when there is one,
            % otherwise every row.
            rows = self.selectedRows_();
            if isempty(rows), rows = 1:numel(self.Rows); end
            if isempty(rows)
                self.setStatus_('Nothing to copy.');
                return
            end

            data = self.H.table.Data(rows, :);
            lines = cell(1, size(data,1) + 1);
            lines{1} = strjoin(self.H.table.ColumnName(:)', sprintf('\t'));
            for i = 1:size(data,1)
                lines{i+1} = strjoin(cellfun(@char, data(i,:), 'UniformOutput', false), sprintf('\t'));
            end

            clipboard('copy', strjoin(lines, newline));
            self.setStatus_(sprintf('Copied %d row(s) to the clipboard.', numel(rows)));
        end
    end

    % -----------------------------------------------------------------------
    % Substantial private behaviour lives in its own file; the small callbacks
    % below stay here, following gui.SelfTest and gui.SubjectManager.
    % -----------------------------------------------------------------------
    methods (Access = private)
        buildUI(self, visible)
    end

    % ---- Selection, callbacks, and the table -------------------------------
    methods (Access = private)
        function rows = selectedRows_(self)
            % Table selection as row indices into Rows, clipped to what exists.
            %
            % sel(:) rather than sel(:,1): with SelectionType='row' a uitable
            % returns Selection as a 1-by-N ROW vector of row indices, so
            % taking column 1 would keep only the first selected row and
            % silently drop the rest -- which every multi-row action here
            % (Read Selected, Fire Trigger, Copy) depends on.
            rows = [];
            sel = self.H.table.Selection;
            if isempty(sel) || isempty(self.Rows), return, end
            rows = unique(sel(:))';
            rows = rows(rows >= 1 & rows <= numel(self.Rows));
        end

        function onDoubleClick_(self, evt)
            % Double-clicking a parameter reads it. The Value column is left
            % alone: a double-click there opens the cell editor, and reading
            % underneath the operator's cursor would replace what they type.
            try
                info = evt.InteractionInformation;
                row = info.Row;
                col = info.Column;
            catch ME
                vprintf(3, 'gui.ParameterDebugger: double-click carried no cell: %s', ME.message);
                return
            end
            if isempty(row), return, end
            if ~isempty(col) && col == self.valueColumn_(), return, end
            self.readRows(row(1), Force = true);
        end

        function onCellEdit_(self, evt)
            % Only the Value column is editable.
            if self.Refreshing_, return, end
            row = evt.Indices(1);
            col = evt.Indices(2);
            if col ~= self.valueColumn_() || row > numel(self.Rows), return, end

            text = strtrim(char(string(evt.NewData)));
            if isequal(text, strtrim(char(string(evt.PreviousData))))
                return
            end

            if ~self.Rows(row).Editable
                % Put the summary back: it was never a literal to edit.
                self.H.table.Data{row, col} = self.Rows(row).ValueText;
                self.setStatus_(sprintf(['"%s" is too large or too complex to edit in the grid. ' ...
                    'Right-click and assign it to the command window instead.'], self.Rows(row).Name));
                return
            end

            self.writeRow(row, text);
        end

        function onSelectionChanged_(self)
            if self.Refreshing_, return, end
            self.updateEnableStates_();
        end

        function onSourceChanged_(self)
            if self.Refreshing_, return, end
            self.LastSource_ = char(self.H.source.Value);
            self.refresh();
        end

        function onFilterTyped_(self, text)
            % Every keystroke in the Find box, and every commit of it.
            %
            % Filtering per character is affordable because it touches nothing
            % but objects already in memory: the walk is over the interface's
            % parameter handles, and no backend is asked for anything. That is
            % what lets it be live -- a window that polled hardware could not
            % narrow a list while a person types.
            if self.Refreshing_, return, end
            text = char(string(text));
            if isequal(text, self.FilterText_), return, end
            self.FilterText_ = text;
            self.applyFilter_();
        end

        function clearFilter_(self)
            % Empty the Find box and leave the focus in it, which is what the
            % operator wants next whether they reached for the button or Esc.
            if isfield(self.H,'filter') && isgraphics(self.H.filter)
                self.H.filter.Value = '';
                try
                    focus(self.H.filter);
                catch ME
                    % An invisible or already-closing window has nothing to
                    % focus, which is not a reason to leave the box uncleared.
                    vprintf(3, 'gui.ParameterDebugger: focus: %s', ME.message);
                end
            end
            if isempty(self.FilterText_), return, end
            self.FilterText_ = '';
            self.applyFilter_();
        end

        function applyFilter_(self)
            % Relist with the current filter, keeping what has already been read.
            %
            % A filter change cannot invalidate a read the way a rebuild can:
            % the parameter objects are the same objects. So the read report is
            % carried across, and narrowing the list does not throw away the
            % sweep that is usually the reason the window is open.
            if self.Refreshing_, return, end
            if ~isfield(self.H,'table') || ~isgraphics(self.H.table), return, end

            [~, ok] = self.filterPredicate_();
            self.markFilterValid_(ok);
            if ~ok
                % A half-typed pattern ("Freq[") is not an error to report,
                % only a list not worth rebuilding yet: what is shown stays
                % shown until the pattern parses again.
                self.setStatus_('Incomplete regular expression -- the list is unchanged.');
                return
            end

            self.Refreshing_ = true;
            restore = onCleanup(@() self.clearRefreshing_());

            prior = self.Rows;
            self.buildRows_(self.Interfaces_);
            self.carryOverState_(prior);
            self.renderTable_();

            clear restore
            self.updateEnableStates_();
        end

        function [fn, ok] = filterPredicate_(self)
            % The test a row's "interface / module  name" text has to pass.
            % Empty text keeps everything; a malformed pattern reports itself
            % rather than throwing, since it is almost always one still being
            % typed.
            fn = [];
            ok = true;

            txt = strtrim(self.FilterText_);
            if isempty(txt), return, end

            if self.regexOn_()
                % MATLAB's regexp does not object to a half-written pattern --
                % "Freq[" simply matches nothing -- so an unbalanced one is
                % recognised here instead. Without this, every group and class
                % typed would empty the table on its opening bracket and fill
                % it again on the closing one.
                if gui.ParameterDebugger.patternIncomplete_(txt)
                    ok = false;
                    return
                end
                try
                    regexp('', txt, 'once');
                catch
                    ok = false;
                    return
                end
                fn = @(s) ~isempty(regexpi(s, txt, 'once'));
            else
                needle = lower(txt);
                fn = @(s) contains(lower(s), needle);
            end
        end

        function tf = regexOn_(self)
            tf = isfield(self.H,'chkRegex') && isgraphics(self.H.chkRegex) && ...
                logical(self.H.chkRegex.Value);
        end

        function markFilterValid_(self, ok)
            % The Find box carries whether its own pattern parses: an amber
            % field while typing "Freq[" says more than a message would.
            if ~isfield(self.H,'filter') || ~isgraphics(self.H.filter), return, end
            if ok
                self.H.filter.BackgroundColor = [1 1 1];
            else
                self.H.filter.BackgroundColor = self.COLOR_STALE;
            end
        end

        function carryOverState_(self, prior)
            % Move the read report from the previous row list onto the new one,
            % matched on the parameter HANDLE -- the same object is the same
            % evidence. A rebuild after a config load matches nothing, because
            % those handles are gone, which is exactly what refresh promises.
            if isempty(prior) || isempty(self.Rows), return, end

            was = [prior.Parameter];
            for i = 1:numel(self.Rows)
                hit = find(was == self.Rows(i).Parameter, 1);
                if isempty(hit) || prior(hit).State == self.STATE_UNREAD, continue, end
                self.Rows(i).State     = prior(hit).State;
                self.Rows(i).ValueText = prior(hit).ValueText;
                self.Rows(i).Editable  = prior(hit).Editable;
                self.Rows(i).Note      = prior(hit).Note;
            end
        end

        function renderTable_(self)
            % Push Rows into the table, with the styles, the count, and the
            % empty-state text that belong to them. Shared by the full rebuild
            % and by a filter change so the two cannot drift apart.
            n = numel(self.Rows);
            data = cell(n, 8);
            for i = 1:n
                R = self.Rows(i);
                data(i,:) = {R.Where, R.Name, R.Type, R.Access, R.ValueText, R.Unit, R.Flags, R.Note};
            end

            self.H.table.Data = data;
            self.applyStyles_();

            hasRows = n > 0;
            self.H.table.Visible = matlab.lang.OnOffSwitchState(hasRows);
            self.H.emptyState.Visible = matlab.lang.OnOffSwitchState(~hasRows);
            if ~hasRows
                self.H.emptyState.Text = self.emptyText_();
            end

            self.updateCountLabel_();

            if hasRows
                self.setStatus_(self.listedStatus_(n));
            end
        end

        function txt = listedStatus_(self, n)
            % What the status line says after a rebuild: how much is listed,
            % and -- when a filter is responsible for the number -- how to get
            % the rest back.
            if isempty(strtrim(self.FilterText_))
                txt = sprintf(['%d parameter(s) listed. Double-click a name to read one, ' ...
                    'or Read All (F5).'], n);
            else
                txt = sprintf('%d parameter(s) match "%s". Esc clears the Find box.', ...
                    n, strtrim(self.FilterText_));
            end
        end

        function txt = emptyText_(self)
            % Why the table is empty, in the operator's terms. The cases are
            % worth distinguishing: no protocol at all, a protocol whose
            % parameters are all hidden or filtered out, and a protocol that
            % genuinely defines none.
            if isempty(self.Interfaces_)
                if isempty(self.Sources_)
                    txt = ['No protocol is loaded. Load a configuration in the session window, ' ...
                           'or open this window against a protocol directly.'];
                else
                    txt = 'The selected protocol has no hardware interfaces.';
                end
                return
            end

            if ~isempty(strtrim(self.FilterText_))
                txt = sprintf('No parameter matches "%s". Clear the Find box to see them all.', ...
                    strtrim(self.FilterText_));
            elseif self.HiddenSkipped_ > 0
                % Only offered when it would actually reveal something: an empty
                % table plus advice that changes nothing is worse than an empty
                % table.
                txt = sprintf(['No visible parameters. Tick "Show hidden" to list the %d ' ...
                               'this protocol keeps out of the GUI.'], self.HiddenSkipped_);
            else
                txt = 'This protocol defines no parameters.';
            end
        end

        function onKeyPress_(self, evt)
            % Window-level shortcuts.
            hasCtrl = any(strcmp(evt.Modifier, 'control'));

            switch evt.Key
                case 'f5'
                    self.readAll();
                case 'r'
                    if hasCtrl, self.refresh(); end
                case 'f'
                    if hasCtrl, focus(self.H.filter); end
                case 't'
                    if hasCtrl, self.trackSelected(); end
                case 'return'
                    if hasCtrl, self.readSelected(); end
                case 'escape'
                    % Esc is the way out of a search before it is the way out
                    % of the window: with the list narrowed, closing on the
                    % same key that ought to widen it again is the wrong
                    % surprise. An empty Find box still closes.
                    if ~isempty(strtrim(self.FilterText_))
                        self.clearFilter_();
                    else
                        delete(self);
                    end
            end
        end

        function onClose_(self)
            delete(self);
        end

        function openErrorLog_(self)
            % Today's log, which is where a caught read or write failure was
            % recorded in full. Delegated to the session window when there is
            % one so the operator's configured viewer applies; without a
            % session there is no such preference to honour, only the file.
            if ~isempty(self.RunExpt) && isvalid(self.RunExpt)
                self.RunExpt.OpenCurrentErrorLog();
                return
            end

            try
                L = eplog.Logger.instance();
                L.flush();
                if isempty(L.LogFile)
                    self.setStatus_('File logging is disabled for this session.');
                    return
                end
                if ispc
                    winopen(char(L.LogFile));
                else
                    open(char(L.LogFile));
                end
            catch ME
                vprintf(0, 1, ME);
                self.setStatus_(sprintf('Could not open the error log: %s', ME.message));
            end
        end

        function c = valueColumn_(self)
            % Index of the editable Value column, so the callbacks above do not
            % hardcode a number the column list can drift away from.
            c = find(strcmp(self.H.table.ColumnName, 'Value'), 1);
            if isempty(c), c = 5; end
        end

        function c = noteColumn_(self)
            c = numel(self.H.table.ColumnName);
        end

        function updateEnableStates_(self)
            % One boolean per action, copied to every surface that offers it,
            % so button, menu item, and context item cannot disagree.
            onoff = @(tf) matlab.lang.OnOffSwitchState(tf);

            rows = self.selectedRows_();
            hasRows = ~isempty(self.Rows);
            hasSel  = ~isempty(rows);
            hasTrig = false;
            if hasSel
                hasTrig = any(arrayfun(@(r) isvalid(r.Parameter) && r.Parameter.isTrigger, ...
                    self.Rows(rows)));
            end

            self.H.btnReadAll.Enable = onoff(hasRows);
            self.H.mnu_read_all.Enable = self.H.btnReadAll.Enable;

            self.H.btnReadSel.Enable = onoff(hasSel);
            self.H.mnu_read_selected.Enable = self.H.btnReadSel.Enable;
            self.H.cmnu_read.Enable = self.H.btnReadSel.Enable;

            self.H.cmnu_assign.Enable = onoff(hasSel);
            self.H.cmnu_copy.Enable = onoff(hasRows);
            self.H.mnu_copy.Enable = self.H.cmnu_copy.Enable;

            self.H.cmnu_fire.Enable = onoff(hasTrig);
            self.H.mnu_fire.Enable = self.H.cmnu_fire.Enable;

            hasPlot = false;
            if hasSel
                hasPlot = any(arrayfun(@(r) gui.ParameterTracker.isTrackable(r.Parameter), ...
                    self.Rows(rows)));
            end
            self.H.mnu_track.Enable = onoff(hasPlot);
            self.H.mnu_track_new.Enable = self.H.mnu_track.Enable;
            self.H.cmnu_track.Enable = self.H.mnu_track.Enable;

            self.H.btnClear.Enable = onoff(~isempty(self.FilterText_));
        end

        function P = trackableParameters_(self)
            % Every scalar parameter in the selected source, filter or no
            % filter: the tracker's own Add list should offer what the protocol
            % has, not what the Find box happens to be showing.
            P = hw.Parameter.empty(1,0);
            for k = 1:numel(self.Interfaces_)
                I = self.Interfaces_(k);
                if ~isvalid(I), continue, end
                M = I.Module;
                for m = 1:numel(M)
                    if ~isvalid(M(m)), continue, end
                    Q = M(m).Parameters;
                    for q = 1:numel(Q)
                        if ~isvalid(Q(q)), continue, end
                        if ~gui.ParameterTracker.isTrackable(Q(q)), continue, end
                        P(end+1) = Q(q);
                    end
                end
            end
        end

        function setStatus_(self, msg)
            if isfield(self.H,'status') && isgraphics(self.H.status)
                self.H.status.Text = msg;
            end
        end

        function updateCountLabel_(self)
            % How much is listed, and how many of the backends behind it are
            % actually connected -- the first thing to check when every value
            % looks like the design-time default.
            %
            % Recomputed after a read as well as after a rebuild: a rig that
            % dropped its connection since the window opened is exactly what a
            % sweep of failed reads is trying to tell the operator.
            if ~isfield(self.H,'countLabel') || ~isgraphics(self.H.countLabel)
                return
            end

            I = self.Interfaces_;
            if isempty(I)
                self.H.countLabel.Text = '';
                return
            end

            live = 0;
            for k = 1:numel(I)
                if ~self.isOffline_(I(k))
                    live = live + 1;
                end
            end

            self.H.countLabel.Text = sprintf('%d parameter(s)  |  %d of %d interface(s) live', ...
                numel(self.Rows), live, numel(I));
        end

        function markValue_(self, row, state, P, value, note)
            % Record an outcome that carries a new VALUE, formatting it here.
            %
            % Every path that changes what a cell shows goes through this
            % rather than through markRow_ with pre-formatted text, because
            % valueText_ returns the display text and the "can this be edited
            % in the grid" flag together, and the two must never drift apart:
            % a cell showing a "<1x100 double> ..." summary that is still
            % marked editable hands that summary back to the parser and
            % reports it as malformed text instead of as too large to edit.
            [txt, editable] = self.valueText_(P, value);
            self.Rows(row).Editable = editable;
            self.markRow_(row, state, txt, note);
        end

        function markRow_(self, row, state, valueText, note)
            % Record one row's outcome and push it to the table. Callers that
            % have a new value should use markValue_ instead.
            self.Rows(row).State = state;
            self.Rows(row).ValueText = valueText;
            self.Rows(row).Note = note;

            self.Refreshing_ = true;
            restore = onCleanup(@() self.clearRefreshing_());
            self.H.table.Data{row, self.valueColumn_()} = valueText;
            self.H.table.Data{row, self.noteColumn_()} = note;
            clear restore

            self.applyStyles_();
        end

        function clearRefreshing_(self)
            if ~isvalid(self), return, end
            self.Refreshing_ = false;
        end

        function restoreReadControls_(self)
            % Put the read controls back the way the window's own rules want
            % them after a sweep, rather than switching them all on. Guarded
            % because a sweep can outlive the window that started it.
            if ~isvalid(self) || ~isfield(self.H,'table') || ~isgraphics(self.H.table)
                return
            end
            self.updateEnableStates_();
        end

        function applyStyles_(self)
            % Repaint the whole table from Rows. One addStyle per state rather
            % than per row: styling three hundred rows one at a time is
            % visibly slow, and every read would pay for it.
            t = self.H.table;
            try
                removeStyle(t);
            catch ME
                vprintf(3, 'gui.ParameterDebugger: could not clear table styles: %s', ME.message);
            end
            if isempty(self.Rows), return, end

            % Hidden parameters are greyed across the whole row. Added first so
            % the Value-cell background below still shows: the two styles set
            % different properties and combine.
            hidden = find(~[self.Rows.Visible]);
            if ~isempty(hidden)
                addStyle(t, uistyle('FontColor', self.MUTED_COLOR), 'row', hidden);
            end

            vcol = self.valueColumn_();
            states = [self.Rows.State];
            for s = [self.STATE_OK, self.STATE_FAIL, self.STATE_WROTE, ...
                     self.STATE_STALE, self.STATE_SKIP]
                rows = find(states == s);
                if isempty(rows), continue, end
                addStyle(t, uistyle('BackgroundColor', self.stateColor_(s)), ...
                    'cell', [rows(:), repmat(vcol, numel(rows), 1)]);
            end
        end

        function c = stateColor_(self, state)
            switch state
                case self.STATE_OK,    c = self.COLOR_OK;
                case self.STATE_FAIL,  c = self.COLOR_FAIL;
                case self.STATE_WROTE, c = self.COLOR_WROTE;
                case self.STATE_STALE, c = self.COLOR_STALE;
                case self.STATE_SKIP,  c = self.COLOR_SKIP;
                otherwise,             c = [1 1 1];
            end
        end

        function stamp = timestamp_(self, iface)
            % Time of a read, with the one qualifier that changes how to read
            % the number: a disconnected backend was never asked, so the value
            % is whatever the object was last told, not what a device holds.
            stamp = char(string(datetime('now'), 'HH:mm:ss'));
            if self.isOffline_(iface)
                stamp = [stamp ' (offline)'];
            end
        end

        function tf = isOffline_(~, iface)
            % True when a backend could have been asked but was not, because it
            % is not connected. hw.Software has no device to be offline from,
            % so it never qualifies.
            tf = false;
            if isempty(iface) || ~isobject(iface) || ~isvalid(iface), return, end
            if isa(iface, 'hw.Software'), return, end
            try
                tf = ~iface.IsConnected;
            catch ME
                vprintf(3, 'gui.ParameterDebugger: %s has no connection state: %s', ...
                    class(iface), ME.message);
            end
        end
    end

    % ---- Sources -----------------------------------------------------------
    methods (Access = private)
        function sources = resolveSources_(self)
            % Every interface set this window can show.
            %
            % Resolved on every refresh rather than cached: ExptDispatch
            % replaces RunExpt.RUNTIME with a fresh object at each run, so a
            % handle captured when the window opened goes stale the moment the
            % operator presses Run.
            rx = self.RunExpt;
            haveRx = ~isempty(rx) && isvalid(rx);

            nMax = 1;
            if haveRx, nMax = nMax + numel(rx.CONFIG) + 1; end
            sources = repmat(struct('Label','', 'Interfaces', hw.Interface.empty(1,0)), 1, nMax);
            n = 0;

            if ~isempty(self.Seed_)
                n = n + 1;
                sources(n).Label = 'Supplied source';
                sources(n).Interfaces = self.interfacesOf_(self.Seed_);
            end

            if ~haveRx
                sources = sources(1:n);
                return
            end

            live = hw.Interface.empty(1,0);
            try
                live = rx.RUNTIME.Interfaces;
            catch ME
                vprintf(3, 'gui.ParameterDebugger: no runtime interfaces yet: %s', ME.message);
            end

            liveShown = false;
            for i = 1:numel(rx.CONFIG)
                P = rx.CONFIG(i).PROTOCOL;
                if ~isa(P, 'epsych.Protocol') || ~isvalid(P), continue, end

                suffix = '';
                if ~isempty(live) && self.sameInterfaces_(live, P.Interfaces)
                    suffix = ' - live';
                    liveShown = true;
                end

                n = n + 1;
                sources(n).Label = sprintf('%d: %s%s', i, ...
                    self.subjectLabel_(rx.CONFIG(i)), suffix);
                sources(n).Interfaces = P.Interfaces;
            end

            % A live run whose interfaces did not come from any listed protocol
            % still has to be reachable -- that is exactly the case worth
            % debugging.
            if ~isempty(live) && ~liveShown
                n = n + 1;
                sources(n).Label = 'Live session';
                sources(n).Interfaces = live;
            end

            sources = sources(1:n);
        end

        function name = subjectLabel_(~, C)
            % "Name (box N)" for a config entry, degrading to whatever is set.
            name = 'subject';
            try
                if isa(C.SUBJECT, 'epsych.Subject') && isvalid(C.SUBJECT)
                    name = char(C.SUBJECT.Name);
                    if isempty(name), name = 'subject'; end
                    name = sprintf('%s (box %d)', name, C.SUBJECT.BoxID);
                end
            catch ME
                vprintf(3, 'gui.ParameterDebugger: could not label a subject: %s', ME.message);
            end
        end

        function I = interfacesOf_(~, source)
            % Interfaces from anything that has them: an interface array as
            % given, or the Interfaces property of a Runtime or a Protocol.
            I = hw.Interface.empty(1,0);
            if isa(source, 'hw.Interface')
                I = source;
                return
            end
            if isobject(source) && isprop(source, 'Interfaces')
                try
                    I = source.Interfaces;
                catch ME
                    vprintf(2, 'gui.ParameterDebugger: could not read Interfaces: %s', ME.message);
                end
            end
        end

        function tf = sameInterfaces_(~, a, b)
            tf = false;
            try
                tf = ~isempty(a) && numel(a) == numel(b) && ...
                    all(arrayfun(@(k) a(k) == b(k), 1:numel(a)));
            catch ME
                vprintf(3, 'gui.ParameterDebugger: could not compare interfaces: %s', ME.message);
            end
        end
    end

    % ---- Rows --------------------------------------------------------------
    methods (Access = private)
        function buildRows_(self, interfaces)
            % One record per parameter the table will show, in interface then
            % module then declaration order -- the order the protocol defines
            % them in, which is the order the designer shows and the order a
            % person reading a circuit expects.
            showHidden = logical(self.H.chkHidden.Value);
            match = self.filterPredicate_();

            keep = self.collectParameters_(interfaces, showHidden, match);
            if isempty(keep)
                self.Rows = [];
                return
            end

            R = repmat(self.blankRow_(keep(1).Parameter, keep(1).Interface, keep(1).Where), ...
                1, numel(keep));
            for i = 2:numel(keep)
                R(i) = self.blankRow_(keep(i).Parameter, keep(i).Interface, keep(i).Where);
            end
            self.Rows = R;
        end

        function keep = collectParameters_(self, interfaces, showHidden, match)
            % Walk interface -> module -> parameter once, collecting what
            % passes the visibility and filter tests. Counted first so the row
            % array is built at its final size.
            nMax = 0;
            for k = 1:numel(interfaces)
                if ~isvalid(interfaces(k)), continue, end
                M = interfaces(k).Module;
                for m = 1:numel(M)
                    if ~isvalid(M(m)), continue, end
                    nMax = nMax + numel(M(m).Parameters);
                end
            end

            keep = repmat(struct('Parameter', [], 'Interface', [], 'Where', ''), 1, max(nMax,1));
            n = 0;
            self.HiddenSkipped_ = 0;

            for k = 1:numel(interfaces)
                I = interfaces(k);
                if ~isvalid(I), continue, end
                ifaceName = self.interfaceLabel_(I);

                M = I.Module;
                for m = 1:numel(M)
                    if ~isvalid(M(m)), continue, end
                    where = sprintf('%s / %s', ifaceName, self.moduleLabel_(M(m), m));

                    P = M(m).Parameters;
                    for p = 1:numel(P)
                        if ~isvalid(P(p)), continue, end
                        if ~P(p).Visible && ~showHidden
                            self.HiddenSkipped_ = self.HiddenSkipped_ + 1;
                            continue
                        end
                        if ~isempty(match) && ~match([where ' ' P(p).Name])
                            continue
                        end

                        n = n + 1;
                        keep(n).Parameter = P(p);
                        keep(n).Interface = I;
                        keep(n).Where = where;
                    end
                end
            end

            keep = keep(1:n);
        end

        function row = blankRow_(self, P, I, where)
            % A row as it looks before anything has been read.
            [txt, editable] = self.valueText_(P, self.freeValue_(P, I));

            row = struct( ...
                'Parameter', P, ...
                'Interface', I, ...
                'Name',      P.Name, ...
                'Where',     where, ...
                'Type',      P.Type, ...
                'Access',    P.Access, ...
                'Unit',      P.Unit, ...
                'Flags',     self.flagText_(P), ...
                'Visible',   P.Visible, ...
                'ValueText', txt, ...
                'Editable',  editable, ...
                'State',     self.STATE_UNREAD, ...
                'Note',      '');
        end

        function v = freeValue_(self, P, I)
            % The value already held in the object, but only when getting it
            % costs nothing.
            %
            % hw.Parameter.get.Value goes to the backend whenever the parent is
            % connected, so reading every parameter here would put a full
            % hardware sweep behind merely opening the window -- and would log
            % a critical record for every write-only parameter listed. When the
            % read is not free the cell stays blank and unread, which is the
            % honest state until the operator asks.
            v = [];
            if strcmp(P.Access, 'Write'), return, end
            if ~(strcmp(P.Type, 'StimType') || isa(I, 'hw.Software') || self.isOffline_(I))
                return
            end
            try
                v = P.Value;
            catch ME
                vprintf(3, 'gui.ParameterDebugger: could not read "%s": %s', P.Name, ME.message);
            end
        end

        function s = flagText_(~, P)
            % The properties that explain why a parameter behaves as it does --
            % the answer to "I wrote it and it went back", which is usually
            % "expr" or "per-trial".
            f = strings(1,0);
            if ~P.Visible,                  f(end+1) = "hidden";   end
            if P.isTrigger,                 f(end+1) = "trigger";  end
            if P.isArray,                   f(end+1) = "array";    end
            if P.isRandom,                  f(end+1) = "random";   end
            if strlength(P.Expression) > 0, f(end+1) = "expr";     end
            if P.SetOnce,                   f(end+1) = "set-once"; end
            if numel(P.Values) > 1 && P.UpdateEveryTrial
                f(end+1) = "per-trial";
            end
            s = char(strjoin(f, ', '));
        end

        function name = interfaceLabel_(~, I)
            % Type is what the designer and the protocol file call a backend;
            % the class name is the fallback for one that does not set it.
            name = '';
            try
                name = char(string(I.Type));
            catch ME
                vprintf(3, 'gui.ParameterDebugger: interface has no Type: %s', ME.message);
            end
            if isempty(name)
                name = strrep(class(I), 'hw.', '');
            end
        end

        function name = moduleLabel_(~, M, idx)
            name = M.Name;
            if isempty(name), name = M.Label; end
            if isempty(name), name = sprintf('module %d', idx); end
        end
    end

    % ---- Values ------------------------------------------------------------
    methods (Access = private)
        function [value, ok, why] = parseValue_(self, P, text)
            % Turn typed text into a value of the parameter's type.
            %
            % Numeric text is evaluated with str2num so ranges and arithmetic
            % work ("0:0.1:1", "2*10"), but only after the text is checked
            % against a numeric-literal pattern. str2num is eval, and this
            % window is pointed at live hardware: a cell that could run
            % arbitrary code would be a trap, not a convenience.
            value = [];
            ok = false;
            why = '';

            switch P.Type
                case 'Boolean'
                    [value, ok] = self.parseBoolean_(text);
                    if ~ok, why = 'expected true/false, 1/0, or on/off'; end

                case {'String','File'}
                    value = text;
                    ok = true;

                case 'StimType'
                    why = ['a stimulus cannot be typed in; edit it in the ' ...
                           'Protocol Designer or the Stimulus Player'];

                otherwise
                    if isempty(text)
                        why = 'no value given';
                        return
                    end
                    % The whitelist is applied FIRST, to every numeric path.
                    % str2double is not a safety net of its own: it happily
                    % returns a complex number for "3i" and +/-Inf for "inf",
                    % neither of which any backend here can send, so letting it
                    % answer before the pattern check would put values on the
                    % wire that the pattern exists to keep off.
                    if isempty(regexp(text, '^[\[\]\(\)\s0-9eE\.\,\;\+\-\:\*\/]+$', 'once'))
                        why = 'not a number, an array literal, or an arithmetic expression';
                        return
                    end
                    scalar = str2double(text);
                    if ~isnan(scalar)
                        value = scalar;
                    else
                        try
                            value = str2num(text); %#ok<ST2NM> accepting "0:0.1:1" is the point
                        catch ME
                            why = ME.message;
                            return
                        end
                        if isempty(value)
                            why = 'could not be read as a number';
                            return
                        end
                    end

                    % The pattern keeps identifiers out; it cannot keep out
                    % what arithmetic on digits alone can still produce.
                    % "1e999" overflows to Inf and "(-1)^0.5" is complex, and
                    % no backend here can send either -- a complex value would
                    % be silently truncated somewhere downstream rather than
                    % refused. Checking the result, not the text, catches both.
                    [value, ok, why] = self.checkNumericResult_(value);
            end
        end

        function [value, ok, why] = checkNumericResult_(~, value)
            % Accept only a real, finite numeric value to send to hardware.
            ok = false;
            why = '';
            if ~isnumeric(value)
                why = 'did not evaluate to a number';
            elseif ~isreal(value)
                why = 'is complex; hardware parameters take real values';
            elseif ~all(isfinite(value(:)))
                why = 'is not finite';
            else
                ok = true;
            end
        end

        function [value, ok] = parseBoolean_(~, text)
            value = false;
            ok = true;
            switch lower(strtrim(text))
                case {'1','true','on','yes','t','y'},  value = true;
                case {'0','false','off','no','f','n'}, value = false;
                otherwise, ok = false;
            end
        end

        function [txt, editable] = valueText_(self, P, v)
            % Value as a literal the operator can edit and this window can read
            % back, or -- when it cannot be one -- as a summary marked
            % uneditable.
            %
            % hw.Parameter.ValueStr is deliberately not used: it re-reads the
            % parameter (a second hardware round trip per row), appends the
            % unit, which has its own column here, and truncates arrays, so
            % what it shows could not be typed back in.
            editable = true;

            if isempty(v)
                txt = '';
                return
            end

            if ischar(v) || isstring(v)
                txt = char(strjoin(string(v), ' '));
                return
            end

            if islogical(v)
                if isscalar(v)
                    txt = char(string(v));
                    return
                end
                v = double(v);
            end

            % A Boolean parameter reads back as a double on most backends;
            % showing it as true/false keeps the cell symmetric with what
            % parseValue_ accepts. Only an exact 0 or 1 is translated, so a
            % Boolean that comes back as something else stays visible as the
            % number it is rather than being rounded into a word.
            if strcmp(P.Type, 'Boolean') && isnumeric(v) && isscalar(v) && (v == 0 || v == 1)
                txt = char(string(logical(v)));
                return
            end

            if isa(v, 'stimgen.StimType')
                editable = false;
                if isscalar(v)
                    txt = sprintf('<%s>', class(v));
                else
                    txt = sprintf('<%d x %s>', numel(v), class(v));
                end
                return
            end

            if isnumeric(v)
                if isscalar(v)
                    txt = num2str(v, '%.10g');
                elseif isvector(v) && numel(v) <= self.MAX_INLINE_ELEMENTS
                    txt = mat2str(v, 10);
                else
                    editable = false;
                    txt = sprintf('<%s %s> %s...', ...
                        char(strjoin(string(size(v)), 'x')), class(v), ...
                        num2str(reshape(v(1:min(4,numel(v))), 1, []), '%.4g '));
                end
                return
            end

            editable = false;
            txt = sprintf('<%s>', class(v));
        end

        function tf = isBulk_(self, P)
            tf = ismember(P.Type, self.BULK_TYPES);
        end
    end

    methods (Static, Access = private)
        function tf = patternIncomplete_(txt)
            % Whether a regular expression is one still being typed: an open
            % group, an open character class, an open quantifier, or a
            % trailing backslash. Not a validator -- MATLAB's own regexp
            % accepts far more than this rejects -- only the four states a
            % pattern passes THROUGH on the way to being written, which are
            % the ones a live filter must not act on.
            esc = false;
            inClass = false;
            depth = 0;
            brace = false;

            for k = 1:numel(txt)
                if esc
                    esc = false;
                    continue
                end
                switch txt(k)
                    case '\'
                        esc = true;
                    case '['
                        inClass = true;
                    case ']'
                        inClass = false;
                    case '('
                        if ~inClass, depth = depth + 1; end
                    case ')'
                        if ~inClass, depth = max(0, depth - 1); end
                    case '{'
                        if ~inClass, brace = true; end
                    case '}'
                        brace = false;
                end
            end

            tf = esc || inClass || depth > 0 || brace;
        end
    end
end
