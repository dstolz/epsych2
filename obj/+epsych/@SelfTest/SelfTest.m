classdef SelfTest < handle
    % epsych.SelfTest
    % Pre-flight diagnostics for an epsych.RunExpt session.
    %
    % Runs real checks against the currently loaded session — compiling
    % protocols, exercising the trial selector, writing and reading back data
    % files, probing hardware — and returns one result per check with an
    % actionable remedy. Almost every RunExpt failure mode otherwise surfaces
    % mid-session; this converts them into pre-flight failures.
    %
    % Checks are grouped; a group is a method returning a struct array of
    % results. Groups tagged mutating touch live state (hardware connections,
    % the behavior GUI, the main window's control states) and are opt-in.
    %
    % Important properties:
    %   RunExpt              - The epsych.RunExpt instance under test.
    %   Verbosity              - GVerbosity level forced while checks run (default 3).
    %   IncludeHardwareConnect - Opt in to connecting hardware interfaces.
    %   IncludeBehaviorGUI     - Opt in to launching the configured behavior GUI.
    %   IncludeGuiStateCycle   - Opt in to cycling the main window's STATE.
    %
    % Key methods:
    %   run          - Execute selected groups and return results.
    %   catalog      - Group registry (id, label, method, mutating).
    %   formatReport - Render results as plain text.
    %   saveReport   - Write the plain-text report to disk.
    %
    % Usage:
    %   st  = epsych.SelfTest(RunExptInstance);
    %   res = st.run();
    %   disp(st.formatReport(res))
    %
    % See also: epsych.RunExpt, gui.SelfTest, hw.Interface.selfTest,
    %   documentation/overviews/RunExpt_SelfTest.md

    properties
        Verbosity (1,1) double {mustBeInteger,mustBeNonnegative} = 3  % GVerbosity level forced for the duration of a run
        IncludeHardwareConnect (1,1) logical = false  % Connect each hw.Interface and run its invasive selfTest
        IncludeBehaviorGUI (1,1) logical = false      % Launch FUNCS.BehaviorGUI against a synthetic Runtime
        IncludeGuiStateCycle (1,1) logical = false    % Drive STATE through each PRGMSTATE and assert control states
    end

    properties (SetAccess = private)
        RunExpt  % epsych.RunExpt instance under test
    end

    properties (Constant)
        % Statuses, ordered most to least severe. Ordering drives group rollup
        % and the report summary.
        STATUSES = ["fail","warn","pass","info","skip"]
    end

    methods
        results = run(self, groupIds)         % Execute selected groups; returns a result struct array
        txt = formatReport(self, results)     % Render results as plain text
        ffn = saveReport(self, results, ffn)  % Write the plain-text report to disk

        function self = SelfTest(runExpt, opts)
            % self = epsych.SelfTest(runExpt)
            % self = epsych.SelfTest(runExpt, Name=Value)
            % Create a self-test engine bound to a RunExpt session.
            %
            % Parameters:
            %	runExpt	- epsych.RunExpt instance to test. Omit to test the
            %	          active session window, if one is open.
            %	Name-Value options:
            %		Verbosity              - GVerbosity level forced while running (default 3).
            %		IncludeHardwareConnect - Connect hardware interfaces (default false).
            %		IncludeBehaviorGUI     - Launch the behavior GUI (default false).
            %		IncludeGuiStateCycle   - Cycle the main window STATE (default false).
            %
            % Returns:
            %	self	- Configured epsych.SelfTest instance.
            arguments
                runExpt = epsych.SelfTest.findActiveRunExpt()
                opts.Verbosity (1,1) double {mustBeInteger,mustBeNonnegative} = 3
                opts.IncludeHardwareConnect (1,1) logical = false
                opts.IncludeBehaviorGUI (1,1) logical = false
                opts.IncludeGuiStateCycle (1,1) logical = false
            end

            if ~isempty(runExpt) && ~isa(runExpt,'epsych.RunExpt')
                error('epsych:SelfTest:InvalidTarget', ...
                    'Expected an epsych.RunExpt instance; got %s.', class(runExpt));
            end

            self.RunExpt = runExpt;
            self.Verbosity = opts.Verbosity;
            self.IncludeHardwareConnect = opts.IncludeHardwareConnect;
            self.IncludeBehaviorGUI = opts.IncludeBehaviorGUI;
            self.IncludeGuiStateCycle = opts.IncludeGuiStateCycle;
        end
    end

    methods (Access = private)
        % One method per group; each returns a struct array of results.
        results = checkEnvironment(self)
        results = checkFunctions(self)
        results = checkTimer(self)
        results = checkConfig(self)
        results = checkProtocol(self)
        results = checkTrialSelection(self)
        results = checkHardware(self)
        results = checkDataSaving(self)
        results = checkGui(self)
    end

    methods (Static)
        function C = catalog()
            % C = epsych.SelfTest.catalog()
            % Return the group registry: id, label, method name, and whether the
            % group can mutate live state. Order is execution order — cheap and
            % safe groups first so an early failure is visible before anything
            % slow or invasive runs.
            %
            % Returns:
            %   C - struct array with fields id, label, method, mutating.
            C = struct( ...
                'id',       {"Environment","Functions","Timer","Config","Protocol","TrialSelection","Hardware","DataSaving","Gui"}, ...
                'label',    {"Environment & installation","Callback functions","Timer", ...
                             "Config & subjects","Protocol","Trial selection", ...
                             "Hardware & connections","Data saving","GUI wiring & state"}, ...
                'method',   {"checkEnvironment","checkFunctions","checkTimer","checkConfig", ...
                             "checkProtocol","checkTrialSelection","checkHardware", ...
                             "checkDataSaving","checkGui"}, ...
                'mutating', {false,false,false,false,false,false,true,false,true});
        end

        function r = result(id, group, name, status, summary, opts)
            % r = epsych.SelfTest.result(id, group, name, status, summary)
            % r = epsych.SelfTest.result(..., Detail=..., Remedy=..., Mutating=true)
            % Build one result. Called with no arguments, returns the empty
            % prototype so checks can seed an accumulator.
            %
            % Parameters:
            %   id      - Stable identifier, e.g. "E4_CoreTriggers".
            %   group   - Group id from catalog().
            %   name    - Human-readable check name.
            %   status  - 'pass' | 'fail' | 'warn' | 'info' | 'skip'.
            %   summary - One-line result.
            %   opts.Detail   - Additional lines for the detail pane.
            %   opts.Remedy   - Actionable fix; expected when status is fail/warn.
            %   opts.Mutating - True when the check changed live state.
            %
            % Returns:
            %   r - 1x1 result struct, or a 0x0 empty struct array with the same
            %       fields when called with no arguments.
            arguments
                id (1,1) string = ""
                group (1,1) string = ""
                name (1,1) string = ""
                status (1,1) string {mustBeMember(status,["pass","fail","warn","info","skip",""])} = ""
                summary (1,1) string = ""
                opts.Detail (1,:) string = strings(1,0)
                opts.Remedy (1,1) string = ""
                opts.Mutating (1,1) logical = false
            end

            if nargin == 0
                r = struct('id',{},'group',{},'name',{},'status',{},'summary',{}, ...
                    'detail',{},'remedy',{},'seconds',{},'mutating',{});
                return
            end

            r = struct( ...
                'id',       id, ...
                'group',    group, ...
                'name',     name, ...
                'status',   status, ...
                'summary',  summary, ...
                'detail',   {opts.Detail}, ...
                'remedy',   opts.Remedy, ...
                'seconds',  0, ...
                'mutating', opts.Mutating);
        end

        function r = withTime(r, seconds)
            % r = epsych.SelfTest.withTime(r, seconds)
            % Stamp an elapsed time onto every result produced by one timed
            % block. Used by group methods so the report can show which checks
            % are slow (a slow disk or a slow trial selector is itself a finding).
            arguments
                r struct
                seconds (1,1) double
            end
            for i = 1:numel(r)
                r(i).seconds = seconds / max(1, numel(r));
            end
        end

        function rx = findActiveRunExpt()
            % rx = epsych.SelfTest.findActiveRunExpt()
            % Return the live epsych.RunExpt behind the open session window, or
            % [] when no session is open. Mirrors the reuse lookup performed by
            % the epsych.RunExpt constructor.
            rx = [];
            f = findall(groot,'Type','figure','-and','Tag','RunExpt');
            for i = 1:numel(f)
                if ~isgraphics(f(i)), continue, end
                candidate = f(i).UserData;
                if isa(candidate,'epsych.RunExpt') && isvalid(candidate) && ~candidate.IsClosing
                    rx = candidate;
                    return
                end
            end
        end

        function s = rollup(results)
            % s = epsych.SelfTest.rollup(results)
            % Count results by status.
            %
            % Returns:
            %   s - struct with one count per epsych.SelfTest.STATUSES entry,
            %       plus 'total' and 'seconds'.
            s = struct();
            for st = epsych.SelfTest.STATUSES
                s.(st) = 0;
            end
            s.total = numel(results);
            s.seconds = 0;

            for i = 1:numel(results)
                st = string(results(i).status);
                if isfield(s, st)
                    s.(st) = s.(st) + 1;
                end
                s.seconds = s.seconds + results(i).seconds;
            end
        end
    end
end
