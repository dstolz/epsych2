classdef TrialWindow
    % w = psychophysics.TrialWindow(mode, arg)
    % Immutable description of which trials an analysis should use.
    %
    % A TrialWindow is a small value object naming a contiguous span of the
    % trial record: every trial, the last N, the first N, or an explicit
    % range. Analyses resolve it against their own trial count, so the same
    % window object stays meaningful as a session grows.
    %
    % Windows are usually built from the shorthand accepted by parse rather
    % than the constructor, so a caller can write the window the way they
    % would say it:
    %
    %   psychophysics.TrialWindow.parse("all")        % every trial
    %   psychophysics.TrialWindow.parse(50)           % the last 50 trials
    %   psychophysics.TrialWindow.parse([20 100])     % trials 20 through 100
    %   psychophysics.TrialWindow.parse("last 20")
    %   psychophysics.TrialWindow.parse("first 10")
    %   psychophysics.TrialWindow.parse("20-100")     % also "20:100"
    %
    % Properties:
    %   Mode  - "All", "Last", "First", or "Range"
    %   N     - Trial count for the "Last" and "First" modes
    %   Range - [first last] trial numbers for "Range"; last may be Inf
    %
    % Methods:
    %   resolve  - 1-based trial indices selected from a given trial count
    %   describe - Human-readable window description ("Last 20 trials")
    %   label    - Description plus the resolved span ("Last 20 trials (28-47)")
    %   toStruct / fromStruct - Round trip for getpref/setpref persistence
    %
    % Example:
    %   w = psychophysics.TrialWindow.lastN(20);
    %   idx = w.resolve(47);        % 28:47
    %   disp(w.label(47))           % Last 20 trials (28-47)
    %
    % See also: psychophysics.SessionMetrics, gui.components.SessionPerformance,
    % documentation/psychophysics/psychophysics_SessionMetrics.md

    properties (SetAccess = immutable)
        Mode (1,1) string {mustBeMember(Mode,["All","Last","First","Range"])} = "All"  % Window kind
        N (1,1) double = 0                  % Trial count used by the "Last"/"First" modes
        Range (1,2) double = [1 Inf]        % [first last] trial numbers used by "Range"
    end

    methods
        function obj = TrialWindow(mode, arg)
            % w = psychophysics.TrialWindow()             % all trials
            % w = psychophysics.TrialWindow("Last", 20)
            % w = psychophysics.TrialWindow("First", 10)
            % w = psychophysics.TrialWindow("Range", [20 100])
            %
            % Parameters:
            %   mode - "All", "Last", "First", or "Range". Default "All".
            %   arg  - Trial count for "Last"/"First", or [first last] for "Range".
            arguments
                mode (1,1) string {mustBeMember(mode,["All","Last","First","Range"])} = "All"
                arg double = []
            end

            obj.Mode = mode;

            switch mode
                case {"Last","First"}
                    if isempty(arg)
                        error('psychophysics:TrialWindow:MissingCount', ...
                            'The "%s" window requires a trial count.', mode);
                    end
                    obj.N = psychophysics.TrialWindow.validateCount_(arg);

                case "Range"
                    if numel(arg) ~= 2
                        error('psychophysics:TrialWindow:InvalidRange', ...
                            'The "Range" window requires [first last] trial numbers.');
                    end
                    obj.Range = psychophysics.TrialWindow.validateRange_(arg);
            end
        end

        function idx = resolve(obj, nTrials)
            % idx = resolve(obj, nTrials)
            % Trial indices selected from a record of nTrials trials.
            %
            % Parameters:
            %   nTrials - Number of trials available.
            %
            % Returns:
            %   idx - Ascending row vector of 1-based trial indices, empty
            %         when the window falls outside the available trials.
            arguments
                obj (1,1) psychophysics.TrialWindow
                nTrials (1,1) double {mustBeNonnegative, mustBeInteger}
            end

            idx = zeros(1,0);
            if nTrials == 0, return; end

            switch obj.Mode
                case "All"
                    lo = 1;                          hi = nTrials;
                case "Last"
                    lo = max(1, nTrials - obj.N + 1); hi = nTrials;
                case "First"
                    lo = 1;                          hi = min(nTrials, obj.N);
                case "Range"
                    lo = max(1, floor(obj.Range(1)));
                    hi = min(nTrials, floor(obj.Range(2)));
            end

            if hi >= lo, idx = lo:hi; end
        end

        function s = describe(obj)
            % s = describe(obj)
            % Human-readable window description, independent of trial count.
            switch obj.Mode
                case "All"
                    s = "All trials";
                case "Last"
                    s = sprintf("Last %d trials", obj.N);
                case "First"
                    s = sprintf("First %d trials", obj.N);
                case "Range"
                    if isinf(obj.Range(2))
                        s = sprintf("Trials %d+", obj.Range(1));
                    else
                        s = sprintf("Trials %d-%d", obj.Range(1), obj.Range(2));
                    end
            end
        end

        function s = label(obj, nTrials)
            % s = label(obj, nTrials)
            % Description plus the span it resolves to, for display headers.
            % A window that selects nothing is reported as such rather than
            % silently showing an empty span.
            arguments
                obj (1,1) psychophysics.TrialWindow
                nTrials (1,1) double {mustBeNonnegative, mustBeInteger} = 0
            end

            idx = obj.resolve(nTrials);
            if isempty(idx)
                if nTrials == 0
                    s = obj.describe();
                else
                    s = sprintf("%s (no trials in window)", obj.describe());
                end
                return
            end

            if obj.Mode == "All"
                s = sprintf("%s (1-%d)", obj.describe(), idx(end));
            else
                s = sprintf("%s (%d-%d)", obj.describe(), idx(1), idx(end));
            end
        end

        function s = toStruct(obj)
            % s = toStruct(obj)
            % Plain struct form for getpref/setpref persistence.
            s = struct('Mode', char(obj.Mode), 'N', obj.N, 'Range', obj.Range);
        end
    end

    methods (Static)
        function w = allTrials()
            % w = psychophysics.TrialWindow.allTrials()
            w = psychophysics.TrialWindow("All");
        end

        function w = lastN(n)
            % w = psychophysics.TrialWindow.lastN(n)
            w = psychophysics.TrialWindow("Last", n);
        end

        function w = firstN(n)
            % w = psychophysics.TrialWindow.firstN(n)
            w = psychophysics.TrialWindow("First", n);
        end

        function w = range(firstTrial, lastTrial)
            % w = psychophysics.TrialWindow.range(firstTrial, lastTrial)
            % lastTrial may be Inf, meaning "through the end of the session".
            arguments
                firstTrial (1,1) double
                lastTrial (1,1) double = Inf
            end
            w = psychophysics.TrialWindow("Range", [firstTrial lastTrial]);
        end

        function w = fromStruct(s)
            % w = psychophysics.TrialWindow.fromStruct(s)
            % Rebuild a window from toStruct output (e.g. a saved preference).
            % An unrecognized struct yields the all-trials window rather than
            % an error, so a stale preference cannot block a GUI from opening.
            w = psychophysics.TrialWindow.allTrials();
            if ~isstruct(s) || ~isfield(s,'Mode'), return; end
            try
                switch string(s.Mode)
                    case "Last",  w = psychophysics.TrialWindow("Last", s.N);
                    case "First", w = psychophysics.TrialWindow("First", s.N);
                    case "Range", w = psychophysics.TrialWindow("Range", s.Range);
                end
            catch ME
                vprintf(2,'psychophysics.TrialWindow: ignoring saved window (%s)', ME.message)
            end
        end

        function w = parse(value)
            % w = psychophysics.TrialWindow.parse(value)
            % Build a window from the shorthand forms callers naturally use.
            %
            % Parameters:
            %   value - One of:
            %       []                        - all trials
            %       psychophysics.TrialWindow - returned unchanged
            %       scalar N                  - the last N trials
            %       [first last]              - trials first through last (last may be Inf)
            %       struct                     - toStruct output
            %       "all" | "last 20" | "first 10" | "20-100" | "20:100"
            %
            % Returns:
            %   w - psychophysics.TrialWindow
            if isa(value,'psychophysics.TrialWindow')
                w = value;
                return
            end

            if isempty(value)
                w = psychophysics.TrialWindow.allTrials();
                return
            end

            if isstruct(value)
                w = psychophysics.TrialWindow.fromStruct(value);
                return
            end

            if isnumeric(value)
                if isscalar(value)
                    w = psychophysics.TrialWindow.lastN(value);
                elseif numel(value) == 2
                    w = psychophysics.TrialWindow("Range", value(:)');
                else
                    error('psychophysics:TrialWindow:InvalidSpec', ...
                        'A numeric window must be a scalar count or [first last].');
                end
                return
            end

            if ischar(value) || isstring(value)
                w = psychophysics.TrialWindow.parseText_(string(value));
                return
            end

            error('psychophysics:TrialWindow:InvalidSpec', ...
                'Cannot interpret a %s as a trial window.', class(value));
        end
    end

    methods (Static, Access = private)
        function w = parseText_(txt)
            % Text grammar: "all", "last N", "first N", "A-B", "A:B", "A+".
            s = strtrim(lower(txt));

            if s == "" || s == "all" || s == "all trials"
                w = psychophysics.TrialWindow.allTrials();
                return
            end

            tok = regexp(s, '^last\s+(\d+)', 'tokens', 'once');
            if ~isempty(tok)
                w = psychophysics.TrialWindow.lastN(str2double(tok{1}));
                return
            end

            tok = regexp(s, '^first\s+(\d+)', 'tokens', 'once');
            if ~isempty(tok)
                w = psychophysics.TrialWindow.firstN(str2double(tok{1}));
                return
            end

            tok = regexp(s, '^(\d+)\s*[-:]\s*(\d+|end|inf)$', 'tokens', 'once');
            if ~isempty(tok)
                if ismember(tok{2}, {'end','inf'})
                    hi = Inf;
                else
                    hi = str2double(tok{2});
                end
                w = psychophysics.TrialWindow.range(str2double(tok{1}), hi);
                return
            end

            tok = regexp(s, '^(\d+)\s*\+$', 'tokens', 'once');
            if ~isempty(tok)
                w = psychophysics.TrialWindow.range(str2double(tok{1}), Inf);
                return
            end

            error('psychophysics:TrialWindow:InvalidSpec', ...
                'Cannot interpret "%s" as a trial window.', txt);
        end

        function n = validateCount_(arg)
            n = double(arg);
            if ~isscalar(n) || ~isfinite(n) || n < 1 || fix(n) ~= n
                error('psychophysics:TrialWindow:InvalidCount', ...
                    'The trial count must be a positive integer.');
            end
        end

        function r = validateRange_(arg)
            r = double(reshape(arg,1,2));
            if ~isfinite(r(1)) || r(1) < 1 || fix(r(1)) ~= r(1)
                error('psychophysics:TrialWindow:InvalidRange', ...
                    'The first trial of a range must be a positive integer.');
            end
            if ~(isinf(r(2)) && r(2) > 0) && (fix(r(2)) ~= r(2) || r(2) < r(1))
                error('psychophysics:TrialWindow:InvalidRange', ...
                    'The last trial of a range must be Inf or an integer >= the first trial.');
            end
        end
    end
end
