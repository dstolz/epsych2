classdef SessionClock < handle
    % gui.SessionClock(parent, options)
    % Compact status widget showing up to four live-updating readouts:
    %   - Time since the most recent trial began
    %   - Duration of the experiment since the first trial began
    %   - Duration of the experiment since the session was started
    %   - The current computer (wall-clock) time
    %
    % Right-click the widget for a context menu that toggles which lines
    % are shown. The choice persists across sessions via getpref/setpref,
    % keyed by PreferenceTag (by default the hosting figure's Tag, which
    % for a gui.BehaviorGUI subclass is that GUI's own PreferenceTag — so the
    % remembered lines are scoped per BehaviorGUI automatically). Each line can
    % also be toggled programmatically via the Show* properties; a change
    % takes effect on the next timer tick, or immediately via refresh().
    %
    % Usage (inside a gui.BehaviorGUI build(fig)):
    %   c = gui.SessionClock(parent);
    %   c.attachRuntime(obj.RUNTIME);
    %   c.start();
    %   obj.register(c);
    %
    %   c.ShowClockTime = false;   % programmatic control
    %   c.refresh();               % apply immediately
    %
    % See also: gui.BehaviorGUI, gui.ElapsedTrialTimer, epsych.Runtime

    properties
        ShowTimeSinceLastTrial  (1,1) logical = true  % Time since the most recent trial began
        ShowTimeSinceFirstTrial (1,1) logical = true  % Elapsed time since the first trial began
        ShowSessionDuration     (1,1) logical = true  % Elapsed time since RUNTIME.StartTime
        ShowClockTime           (1,1) logical = true  % Current wall-clock time
        UpdatePeriod (1,1) double {mustBePositive, mustBeFinite} = 1 % Display refresh interval (s)
        Format       (1,:) char = 'hms' % 'hms', 'ms', 's', or a custom sprintf pattern receiving total seconds
    end

    properties (SetAccess = private)
        PreferenceTag (1,:) char = '' % getpref/setpref group for remembered line visibility
        LabelH        (1,1) struct = struct() % uilabel handles keyed by line name
        ContextMenuH                 % Right-click menu handle
        PanelH                       % Outer uipanel handle
        GridH                        % Inner uigridlayout handle (one row per line)
    end

    properties (Access = private)
        Timer_
        NewTrialListener_ event.listener
        SessionStartTime_ datetime = NaT
        FirstTrialTime_   datetime = NaT
        LastTrialTime_    datetime = NaT
    end

    properties (Constant, Access = private)
        PREF_KEY = 'SessionClockVisibleLines'
        LINES_ = struct( ...
            'Key',    {'LastTrial',              'FirstTrial',               'SessionDuration',     'ClockTime'}, ...
            'Prop',   {'ShowTimeSinceLastTrial',  'ShowTimeSinceFirstTrial',  'ShowSessionDuration',  'ShowClockTime'}, ...
            'Text',   {'Time Since Last Trial',   'Time Since First Trial',   'Session Duration',     'Computer Time'}, ...
            'Prefix', {'Last trial: ',            'Since first trial: ',     'Session duration: ',   'Time: '})
    end

    methods

        function obj = SessionClock(parent, options)
            % gui.SessionClock(parent, options)
            % Construct a SessionClock embedded in a ui container.
            %
            % Parameters:
            %   parent        - Any UI container (uifigure, uigridlayout cell, uipanel, etc.).
            %   PreferenceTag - getpref/setpref group; default is the ancestor figure's Tag.
            %   UpdatePeriod  - Timer refresh interval in seconds (default: 1).
            %   FontSize      - Label font size in points (default: 12).
            %   FontColor     - Label font color [R G B] (default: [0 0 0]).
            %   ShowTimeSinceLastTrial, ShowTimeSinceFirstTrial, ShowSessionDuration,
            %   ShowClockTime - Initial visibility, overridden by a saved preference if one exists.
            arguments
                parent
                options.PreferenceTag (1,:) char = ''
                options.UpdatePeriod  (1,1) double {mustBePositive, mustBeFinite} = 1
                options.FontSize      (1,1) double {mustBePositive, mustBeFinite} = 12
                options.FontColor     (1,3) double {mustBeNonnegative} = [0 0 0]
                options.ShowTimeSinceLastTrial  (1,1) logical = true
                options.ShowTimeSinceFirstTrial (1,1) logical = true
                options.ShowSessionDuration     (1,1) logical = true
                options.ShowClockTime           (1,1) logical = true
            end

            obj.ShowTimeSinceLastTrial  = options.ShowTimeSinceLastTrial;
            obj.ShowTimeSinceFirstTrial = options.ShowTimeSinceFirstTrial;
            obj.ShowSessionDuration     = options.ShowSessionDuration;
            obj.ShowClockTime           = options.ShowClockTime;
            obj.UpdatePeriod            = options.UpdatePeriod;

            obj.PreferenceTag = options.PreferenceTag;
            if isempty(obj.PreferenceTag)
                obj.PreferenceTag = gui.SessionClock.inferPreferenceTag_(parent);
            end

            obj.buildUI_(parent, options.FontSize, options.FontColor);
            obj.loadPreferences_();
            obj.buildTimer_();
            obj.updateDisplay_();
        end

        function attachRuntime(obj, RUNTIME)
            % obj.attachRuntime(RUNTIME)
            % Wire a NewTrial listener and capture the session start time.
            % Replaces any previously attached listener.
            arguments
                obj
                RUNTIME % epsych.Runtime
            end
            delete(obj.NewTrialListener_);
            obj.SessionStartTime_ = NaT;
            try
                if ~isnat(RUNTIME.StartTime)
                    obj.SessionStartTime_ = RUNTIME.StartTime;
                end
            catch
            end
            if isnat(obj.SessionStartTime_)
                obj.SessionStartTime_ = datetime('now');
            end
            obj.NewTrialListener_ = addlistener(RUNTIME.HELPER, 'NewTrial', @(~,~) obj.onNewTrial_());
            obj.updateDisplay_();
            vprintf(2, 'SessionClock attached to runtime')
        end

        function refresh(obj)
            % obj.refresh()
            % Apply the current Show* properties and redraw immediately,
            % instead of waiting for the next timer tick.
            obj.updateDisplay_();
        end

        function start(obj)
            % obj.start()
            % Start the periodic display-refresh timer.
            if strcmp(obj.Timer_.Running, 'off')
                obj.Timer_.Period = obj.UpdatePeriod;
                start(obj.Timer_);
                vprintf(2, 'SessionClock started')
            end
        end

        function stop(obj)
            % obj.stop()
            % Stop the periodic display-refresh timer.
            if strcmp(obj.Timer_.Running, 'on')
                stop(obj.Timer_);
                vprintf(2, 'SessionClock stopped')
            end
        end

        function delete(obj)
            % Clean up the timer, listener, and context menu.
            try
                stop(obj.Timer_);
                delete(obj.Timer_);
            catch ME
                vprintf(0, 1, ME)
            end
            delete(obj.NewTrialListener_);
            try
                if ~isempty(obj.ContextMenuH) && isvalid(obj.ContextMenuH)
                    delete(obj.ContextMenuH);
                end
            catch
            end
        end

    end % public methods

    methods (Access = private)

        function buildUI_(obj, parent, fontSize, fontColor)
            % Lay out one row per line in a grid. Rows use 'fit' height
            % and labels use WordWrap so a line never clips: hidden rows
            % collapse to zero height instead of reserving clipped, blank
            % space, and shown rows grow to fit wrapped text.
            obj.PanelH = uipanel(parent, 'BorderType', 'none');

            n = numel(obj.LINES_);
            g = uigridlayout(obj.PanelH, [n 1]);
            g.RowHeight   = repmat({'fit'}, 1, n);
            g.ColumnWidth = {'1x'};
            g.RowSpacing  = 2;
            g.Padding     = [4 4 4 4];
            obj.GridH = g;

            for i = 1:n
                key = obj.LINES_(i).Key;
                lbl = uilabel(g, ...
                    'Text',                '', ...
                    'WordWrap',            'on', ...
                    'HorizontalAlignment', 'left', ...
                    'FontSize',            fontSize, ...
                    'FontColor',           fontColor);
                lbl.Layout.Row    = i;
                lbl.Layout.Column = 1;
                obj.LabelH.(key) = lbl;
            end

            obj.buildContextMenu_(ancestor(parent, 'figure'));
        end

        function buildContextMenu_(obj, hostFig)
            % Right-click menu with one checked toggle per line.
            if isempty(hostFig), return; end
            try
                cm = uicontextmenu(hostFig);
                for i = 1:numel(obj.LINES_)
                    key = obj.LINES_(i).Key;
                    uimenu(cm, 'Text', obj.LINES_(i).Text, 'Tag', ['line|' key], ...
                        'MenuSelectedFcn', @(~,~) obj.toggleLine_(key));
                end
                obj.ContextMenuH = cm;
                obj.PanelH.ContextMenu = cm;
                fns = fieldnames(obj.LabelH);
                for k = 1:numel(fns)
                    obj.LabelH.(fns{k}).ContextMenu = cm;
                end
            catch ME
                vprintf(3, 'gui.SessionClock: context menu unavailable: %s', ME.message)
            end
        end

        function buildTimer_(obj)
            % Create the internal display-refresh timer.
            T = timer();
            T.Name           = 'SessionClock';
            T.Tag            = 'EPsychSessionClock';
            T.BusyMode       = 'drop';
            T.ExecutionMode  = 'fixedRate';
            T.TasksToExecute = inf;
            T.Period         = obj.UpdatePeriod;
            T.TimerFcn       = @(~,~) obj.updateDisplay_();
            T.ErrorFcn       = @(~, ev) vprintf(0, 1, 'SessionClock error: %s', ev.Data.message);
            obj.Timer_       = T;
        end

        function toggleLine_(obj, key)
            % Right-click menu handler: flip one line's visibility, apply
            % it immediately, and remember the choice.
            idx = strcmp({obj.LINES_.Key}, key);
            prop = obj.LINES_(idx).Prop;
            obj.(prop) = ~obj.(prop);
            obj.updateDisplay_();
            obj.savePreferences_();
        end

        function onNewTrial_(obj)
            % Stamp the most-recent-trial clock, and the first-trial clock
            % the first time this fires.
            now_ = datetime('now');
            if isnat(obj.FirstTrialTime_)
                obj.FirstTrialTime_ = now_;
            end
            obj.LastTrialTime_ = now_;
            obj.updateDisplay_();
        end

        function updateDisplay_(obj)
            % Single source of truth: every call re-applies row visibility
            % from the current Show* properties, refreshes all label text,
            % and syncs the context menu's checkmarks — so programmatic
            % property changes, menu toggles, and timer ticks all converge
            % on the same displayed state.
            if isempty(obj.GridH) || ~isvalid(obj.GridH), return; end

            timeSource = struct( ...
                'LastTrial',       obj.LastTrialTime_, ...
                'FirstTrial',      obj.FirstTrialTime_, ...
                'SessionDuration', obj.SessionStartTime_);

            rh = cell(1, numel(obj.LINES_));
            for i = 1:numel(obj.LINES_)
                L   = obj.LINES_(i);
                tf  = obj.(L.Prop);
                lbl = obj.LabelH.(L.Key);
                lbl.Visible = matlab.lang.OnOffSwitchState(tf);
                if tf
                    rh{i} = 'fit';
                else
                    rh{i} = 0;
                end

                if strcmp(L.Key, 'ClockTime')
                    lbl.Text = [L.Prefix char(datetime('now', 'Format', 'HH:mm:ss'))];
                else
                    lbl.Text = obj.formatLine_(L.Prefix, timeSource.(L.Key));
                end
            end
            obj.GridH.RowHeight = rh;
            obj.refreshMenuChecks_();
        end

        function refreshMenuChecks_(obj)
            % Sync menu checkmarks with the current Show* property values.
            cm = obj.ContextMenuH;
            if isempty(cm) || ~isvalid(cm), return; end
            items = findall(cm, 'Type', 'uimenu');
            for k = 1:numel(items)
                t = items(k).Tag;
                if startsWith(t, 'line|')
                    key = extractAfter(t, 'line|');
                    idx = strcmp({obj.LINES_.Key}, key);
                    items(k).Checked = obj.(obj.LINES_(idx).Prop);
                end
            end
        end

        function str = formatLine_(obj, prefix, t0)
            % str = formatLine_(obj, prefix, t0)
            % Format an elapsed duration since t0 (NaT reads as "not yet").
            if isempty(t0) || isnat(t0)
                str = [prefix '--'];
                return
            end
            secs = max(0, seconds(datetime('now') - t0));
            str = [prefix gui.SessionClock.formatDuration_(secs, obj.Format)];
        end

        function loadPreferences_(obj)
            % Apply a saved visibility choice, if one exists, on top of
            % the constructor-supplied defaults.
            try
                if ispref(obj.PreferenceTag, obj.PREF_KEY)
                    s = getpref(obj.PreferenceTag, obj.PREF_KEY);
                    for i = 1:numel(obj.LINES_)
                        f = obj.LINES_(i).Prop;
                        if isfield(s, f)
                            obj.(f) = logical(s.(f));
                        end
                    end
                    vprintf(3, 'gui.SessionClock: loaded saved line visibility')
                end
            catch ME
                vprintf(2, 'gui.SessionClock: failed to load saved preferences: %s', ME.message)
            end
        end

        function savePreferences_(obj)
            % Persist the current line visibility for this PreferenceTag.
            try
                s = struct();
                for i = 1:numel(obj.LINES_)
                    f = obj.LINES_(i).Prop;
                    s.(f) = obj.(f);
                end
                setpref(obj.PreferenceTag, obj.PREF_KEY, s);
            catch ME
                vprintf(2, 'gui.SessionClock: failed to save preferences: %s', ME.message)
            end
        end

    end % private methods

    methods (Static, Access = private)

        function tag = inferPreferenceTag_(parent)
            % Default PreferenceTag: the ancestor figure's Tag (which, for
            % a gui.BehaviorGUI subclass, is that GUI's own PreferenceTag), so
            % line visibility is remembered per BehaviorGUI without the host
            % needing to pass anything. Falls back to a fixed tag when no
            % ancestor figure exists yet (e.g. standalone construction).
            tag = '';
            try
                f = ancestor(parent, 'figure');
                if ~isempty(f) && isvalid(f) && ~isempty(f.Tag)
                    tag = f.Tag;
                end
            catch
            end
            if isempty(tag)
                tag = 'gui_SessionClock';
            end
        end

        function str = formatDuration_(totalSecs, fmt)
            % str = formatDuration_(totalSecs, fmt)
            % Convert total seconds to a display string per Format.
            totalSecs = max(0, totalSecs);
            switch lower(fmt)
                case 'hms'
                    h = floor(totalSecs / 3600);
                    m = floor(mod(totalSecs, 3600) / 60);
                    s = floor(mod(totalSecs, 60));
                    str = sprintf('%02d:%02d:%02d', h, m, s);
                case 'ms'
                    m = floor(totalSecs / 60);
                    s = floor(mod(totalSecs, 60));
                    str = sprintf('%02d:%02d', m, s);
                case 's'
                    str = sprintf('%.1f s', totalSecs);
                otherwise
                    str = sprintf(fmt, totalSecs);
            end
        end

    end
end
