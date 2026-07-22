classdef SelfTest < handle
    % gui.SelfTest
    % Window for running epsych.SelfTest against a live RunExpt session.
    %
    % Presents the check groups as a checkbox tree, runs the selected ones,
    % and shows one row per check colour-coded by status. Selecting a row
    % reveals its detail lines and the remedy for a failure, which is the
    % point of the window: a red row that does not say what to do about it is
    % no more useful than a stack trace.
    %
    % Groups that mutate live state (connecting hardware, launching the box
    % GUI, cycling the window's control states) are opt-in via the checkboxes
    % in the toolbar and are refused outright while a session is running.
    %
    % Usage:
    %   gui.SelfTest(RunExptInstance)   % normally via Help > Run Self-Test...
    %
    % See also: epsych.SelfTest, epsych.RunExpt.OpenSelfTest,
    %   documentation/overviews/RunExpt_SelfTest.md

    properties (SetAccess = private)
        Engine   % epsych.SelfTest instance driving the checks
        Results  % Most recent result struct array
        H        % Handles to UI components
    end

    properties (Constant, Access = private)
        FIGURE_TAG = 'RunExptSelfTest'

        % Row tints. Deliberately pale: the status word carries the meaning,
        % the colour only makes the failures findable by eye.
        COLOR_FAIL = [1.00 0.88 0.88]
        COLOR_WARN = [1.00 0.96 0.85]
        COLOR_PASS = [0.90 0.97 0.90]
        COLOR_SKIP = [0.94 0.94 0.94]
        COLOR_INFO = [0.92 0.95 1.00]
    end

    methods
        buildUI(self)                % Build the window and all controls
        runSelected(self, groupIds)  % Run the given groups and refresh the display

        function self = SelfTest(runExpt)
            % self = gui.SelfTest(runExpt)
            % Open the self-test window for a RunExpt session.
            %
            % Parameters:
            %	runExpt	- epsych.RunExpt instance to test. Omit to bind to the
            %	          active session window, if one is open.
            %
            % Returns:
            %	self	- gui.SelfTest instance.
            arguments
                runExpt = epsych.SelfTest.findActiveRunExpt()
            end

            % Single instance: a second window would run checks against the
            % same session concurrently, and the mutating ones would collide.
            existing = findall(groot, 'Type', 'figure', 'Tag', gui.SelfTest.FIGURE_TAG);
            for i = 1:numel(existing)
                ud = existing(i).UserData;
                existing(i).UserData = [];
                existing(i).CloseRequestFcn = '';
                delete(existing(i));
                if isa(ud, 'gui.SelfTest') && isvalid(ud)
                    delete(ud);
                end
            end

            self.Engine = epsych.SelfTest(runExpt);
            self.Results = epsych.SelfTest.result();

            self.buildUI;

            if nargout == 0, clear self; end
        end

        function delete(self)
            % delete(self)
            % Close the window when the object is destroyed.
            if isfield(self.H, 'figure') && isgraphics(self.H.figure)
                f = self.H.figure;
                f.UserData = [];
                f.CloseRequestFcn = '';
                delete(f);
            end
        end
    end

    methods (Access = private)
        function onClose(self)
            % Tear down the window and this object together.
            delete(self);
        end

        function onRunAll(self)
            % Run every group, ticking all of them in the tree first so the
            % selection reflects what was actually run.
            C = epsych.SelfTest.catalog();
            self.H.tree.CheckedNodes = self.H.groupNodes;
            self.runSelected([C.id]);
        end

        function onRunSelected(self)
            % Run only the ticked groups.
            checked = self.H.tree.CheckedNodes;
            if isempty(checked)
                uialert(self.H.figure, 'Tick at least one group to run.', 'Self-Test', 'Icon', 'info');
                return
            end

            ids = strings(1,0);
            for i = 1:numel(checked)
                nd = checked(i);
                if ~isempty(nd.NodeData)
                    ids(end+1) = string(nd.NodeData);
                end
            end
            self.runSelected(unique(ids, 'stable'));
        end

        function onSelectionChanged(self, evt)
            % Show the selected check's detail lines and remedy.
            idx = evt.Selection;
            if isempty(idx) || isempty(self.Results)
                self.H.detail.Value = {''};
                return
            end

            r = self.Results(idx(1));
            lines = { ...
                sprintf('%s  -  %s', upper(r.status), r.name), ...
                sprintf('Group: %s    Check: %s    %.3f s', r.group, r.id, r.seconds), ...
                '', ...
                char(r.summary)};

            if ~isempty(r.detail)
                lines{end+1} = '';
                lines{end+1} = 'Details:';
                for d = r.detail
                    lines{end+1} = ['  ' char(d)];
                end
            end

            if strlength(r.remedy) > 0
                lines{end+1} = '';
                lines{end+1} = 'What to do:';
                lines{end+1} = ['  ' char(r.remedy)];
            end

            self.H.detail.Value = lines;
        end

        function onCopyReport(self)
            % Put the plain-text report on the clipboard.
            if isempty(self.Results)
                uialert(self.H.figure, 'Run the checks first.', 'Self-Test', 'Icon', 'info');
                return
            end
            clipboard('copy', self.Engine.formatReport(self.Results));
            self.setStatus('Report copied to the clipboard.');
        end

        function onSaveReport(self)
            % Write the plain-text report beside the daily error log.
            if isempty(self.Results)
                uialert(self.H.figure, 'Run the checks first.', 'Self-Test', 'Icon', 'info');
                return
            end

            try
                ffn = self.Engine.saveReport(self.Results);
                self.setStatus(sprintf('Report saved: %s', ffn));
            catch ME
                vprintf(0, 1, ME);
                uialert(self.H.figure, sprintf('Could not save the report:\n\n%s', ME.message), ...
                    'Self-Test', 'Icon', 'error');
            end
        end

        function onOpenLog(self)
            % Open today's error log, which holds the full run-by-run detail.
            logPath = fullfile(epsych_path, '.error_logs', ...
                sprintf('error_log_%s.txt', datestr(now,'ddmmmyyyy')));
            if ~isfile(logPath)
                self.setStatus(sprintf('No log yet at %s', logPath));
                return
            end

            try
                winopen(logPath);
                self.setStatus(sprintf('Opened %s', logPath));
            catch ME
                vprintf(0, 1, ME);
                self.setStatus(sprintf('Could not open the log; it is at %s', logPath));
            end
        end

        function onVerbosityChanged(self)
            % Apply the chosen verbosity to the engine.
            self.Engine.Verbosity = self.H.verbosity.Value;
        end

        function onOptionChanged(self)
            % Mirror the opt-in checkboxes onto the engine.
            self.Engine.IncludeHardwareConnect = self.H.optConnect.Value;
            self.Engine.IncludeBoxFig          = self.H.optBoxFig.Value;
            self.Engine.IncludeGuiStateCycle   = self.H.optStateCycle.Value;
        end

        function setStatus(self, txt)
            % Update the footer message.
            if isfield(self.H, 'status') && isgraphics(self.H.status)
                self.H.status.Text = txt;
            end
        end

        function color = statusColor(self, status)
            % Row tint for one status.
            switch string(status)
                case "fail", color = self.COLOR_FAIL;
                case "warn", color = self.COLOR_WARN;
                case "pass", color = self.COLOR_PASS;
                case "info", color = self.COLOR_INFO;
                otherwise,   color = self.COLOR_SKIP;
            end
        end
    end
end
