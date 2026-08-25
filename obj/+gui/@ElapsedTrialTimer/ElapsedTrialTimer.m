classdef ElapsedTrialTimer < handle
    % gui.ElapsedTrialTimer(options)
    % gui.ElapsedTrialTimer(parent, options)
    % Counter tracking elapsed time since the last completed trial, with optional GUI label.
    %
    % Listens to epsych.EventHub 'NewData' events and resets its clock on each
    % trial completion. A MATLAB timer periodically refreshes the display label.
    % Can be used standalone (reading ElapsedTime) or embedded in any uifigure container.
    %
    % Properties (settable):
    %   UpdatePeriod - Timer refresh interval in seconds (default: 0.5).
    %   Format       - Display format: 'hms', 'ms', 's', or a custom sprintf string.
    %                  'hms' → HH:MM:SS  |  'ms' → MM:SS  |  's' → SS.f
    %                  Custom sprintf pattern receives one double (total seconds).
    %   Prefix       - Text prepended to the formatted elapsed time (default: 'Last trial: ').
    %
    % Properties (read-only):
    %   Label        - Underlying uilabel handle (empty when no parent given).
    %   ElapsedTime  - Current elapsed time as a duration scalar.
    %
    % Methods:
    %   attachRuntime  - Wire listener to RUNTIME.EVENTS NewData events.
    %   reset          - Reset the elapsed-time clock to the current instant.
    %   applyStyle     - Push FontSize/FontColor/FontWeight to the label after construction.
    %   start          - Start the periodic display-refresh timer.
    %   stop           - Stop the refresh timer.
    %   delete         - Clean up timer and listeners.
    %
    % Usage:
    %   t = gui.ElapsedTrialTimer;                        % standalone, no GUI label
    %   t = gui.ElapsedTrialTimer(fig);                   % with label in figure
    %   t = gui.ElapsedTrialTimer(fig, FontSize=14, Prefix='ITI: ');
    %   t.attachRuntime(RUNTIME);
    %   t.start;
    %   elapsed = t.ElapsedTime;                          % query programmatically
    %
    % See also: epsych.EventHub, gui.ModeIndicator, gui.GenericTimer

    % ---------------------------------------------------------------------------
    % Public settable properties
    % ---------------------------------------------------------------------------
    properties
        UpdatePeriod (1,1) double {mustBePositive, mustBeFinite} = 0.5  % Timer refresh interval in seconds
        Format       (1,:) char   = 'hms'    % 'hms', 'ms', 's', or sprintf pattern receiving total seconds
        Prefix       (1,:) char   = 'Last trial: '  % Text prepended to the elapsed-time string
    end

    % ---------------------------------------------------------------------------
    % Read-only public properties
    % ---------------------------------------------------------------------------
    properties (SetAccess = private)
        Label        % uilabel handle; empty when no parent was provided
        ElapsedTime  duration = duration(0,0,0)  % Time since last trial completion (read-only)
    end

    % ---------------------------------------------------------------------------
    % Private implementation details
    % ---------------------------------------------------------------------------
    properties (Access = private)
        LastTrialTime_ datetime = NaT   % Datetime of most recent trial completion (NaT = never)
        Timer_         timer            % Internal MATLAB timer for display refresh
        Listener_      event.listener   % Listener for epsych.EventHub NewData events
        HasLabel_      (1,1) logical = false  % True when a uilabel was created
    end

    % ---------------------------------------------------------------------------
    methods (Static)
        function s = getComponentSpec()
            % s = gui.ElapsedTrialTimer.getComponentSpec()
            % See gui.ComponentSpec.
            s = gui.ComponentSpec();
            s.type          = 'TrialTimer';
            s.label         = 'Trial Timer';
            s.category      = 'Displays';
            s.description   = 'Elapsed time since the last completed trial';
            s.shape         = "parent";
            s.attachRuntime = true;
            s.options       = [ ...
                gui.ComponentSpecOption('name','UpdatePeriod','inputType','numeric','defaultValue',0.5), ...
                gui.ComponentSpecOption('name','Format','inputType','text','defaultValue','hms'), ...
                gui.ComponentSpecOption('name','FontSize','inputType','numeric','defaultValue',12), ...
                gui.ComponentSpecOption('name','Prefix','inputType','text','defaultValue','Last trial: ')];
        end
    end

    methods
    % ---------------------------------------------------------------------------

        function obj = ElapsedTrialTimer(parent, options)
            % gui.ElapsedTrialTimer(options)
            % gui.ElapsedTrialTimer(parent, options)
            % Construct an ElapsedTrialTimer, optionally embedding a uilabel.
            %
            % Parameters:
            %   parent       - (optional) UI container (uifigure, uipanel, uigridlayout cell, etc.)
            %                  If omitted, no label is created and ElapsedTime is query-only.
            %   UpdatePeriod - Timer refresh interval in seconds (default: 0.5).
            %   Format       - Display format string (default: 'hms').
            %   FontSize     - Label font size in points (default: 12).
            %   FontColor    - Label font color [R G B] (default: [0 0 0]).
            %   FontWeight   - 'normal' or 'bold' (default: 'normal').
            %   Prefix       - Text shown before the elapsed time (default: 'Last trial: ').
            arguments
                parent       = []
                options.UpdatePeriod (1,1) double {mustBePositive, mustBeFinite} = 0.5
                options.Format       (1,:) char   = 'hms'
                options.FontSize     (1,1) double {mustBePositive, mustBeFinite} = 12
                options.FontColor    (1,3) double {mustBeNonnegative}            = [0 0 0]
                options.FontWeight   (1,:) char   = 'normal'
                options.Prefix       (1,:) char   = 'Last trial: '
            end

            obj.UpdatePeriod = options.UpdatePeriod;
            obj.Format       = options.Format;
            obj.Prefix       = options.Prefix;

            if ~isempty(parent)
                obj.Label = uilabel(parent, ...
                    'Text',                obj.formatElapsed_(0), ...
                    'HorizontalAlignment', 'center', ...
                    'FontSize',            options.FontSize, ...
                    'FontColor',           options.FontColor, ...
                    'FontWeight',          options.FontWeight);
                obj.HasLabel_ = true;
            end

            obj.buildTimer_();
        end

        % -----------------------------------------------------------------------

        function attachRuntime(obj, RUNTIME)
            % obj.attachRuntime(RUNTIME)
            % Wire a listener to RUNTIME.EVENTS so the clock resets on each
            % NewData event (trial completion). Replaces any existing listener.
            %
            % Parameters:
            %   RUNTIME - epsych.Runtime instance whose EVENTS broadcaster fires NewData
            arguments
                obj
                RUNTIME  % epsych.Runtime
            end
            delete(obj.Listener_);
            obj.Listener_ = addlistener(RUNTIME.EVENTS, 'NewData', ...
                @(~,~) obj.onNewData_());
            vprintf(2, 'ElapsedTrialTimer attached to runtime')
        end

        % -----------------------------------------------------------------------

        function reset(obj)
            % obj.reset()
            % Reset the elapsed-time clock to the current instant.
            obj.LastTrialTime_ = datetime('now');
            obj.updateDisplay_();
            vprintf(3, 'ElapsedTrialTimer reset')
        end

        % -----------------------------------------------------------------------

        function applyStyle(obj, options)
            % obj.applyStyle(FontSize=v, FontColor=[R G B], FontWeight='bold')
            % Apply font style properties to the embedded uilabel.
            % Has no effect when no label was created at construction.
            %
            % Parameters:
            %   FontSize   - Label font size in points.
            %   FontColor  - Label font color [R G B].
            %   FontWeight - 'normal' or 'bold'.
            arguments
                obj
                options.FontSize   (1,1) double {mustBePositive, mustBeFinite}
                options.FontColor  (1,3) double {mustBeNonnegative}
                options.FontWeight (1,:) char
            end
            if ~obj.HasLabel_ || ~isgraphics(obj.Label), return, end
            if isfield(options, 'FontSize'),   obj.Label.FontSize   = options.FontSize;   end
            if isfield(options, 'FontColor'),  obj.Label.FontColor  = options.FontColor;  end
            if isfield(options, 'FontWeight'), obj.Label.FontWeight = options.FontWeight; end
        end

        % -----------------------------------------------------------------------

        function start(obj)
            % obj.start()
            % Start the periodic display-refresh timer.
            if strcmp(obj.Timer_.Running, 'off')
                obj.Timer_.Period = obj.UpdatePeriod;
                start(obj.Timer_);
                vprintf(2, 'ElapsedTrialTimer started')
            end
        end

        % -----------------------------------------------------------------------

        function stop(obj)
            % obj.stop()
            % Stop the periodic display-refresh timer.
            if strcmp(obj.Timer_.Running, 'on')
                stop(obj.Timer_);
                vprintf(2, 'ElapsedTrialTimer stopped')
            end
        end

        % -----------------------------------------------------------------------

        function delete(obj)
            % Clean up the timer and event listener.
            try
                stop(obj.Timer_);
                delete(obj.Timer_);
            catch ME
                vprintf(0, 1, ME)
            end
            delete(obj.Listener_);
        end

    end % public methods

    % ---------------------------------------------------------------------------
    % Private helpers
    % ---------------------------------------------------------------------------
    methods (Access = private)

        function buildTimer_(obj)
            % Create the internal display-refresh timer.
            T = timer();
            T.Name           = 'ElapsedTrialTimer';
            T.Tag            = 'EPsychElapsedTrialTimer';
            T.BusyMode       = 'drop';
            T.ExecutionMode  = 'fixedRate';
            T.TasksToExecute = inf;
            T.Period         = obj.UpdatePeriod;
            T.TimerFcn       = @(~,~) obj.updateDisplay_();
            T.ErrorFcn       = @(~, ev) vprintf(0, 1, 'ElapsedTrialTimer error: %s', ev.Data.message);
            obj.Timer_       = T;
        end

        % -----------------------------------------------------------------------

        function onNewData_(obj)
            % Called when epsych.EventHub fires a NewData event (trial completed).
            obj.LastTrialTime_ = datetime('now');
            obj.updateDisplay_();
        end

        % -----------------------------------------------------------------------

        function updateDisplay_(obj)
            % Recalculate ElapsedTime and, if a label exists, refresh its text.
            if isnat(obj.LastTrialTime_)
                secs = 0;
            else
                secs = seconds(datetime('now') - obj.LastTrialTime_);
            end
            obj.ElapsedTime = seconds(secs);

            if obj.HasLabel_ && isgraphics(obj.Label)
                obj.Label.Text = obj.formatElapsed_(secs);
            end
        end

        % -----------------------------------------------------------------------

        function str = formatElapsed_(obj, totalSecs)
            % str = formatElapsed_(obj, totalSecs)
            % Convert total seconds to a display string using obj.Format.
            %
            % Parameters:
            %   totalSecs - Non-negative scalar number of elapsed seconds.
            %
            % Returns:
            %   str - Formatted string (with obj.Prefix prepended).
            totalSecs = max(0, totalSecs);
            switch lower(obj.Format)
                case 'hms'
                    h = floor(totalSecs / 3600);
                    m = floor(mod(totalSecs, 3600) / 60);
                    s = floor(mod(totalSecs, 60));
                    body = sprintf('%02d:%02d:%02d', h, m, s);
                case 'ms'
                    m = floor(totalSecs / 60);
                    s = floor(mod(totalSecs, 60));
                    body = sprintf('%02d:%02d', m, s);
                case 's'
                    body = sprintf('%.1f s', totalSecs);
                otherwise
                    % Treat Format as a custom sprintf pattern; receives total seconds.
                    body = sprintf(obj.Format, totalSecs);
            end
            str = [obj.Prefix, body];
        end

    end % private methods

end
