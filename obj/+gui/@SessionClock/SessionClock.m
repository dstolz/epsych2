classdef SessionClock < handle
    % gui.SessionClock(parent, options)
    % Compact status widget showing up to four live-updating readouts:
    %   - Time since the most recent trial began
    %   - Duration of the experiment since the first trial began
    %   - Duration of the experiment since the session was started
    %   - The current computer (wall-clock) time
    %
    % Right-click the widget for a context menu that toggles which lines
    % are shown and sizes the text. Both choices persist across sessions via
    % getpref/setpref, keyed by PreferenceTag (by default the hosting figure's
    % Tag, which for a gui.BehaviorGUI subclass is that GUI's own PreferenceTag
    % — so the remembered display is scoped per BehaviorGUI automatically). Each
    % line can also be toggled programmatically via the Show* properties; a
    % change takes effect on the next timer tick, or immediately via refresh().
    %
    % Font size is settable the same two ways — obj.FontSize = 22, or the
    % right-click "Font Size" menu — so an operator who sized the clock to be
    % read from across the room gets it back next session. Unlike the Show*
    % properties, a font change applies immediately.
    %
    % Usage (inside a gui.BehaviorGUI build(fig)):
    %   c = gui.SessionClock(parent);
    %   c.attachRuntime(obj.RUNTIME);
    %   c.start();
    %   obj.register(c);
    %
    %   c.ShowClockTime = false;   % programmatic control
    %   c.refresh();               % apply immediately
    %   c.FontSize = 24;           % applies (and persists) at once
    %
    % See also: gui.BehaviorGUI, gui.ElapsedTrialTimer, gui.NextTrial, epsych.Runtime

    properties
        ShowTimeSinceLastTrial  (1,1) logical = true  % Time since the most recent trial began
        ShowTimeSinceFirstTrial (1,1) logical = true  % Elapsed time since the first trial began
        ShowSessionDuration     (1,1) logical = true  % Elapsed time since RUNTIME.StartTime
        ShowClockTime           (1,1) logical = true  % Current wall-clock time
        UpdatePeriod (1,1) double {mustBePositive, mustBeFinite} = 1 % Display refresh interval (s)
        Format       (1,:) char = 'hms' % 'hms', 'ms', 's', or a custom sprintf pattern receiving total seconds
        FontPresets  (1,:) double {mustBePositive} = [10 12 14 16 20 24 28 36] % Sizes offered as one-click entries on the Font Size menu
    end

    properties (Dependent)
        FontSize % Label font size in points; applies and persists on set
    end

    properties (SetAccess = private)
        PreferenceTag (1,:) char = '' % getpref/setpref group for remembered line visibility and font size
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
        FontSize_ (1,1) double = 12
        FontMenuH_                   % "Font Size" submenu handle
    end

    properties (Constant, Access = private)
        PREF_KEY      = 'SessionClockVisibleLines'
        PREF_KEY_FONT = 'SessionClockFontSize'
        FONT_LIMITS   = [6 72] % Clamp, so no scripted or typed size can leave the clock unreadable
        LINES_ = struct( ...
            'Key',    {'LastTrial',              'FirstTrial',               'SessionDuration',     'ClockTime'}, ...
            'Prop',   {'ShowTimeSinceLastTrial',  'ShowTimeSinceFirstTrial',  'ShowSessionDuration',  'ShowClockTime'}, ...
            'Text',   {'Time Since Last Trial',   'Time Since First Trial',   'Session Duration',     'Computer Time'}, ...
            'Prefix', {'Last trial: ',            'Since first trial: ',     'Session duration: ',   'Time: '})
    end

    methods (Static)
        function s = getComponentSpec()
            % s = gui.SessionClock.getComponentSpec()
            % How gui.BehaviorGUI.add builds this component. Constructed with
            % the container alone, then given the runtime; the one component
            % that also wants start(). See gui.ComponentSpec.
            s = gui.ComponentSpec();
            s.type          = 'SessionClock';
            s.label         = 'Session Clock';
            s.category      = 'Displays';
            s.description   = 'Clock, session duration, and time-since-trial readouts';
            s.shape         = "parent";
            s.attachRuntime = true;
            s.start         = true;
            s.options       = [ ...
                gui.ComponentSpecOption('name','PreferenceTag','inputType','text'), ...
                gui.ComponentSpecOption('name','FontSize','inputType','numeric')];
        end
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
            %   FontSize      - Label font size in points (default: 12), overridden
            %                   by a saved preference if one exists.
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
            obj.FontSize_               = gui.SessionClock.clampFontSize_(options.FontSize);

            obj.PreferenceTag = options.PreferenceTag;
            if isempty(obj.PreferenceTag)
                obj.PreferenceTag = gui.SessionClock.inferPreferenceTag_(parent);
            end

            obj.buildUI_(parent, obj.FontSize_, options.FontColor);
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
            obj.NewTrialListener_ = addlistener(RUNTIME.EVENTS, 'NewTrial', @(~,~) obj.onNewTrial_());
            obj.updateDisplay_();
            vprintf(2, 'SessionClock attached to runtime')
        end

        function refresh(obj)
            % obj.refresh()
            % Apply the current Show* properties and redraw immediately,
            % instead of waiting for the next timer tick.
            obj.updateDisplay_();
        end

        function sz = get.FontSize(obj)
            sz = obj.FontSize_;
        end

        function set.FontSize(obj, points)
            obj.setFontSize(points);
        end

        function setFontSize(obj, points)
            % obj.setFontSize(points)
            % Set the label font size, in points. Sizes outside 6-72 are
            % clamped rather than refused, so a scripted value cannot leave
            % the display unreadable. Applies at once and persists like a
            % menu choice.
            arguments
                obj
                points (1,1) double {mustBePositive, mustBeFinite}
            end
            obj.FontSize_ = gui.SessionClock.clampFontSize_(points);
            obj.applyFontSize_();
            obj.saveFontPreference_();
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
            % Right-click menu with one checked toggle per line, plus a
            % Font Size submenu. The submenu's entries are rebuilt on open
            % (see refreshFontMenu_) rather than on every timer tick.
            if isempty(hostFig), return; end
            try
                cm = uicontextmenu(hostFig);
                for i = 1:numel(obj.LINES_)
                    key = obj.LINES_(i).Key;
                    uimenu(cm, 'Text', obj.LINES_(i).Text, 'Tag', ['line|' key], ...
                        'MenuSelectedFcn', @(~,~) obj.toggleLine_(key));
                end
                obj.FontMenuH_ = uimenu(cm, 'Text', 'Font Size', 'Tag', 'fontmenu', ...
                    'Separator', 'on');
                obj.refreshFontMenu_();
                try
                    cm.ContextMenuOpeningFcn = @(~,~) obj.refreshMenus_();
                catch
                    cm.Callback = @(~,~) obj.refreshMenus_(); % legacy figure
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

        function refreshMenus_(obj)
            % Context-menu opening handler: bring both the line checkmarks
            % and the font entries up to date with the current state.
            obj.refreshMenuChecks_();
            obj.refreshFontMenu_();
        end

        function refreshFontMenu_(obj)
            % Presets plus relative steps and a prompt, rebuilt on open so
            % the check mark and the custom entry follow a size that was set
            % programmatically.
            m = obj.FontMenuH_;
            if isempty(m) || ~isvalid(m), return; end
            delete(m.Children);

            sz = obj.FontSize_;
            for k = 1:numel(obj.FontPresets)
                n = obj.FontPresets(k);
                item = uimenu(m, 'Text', sprintf('%g pt', n), ...
                    'MenuSelectedFcn', @(~,~) obj.setFontSize(n));
                item.Checked = sz == n;
            end

            uimenu(m, 'Text', 'Larger', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~) obj.setFontSize(sz + 2));
            uimenu(m, 'Text', 'Smaller', ...
                'MenuSelectedFcn', @(~,~) obj.setFontSize(max(sz - 2, obj.FONT_LIMITS(1))));

            item = uimenu(m, 'Text', 'Custom...', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~) obj.promptFontSize_());
            item.Checked = ~ismember(sz, obj.FontPresets);
        end

        function promptFontSize_(obj)
            % inputdlg opens its own dialog, so it works from a uifigure; a
            % cancelled or unparseable entry is ignored.
            try
                a = inputdlg({'Font size (points):'}, 'Font Size', [1 30], ...
                    {num2str(obj.FontSize_)});
            catch ME
                vprintf(0, 1, 'gui.SessionClock: cannot prompt for a font size: %s', ME.message)
                return
            end
            if isempty(a), return; end

            n = str2double(strtrim(a{1}));
            if ~isfinite(n) || n <= 0
                vprintf(1, 'gui.SessionClock: "%s" is not a font size', strtrim(a{1}))
                return
            end
            obj.setFontSize(n);
        end

        function applyFontSize_(obj)
            % Push the current size onto every label. Rows are 'fit'-height,
            % so the widget grows or shrinks with the text.
            fns = fieldnames(obj.LabelH);
            for k = 1:numel(fns)
                lbl = obj.LabelH.(fns{k});
                if isempty(lbl) || ~isvalid(lbl), continue; end
                try
                    lbl.FontSize = obj.FontSize_;
                catch ME
                    vprintf(3, 'gui.SessionClock: unable to set font size: %s', ME.message)
                end
            end
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
            obj.loadFontPreference_();
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

        function loadFontPreference_(obj)
            % Apply a saved font size on top of the constructor's, under a
            % key of its own so an older visibility-only preference — and a
            % clock built before this control existed — still loads.
            try
                if ~ispref(obj.PreferenceTag, obj.PREF_KEY_FONT), return; end
                n = getpref(obj.PreferenceTag, obj.PREF_KEY_FONT);
                if ~isnumeric(n) || ~isscalar(n) || ~isfinite(n) || n <= 0, return; end
                obj.FontSize_ = gui.SessionClock.clampFontSize_(n);
                obj.applyFontSize_();
                vprintf(3, 'gui.SessionClock: loaded saved font size')
            catch ME
                vprintf(2, 'gui.SessionClock: failed to load saved font size: %s', ME.message)
            end
        end

        function saveFontPreference_(obj)
            % Persist the current font size for this PreferenceTag.
            try
                setpref(obj.PreferenceTag, obj.PREF_KEY_FONT, obj.FontSize_);
            catch ME
                vprintf(2, 'gui.SessionClock: failed to save font size: %s', ME.message)
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

        function points = clampFontSize_(points)
            % points = clampFontSize_(points)
            % Round to whole points and hold inside FONT_LIMITS.
            lims = gui.SessionClock.FONT_LIMITS;
            points = min(max(round(points), lims(1)), lims(2));
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
