classdef SessionPerformance < gui.PopOut
    % obj = gui.components.SessionPerformance(source, container)
    % Generic session performance summary for custom behavior GUIs.
    %
    % Shows the behavioral metrics an experimenter watches during a session
    % -- trial counts, hit / false alarm / abort rates, d', criterion --
    % computed by a psychophysics.SessionMetrics object rather than by the
    % GUI, so the same numbers are available headlessly and offline.
    %
    % Which trials the metrics are computed from is a first-class, visible
    % setting. The panel header always states the active window ("Last 20
    % trials (28-47)"), and the window can be changed two ways:
    %
    %   Programmatically  obj.TrialWindow = "all"      % every trial
    %                     obj.TrialWindow = 50         % the last 50 trials
    %                     obj.TrialWindow = [20 100]   % trials 20 through 100
    %                     obj.setTrialWindow(psychophysics.TrialWindow.lastN(20))
    %
    %   By the operator   right-click the panel -> Trials Included, which
    %                     offers All Trials, a set of Last-N presets, and
    %                     prompts for a custom last-N, first-N, or range.
    %
    % Font size works the same two ways -- obj.FontSize = 16, or the
    % right-click Font Size menu. It is the caption size: values render 2pt
    % larger, the supporting counts 2pt smaller, and the header 1pt smaller,
    % so one setting scales the whole panel.
    %
    % The same right-click menu chooses which metrics are displayed, and
    % offers Open in Separate Window (see gui.PopOut), which repeats the
    % summary in a window of its own -- with its own trial window and its own
    % metric selection, so watching the last 20 trials there leaves the
    % embedded panel showing the whole session. Both the window and the
    % metric selection persist across sessions with getpref/setpref, keyed to
    % the hosting figure (or an explicit PreferenceTag), matching
    % gui.components.NextTrial and gui.components.ParameterScatter. So does the font size.
    %
    % Properties:
    %   Analysis      - psychophysics.SessionMetrics doing the computation
    %   TrialWindow   - Trials included; accepts any TrialWindow.parse form
    %   Metrics       - Metric names displayed, in display order
    %   FontSize      - Caption font size in points; values render 2pt larger
    %   ValueColors   - Struct mapping metric Kind -> hex color
    %   ContextMenu   - The right-click menu; host GUIs may append items
    %
    % Methods:
    %   setTrialWindow - Choose the trials the metrics are computed from
    %   setMetrics     - Choose which metrics are displayed
    %   setFontSize    - Choose the caption font size
    %   refresh        - Redraw values from the current results
    %   summaryText    - Plain-text summary of what is displayed
    %
    % Example:
    %   % In a gui.BehaviorGUI subclass's build(fig)
    %   obj.Performance = obj.addPerformance(panelPerformance, ...
    %       Metrics=["HitRate","FARate","AbortRate","DPrime"], FontSize=12);
    %   obj.Performance.TrialWindow = 20;   % summarize the last 20 trials
    %
    % Requires a uifigure-based container (uipanel, uigridlayout, or uifigure).
    %
    % See also: psychophysics.SessionMetrics, psychophysics.TrialWindow,
    % gui.BehaviorGUI.addPerformance, documentation/gui/gui_SessionPerformance.md

    properties (Dependent)
        TrialWindow  % Trials included in the summary (psychophysics.TrialWindow)
        Metrics      % Metric names displayed, in display order
        FontSize     % Caption font size in points; values render 2pt larger
    end

    properties
        % ValueColors - Metric Kind -> hex color for the value text. Kinds
        % follow the response outcomes so a glance separates good from bad:
        % green hit, red miss, blue correct reject, orange false alarm,
        % olive abort, teal sensitivity, neutral gray counts.
        ValueColors = struct( ...
            'hit',         "#1b7f3b", ...
            'miss',        "#c0392b", ...
            'cr',          "#1b6ca8", ...
            'fa',          "#c26a1a", ...
            'abort',       "#8a7300", ...
            'sensitivity', "#0f7c8a", ...
            'count',       "#3c3c3c", ...
            'neutral',     "#3c3c3c")

        LabelColor (1,1) string = "#6b6b6b"   % Metric caption color
        HeaderColor (1,1) string = "#31708f"  % Trial-window header color

        % WindowPresets - Trial counts offered as one-click "Last N" entries
        WindowPresets (1,:) double = [10 20 50 100]

        % FontPresets - Caption sizes offered as one-click entries
        FontPresets (1,:) double {mustBePositive} = [10 12 14 16 20 24]
    end

    properties (SetAccess = private)
        Analysis                            % psychophysics.SessionMetrics
        Parent                              % Hosting container supplied at construction
        GridH                               % uigridlayout holding the rows
        HeaderH                             % uilabel stating the active trial window
        ContextMenu = []                    % Right-click menu
    end

    properties (Access = private)
        Metrics_ (1,:) string = string.empty(1,0)
        Rows_ = struct('Name',{},'LabelH',{},'ValueH',{},'DetailH',{})
        FillerH_ = []
        FontSize_ (1,1) double = 12
        ShowHeader_ (1,1) logical = true
        ShowDetail_ (1,1) logical = true
        OwnsAnalysis_ (1,1) logical = false
        Source_ = []                        % Construction source, reused to build a pop-out
        PreferenceTag_ (1,:) char = ''
        WindowMenuH_ = []
        MetricMenuH_ = []
        FontMenuH_ = []
        hl_NewData_ = event.listener.empty
        hl_Window_ = event.listener.empty
        selfDeleteListener_ = event.listener.empty
    end

    properties (Constant, Access = private)
        PREF_GROUP = 'epsych2_gui_SessionPerformance'
    end

    methods (Static)
        function s = getComponentSpec()
            % s = gui.components.SessionPerformance.getComponentSpec()
            % Built over the analysis object when there is one, else the
            % runtime -- the panel computes through psychophysics.SessionMetrics
            % either way. See gui.ComponentSpec.
            s = gui.ComponentSpec();
            s.type        = 'Performance';
            s.label       = 'Session Performance';
            s.category    = 'Displays';
            s.description = 'Session summary panel: rates, counts, d''';
            s.shape       = ["psychOrRuntime","parent"];
            s.options     = [ ...
                gui.ComponentSpecOption('name','Metrics','inputType','text','isList',true), ...
                gui.ComponentSpecOption('name','FontSize','inputType','numeric','defaultValue',12), ...
                gui.ComponentSpecOption('name','ShowHeader','inputType','logical','defaultValue',true), ...
                gui.ComponentSpecOption('name','ShowDetail','inputType','logical','defaultValue',true), ...
                gui.ComponentSpecOption('name','PreferenceTag','inputType','text')];
        end
    end

    methods
        function obj = SessionPerformance(source, container, options)
            % obj = gui.components.SessionPerformance(source, container, ...)
            %
            % Parameters:
            %   source    - One of: psychophysics.SessionMetrics (used as is),
            %               any other psychophysics object (its runtime or
            %               DATA is reused), an epsych.Runtime, or a per-trial
            %               DATA struct array for offline review.
            %   container - uipanel, uigridlayout, or uifigure host.
            %   Metrics       - Metric names to display. Default
            %                   psychophysics.SessionMetrics.defaultMetrics.
            %   TrialWindow   - Trials to summarize; any form accepted by
            %                   psychophysics.TrialWindow.parse. Default: all.
            %   FontSize      - Caption font size; values render 2pt larger.
            %                   Default 12. Like the metric selection, a size
            %                   saved for this PreferenceTag takes precedence.
            %   ShowHeader    - Show the trial-window header. Default true.
            %   ShowDetail    - Show the supporting counts column. Default true.
            %   PreferenceTag - Key for saved preferences (defaults to the
            %                   hosting figure Tag/Name).
            arguments
                source
                container (1,1)
                options.Metrics (1,:) string = psychophysics.SessionMetrics.defaultMetrics()
                options.TrialWindow = psychophysics.TrialWindow
                options.FontSize (1,1) double {mustBePositive} = 12
                options.ShowHeader (1,1) logical = true
                options.ShowDetail (1,1) logical = true
                options.PreferenceTag (1,:) char = ''
            end

            obj.Parent         = container;
            obj.Source_        = source; % kept so a pop-out can summarize the same trials
            obj.FontSize_      = options.FontSize;
            obj.ShowHeader_    = options.ShowHeader;
            obj.ShowDetail_    = options.ShowDetail;
            obj.PreferenceTag_ = options.PreferenceTag;

            obj.resolveAnalysis_(source, options.TrialWindow);
            obj.Metrics_ = obj.validateMetrics_(options.Metrics);

            obj.buildUI_();
            obj.loadPreferences_();   % a saved selection overrides the defaults
            obj.attachListeners_();
            obj.rebuildRows_();
        end

        function delete(obj)
            % delete(obj)
            % Release listeners and the context menu. An analysis object
            % created by this component is deleted with it; one supplied by
            % the caller is left alone.
            for L = [obj.hl_NewData_, obj.hl_Window_, obj.selfDeleteListener_]
                try
                    if isvalid(L)
                        L.Enabled = false;
                        delete(L);
                    end
                catch
                end
            end

            try
                if ~isempty(obj.ContextMenu) && isvalid(obj.ContextMenu)
                    delete(obj.ContextMenu);
                end
            catch
            end

            try
                if obj.OwnsAnalysis_ && ~isempty(obj.Analysis) && isvalid(obj.Analysis)
                    delete(obj.Analysis);
                end
            catch
            end

            % Unlike the table-based components, this one installs a layout
            % manager in its container, and a container accepts only one.
            % Leaving it behind would block a replacement panel, so the
            % grid this component created goes with it.
            try
                if ~isempty(obj.GridH) && isvalid(obj.GridH)
                    delete(obj.GridH);
                end
            catch
            end
        end

        % -- Trial window ------------------------------------------------

        function w = get.TrialWindow(obj)
            w = obj.Analysis.TrialWindow;
        end

        function set.TrialWindow(obj, value)
            obj.setTrialWindow(value);
        end

        function setTrialWindow(obj, value)
            % setTrialWindow(obj, value)
            % Choose the trials the metrics are computed from. Accepts a
            % psychophysics.TrialWindow or any shorthand its parse method
            % understands ("all", 50, [20 100], "last 20", "first 10").
            % Persists like a menu selection.
            obj.Analysis.TrialWindow = value;   % recomputes; PostSet drives the refresh
            obj.savePreferences_();
        end

        % -- Metric selection --------------------------------------------

        function m = get.Metrics(obj)
            m = obj.Metrics_;
        end

        function set.Metrics(obj, names)
            obj.setMetrics(names);
        end

        function setMetrics(obj, names)
            % setMetrics(obj, names)
            % Choose which metrics are displayed, in display order. Names
            % come from psychophysics.SessionMetrics.metricNames; unknown
            % names are dropped with a message rather than throwing, so a
            % stale saved selection cannot block a GUI from opening.
            arguments
                obj
                names (1,:) string
            end
            obj.Metrics_ = obj.validateMetrics_(names);
            obj.rebuildRows_();
            obj.savePreferences_();
        end

        % -- Font size ---------------------------------------------------

        function sz = get.FontSize(obj)
            sz = obj.FontSize_;
        end

        function set.FontSize(obj, points)
            obj.setFontSize(points);
        end

        function setFontSize(obj, points)
            % setFontSize(obj, points)
            % Set the caption font size, in points; values, counts, and the
            % header scale with it. Sizes outside 6-72 are clamped rather
            % than refused, so a scripted value cannot leave the panel
            % unreadable. Persists like a menu selection.
            arguments
                obj
                points (1,1) double {mustBePositive, mustBeFinite}
            end
            obj.FontSize_ = min(max(round(points), 6), 72);
            obj.applyFontSize_();
            obj.savePreferences_();
        end

        % -- Display -----------------------------------------------------

        function refresh(obj)
            % refresh(obj)
            % Redraw the header and every value from the current results.
            if isempty(obj.GridH) || ~isvalid(obj.GridH), return; end
            if isempty(obj.Analysis) || ~isvalid(obj.Analysis), return; end

            try
                obj.updateHeader_();

                for i = 1:numel(obj.Rows_)
                    r = obj.Rows_(i);
                    if ~isvalid(r.ValueH), continue; end
                    [~, text, detail] = obj.Analysis.metric(r.Name);
                    r.ValueH.Text = char(text);
                    if ~isempty(r.DetailH) && isvalid(r.DetailH)
                        r.DetailH.Text = char(detail);
                    end
                end
            catch ME
                vprintf(0,1,ME)
            end
        end

        function s = summaryText(obj)
            % s = summaryText(obj)
            % Plain-text form of what is displayed, for logs and clipboard.
            s = obj.Analysis.summaryText(obj.Metrics_);
        end
    end

    methods (Access = protected)

        function c = popOutHostContainer_(obj)
            % Container this panel was built into (gui.PopOut).
            c = obj.Parent;
        end

        function h = createPopOut_(obj, container)
            % A second summary over the same trials, in its own window.
            % It always computes through an analysis object of its own:
            % sharing one would make a trial-window change in the pop-out
            % rewrite the embedded panel's numbers too.
            tag = obj.popOutPreferenceTag_();

            src = obj.Source_;
            ownsNew = false;
            if isa(src,'psychophysics.SessionMetrics')
                src = psychophysics.SessionMetrics( ...
                    obj.liveSource_(src.RUNTIME, src.DATA), ...
                    StimulusTrialType = src.StimulusTrialType, ...
                    CatchTrialType    = src.CatchTrialType, ...
                    TrialWindow       = obj.TrialWindow);
                ownsNew = true;
            end

            h = gui.components.SessionPerformance(src, container, ...
                Metrics       = obj.Metrics_, ...
                TrialWindow   = obj.TrialWindow, ...
                FontSize      = obj.FontSize_, ...
                ShowHeader    = obj.ShowHeader_, ...
                ShowDetail    = obj.ShowDetail_, ...
                PreferenceTag = tag);

            % The analysis built just above has no other owner, so the
            % pop-out has to be the one that deletes it.
            h.OwnsAnalysis_ = ownsNew || h.OwnsAnalysis_;
        end
    end

    methods (Access = private)

        % -- Construction ------------------------------------------------

        function resolveAnalysis_(obj, source, trialWindow)
            % Reuse a SessionMetrics if given one; otherwise build one over
            % the same data the caller's object or runtime is using, so the
            % summary and the rest of the GUI never disagree about trials.
            if isa(source,'psychophysics.SessionMetrics')
                obj.Analysis = source;
                obj.OwnsAnalysis_ = false;
                return
            end

            args = {};
            if isa(source,'psychophysics.Psych')
                args = {'StimulusTrialType', source.StimulusTrialType, ...
                        'CatchTrialType',    source.CatchTrialType};
                dataSource = obj.liveSource_(source.RUNTIME, source.DATA);
            elseif isa(source,'psychophysics.Detection')
                args = {'StimulusTrialType', source.ttStimulus, ...
                        'CatchTrialType',    source.ttCatch};
                dataSource = obj.liveSource_(source.RUNTIME, source.DATA);
            elseif isstruct(source) || isempty(source)
                dataSource = source;
            else
                dataSource = source;   % epsych.Runtime, or anything with EVENTS
            end

            obj.Analysis = psychophysics.SessionMetrics(dataSource, ...
                args{:}, TrialWindow=trialWindow);
            obj.OwnsAnalysis_ = true;
        end

        function src = liveSource_(~, RUNTIME, DATA)
            % Prefer the runtime so the new analysis follows NewData itself;
            % an offline object contributes its trial data instead.
            if isempty(RUNTIME)
                src = DATA;
            else
                src = RUNTIME;
            end
        end

        function buildUI_(obj)
            g = uigridlayout(obj.Parent, [1 3]);
            g.ColumnWidth   = {'1x','fit','fit'};
            g.RowHeight     = {'1x'};
            g.RowSpacing    = 2;
            g.ColumnSpacing = 8;
            g.Padding       = [6 4 6 4];
            try
                g.Scrollable = 'on';   % more metrics than the panel can show
            catch
            end
            obj.GridH = g;

            obj.selfDeleteListener_ = listener(g, 'ObjectBeingDestroyed', @(~,~) delete(obj));

            obj.createContextMenu_();
        end

        function attachListeners_(obj)
            % Refresh from the analysis object's own rebroadcast rather than
            % from the runtime: psychophysics.Psych re-emits NewData after it
            % has recomputed, so the panel never has to assume anything about
            % the order in which two listeners on the runtime would fire.
            A = obj.Analysis;
            obj.hl_NewData_ = listener(A.Events, 'NewData', @(~,~) obj.refresh());

            % Covers programmatic window changes made on the analysis object
            % directly, not just through this component.
            obj.hl_Window_ = listener(A, 'TrialWindow', 'PostSet', @(~,~) obj.refresh());
        end

        % -- Rows --------------------------------------------------------

        function rebuildRows_(obj)
            % Rebuild one row per selected metric. Values are refreshed in
            % place afterwards, so this runs only when the selection changes.
            if isempty(obj.GridH) || ~isvalid(obj.GridH), return; end

            delete(obj.GridH.Children);
            obj.Rows_ = struct('Name',{},'LabelH',{},'ValueH',{},'DetailH',{});
            obj.HeaderH = [];
            obj.FillerH_ = [];

            C = psychophysics.SessionMetrics.catalogue();
            n = numel(obj.Metrics_);

            heights = repmat({'fit'}, 1, n + double(obj.ShowHeader_) + 1);
            heights{end} = '1x';   % filler row absorbs slack and keeps rows top-aligned
            obj.GridH.RowHeight = heights;
            if obj.ShowDetail_
                obj.GridH.ColumnWidth = {'1x','fit','fit'};
            else
                obj.GridH.ColumnWidth = {'1x','fit'};
            end

            row = 0;
            if obj.ShowHeader_
                row = 1;
                h = uilabel(obj.GridH);
                h.Layout.Row    = row;
                h.Layout.Column = [1 numel(obj.GridH.ColumnWidth)];
                h.FontSize      = max(obj.FontSize_ - 1, 8);
                h.FontColor     = obj.HeaderColor;
                h.FontWeight    = 'bold';
                h.Tooltip       = 'Right-click to choose which trials are summarized';
                obj.HeaderH     = h;
            end

            for i = 1:n
                row = row + 1;
                name = obj.Metrics_(i);
                def  = C(strcmp([C.Name], name));

                lbl = uilabel(obj.GridH);
                lbl.Layout.Row    = row;
                lbl.Layout.Column = 1;
                lbl.Text          = char(def.Label);
                lbl.FontSize      = obj.FontSize_;
                lbl.FontColor     = obj.LabelColor;

                val = uilabel(obj.GridH);
                val.Layout.Row    = row;
                val.Layout.Column = 2;
                val.Text          = '--';
                val.FontSize      = obj.FontSize_ + 2;
                val.FontWeight    = 'bold';
                val.FontColor     = obj.colorFor_(def.Kind);
                val.HorizontalAlignment = 'right';

                det = [];
                if obj.ShowDetail_
                    det = uilabel(obj.GridH);
                    det.Layout.Row    = row;
                    det.Layout.Column = 3;
                    det.Text          = '';
                    det.FontSize      = max(obj.FontSize_ - 2, 7);
                    det.FontColor     = obj.LabelColor;
                    det.VerticalAlignment = 'bottom';   % sits on the value's baseline
                end

                obj.Rows_(end+1) = struct('Name',name,'LabelH',lbl,'ValueH',val,'DetailH',det);
            end

            % Empty space still answers the right-click, so the menu is
            % reachable even when few metrics are shown.
            f = uilabel(obj.GridH);
            f.Layout.Row    = row + 1;
            f.Layout.Column = [1 numel(obj.GridH.ColumnWidth)];
            f.Text          = '';
            obj.FillerH_    = f;

            obj.attachContextMenu_();
            obj.refresh();
        end

        function applyFontSize_(obj)
            % Resize the labels in place rather than rebuilding the rows:
            % the same proportions rebuildRows_ establishes, without the
            % flicker of deleting and recreating every label mid-session.
            if isempty(obj.GridH) || ~isvalid(obj.GridH), return; end
            try
                if ~isempty(obj.HeaderH) && isvalid(obj.HeaderH)
                    obj.HeaderH.FontSize = max(obj.FontSize_ - 1, 8);
                end
                for i = 1:numel(obj.Rows_)
                    r = obj.Rows_(i);
                    if isvalid(r.LabelH), r.LabelH.FontSize = obj.FontSize_;     end
                    if isvalid(r.ValueH), r.ValueH.FontSize = obj.FontSize_ + 2; end
                    if ~isempty(r.DetailH) && isvalid(r.DetailH)
                        r.DetailH.FontSize = max(obj.FontSize_ - 2, 7);
                    end
                end
            catch ME
                vprintf(3,'gui.components.SessionPerformance: unable to set font size: %s', ME.message)
            end
        end

        function c = colorFor_(obj, kind)
            % Value color for a metric kind, falling back to neutral.
            k = char(kind);
            if isfield(obj.ValueColors, k)
                c = obj.ValueColors.(k);
            else
                c = obj.ValueColors.neutral;
            end
        end

        function updateHeader_(obj)
            if isempty(obj.HeaderH) || ~isvalid(obj.HeaderH), return; end
            n = obj.Analysis.trialCount;
            if n == 0
                obj.HeaderH.Text = sprintf('%s - no trials yet', obj.TrialWindow.describe());
            else
                obj.HeaderH.Text = char(obj.TrialWindow.label(n));
            end
        end

        % -- Context menu ------------------------------------------------

        function createContextMenu_(obj)
            f = ancestor(obj.Parent,'figure');
            if isempty(f) || ~isvalid(f), return; end

            try
                cm = uicontextmenu(f);
                obj.ContextMenu  = cm;
                obj.WindowMenuH_ = uimenu(cm,'Text','Trials Included');
                obj.MetricMenuH_ = uimenu(cm,'Text','Show Metric');
                obj.FontMenuH_   = uimenu(cm,'Text','Font Size');
                uimenu(cm,'Text','Copy Summary','Separator','on', ...
                    'MenuSelectedFcn',@(~,~) obj.copySummary_());
                uimenu(cm,'Text','Reset to Defaults', ...
                    'MenuSelectedFcn',@(~,~) obj.resetToDefaults_());
                obj.addPopOutMenu_(cm);

                cm.ContextMenuOpeningFcn = @(~,~) obj.refreshMenus_();
            catch ME
                vprintf(3,'gui.components.SessionPerformance: context menu unavailable: %s', ME.message)
                obj.ContextMenu = [];
            end
        end

        function attachContextMenu_(obj)
            % Every label carries the menu, so a right-click anywhere in the
            % panel reaches it (a uigridlayout has no ContextMenu of its own).
            cm = obj.ContextMenu;
            if isempty(cm) || ~isvalid(cm), return; end

            h = obj.GridH.Children;
            for i = 1:numel(h)
                try
                    h(i).ContextMenu = cm;
                catch
                end
            end

            try
                obj.Parent.ContextMenu = cm;
            catch
                % Layout containers have no ContextMenu; the labels cover it.
            end
        end

        function refreshMenus_(obj)
            obj.refreshWindowMenu_();
            obj.refreshMetricMenu_();
            obj.refreshFontMenu_();
        end

        function refreshFontMenu_(obj)
            % Presets plus a prompt, rebuilt on open so the check mark and
            % the custom entry follow a size set programmatically.
            m = obj.FontMenuH_;
            if isempty(m) || ~isvalid(m), return; end
            delete(m.Children);

            sz = obj.FontSize_;
            for k = 1:numel(obj.FontPresets)
                n = obj.FontPresets(k);
                item = uimenu(m,'Text',sprintf('%g pt',n), ...
                    'MenuSelectedFcn',@(~,~) obj.setFontSize(n));
                item.Checked = sz == n;
            end

            uimenu(m,'Text','Larger','Separator','on', ...
                'MenuSelectedFcn',@(~,~) obj.setFontSize(sz + 2));
            uimenu(m,'Text','Smaller', ...
                'MenuSelectedFcn',@(~,~) obj.setFontSize(sz - 2));

            item = uimenu(m,'Text','Custom...','Separator','on', ...
                'MenuSelectedFcn',@(~,~) obj.promptFontSize_());
            item.Checked = ~ismember(sz, obj.FontPresets);
        end

        function promptFontSize_(obj)
            answer = obj.askUser_('Font Size', 'Caption font size (points):', ...
                num2str(obj.FontSize_));
            if isempty(answer), return; end

            n = str2double(answer);
            if ~isfinite(n) || n <= 0
                vprintf(1,'gui.components.SessionPerformance: "%s" is not a font size', answer)
                return
            end
            obj.setFontSize(n);
        end

        function refreshWindowMenu_(obj)
            % Rebuilt on open: the presets are static but the check marks
            % and the custom entries' current values are not.
            m = obj.WindowMenuH_;
            if isempty(m) || ~isvalid(m), return; end
            delete(m.Children);

            w = obj.TrialWindow;

            item = uimenu(m,'Text','All Trials', ...
                'MenuSelectedFcn',@(~,~) obj.setTrialWindow(psychophysics.TrialWindow.allTrials()));
            item.Checked = w.Mode == "All";

            for k = 1:numel(obj.WindowPresets)
                n = obj.WindowPresets(k);
                item = uimenu(m,'Text',sprintf('Last %d Trials',n), ...
                    'MenuSelectedFcn',@(~,~) obj.setTrialWindow(psychophysics.TrialWindow.lastN(n)));
                if k == 1, item.Separator = 'on'; end
                item.Checked = w.Mode == "Last" && w.N == n;
            end

            item = uimenu(m,'Text','Last N Trials...','Separator','on', ...
                'MenuSelectedFcn',@(~,~) obj.promptCount_("Last"));
            item.Checked = w.Mode == "Last" && ~ismember(w.N, obj.WindowPresets);

            item = uimenu(m,'Text','First N Trials...', ...
                'MenuSelectedFcn',@(~,~) obj.promptCount_("First"));
            item.Checked = w.Mode == "First";

            item = uimenu(m,'Text','Trial Range...', ...
                'MenuSelectedFcn',@(~,~) obj.promptRange_());
            item.Checked = w.Mode == "Range";

            uimenu(m,'Text',char("Now: " + w.label(obj.Analysis.trialCount)), ...
                'Separator','on','Enable','off');
        end

        function refreshMetricMenu_(obj)
            m = obj.MetricMenuH_;
            if isempty(m) || ~isvalid(m), return; end
            delete(m.Children);

            C = psychophysics.SessionMetrics.catalogue();
            groups = unique([C.Group],'stable');

            for gi = 1:numel(groups)
                inGroup = find(strcmp([C.Group], groups(gi)));
                for k = 1:numel(inGroup)
                    def = C(inGroup(k));
                    item = uimenu(m,'Text',char(def.Label), ...
                        'MenuSelectedFcn',@(~,~) obj.toggleMetric_(def.Name));
                    item.Checked = ismember(def.Name, obj.Metrics_);
                    if k == 1 && gi > 1, item.Separator = 'on'; end
                end
            end
        end

        function toggleMetric_(obj, name)
            % Toggle one metric, keeping the display in catalogue order so
            % the panel reads the same however the operator picked them.
            sel = obj.Metrics_;
            if ismember(name, sel)
                sel(sel == name) = [];
            else
                sel(end+1) = name;
            end
            all_ = psychophysics.SessionMetrics.metricNames();
            obj.setMetrics(all_(ismember(all_, sel)));
        end

        function promptCount_(obj, mode)
            % Prompt for a trial count. inputdlg opens its own dialog, so it
            % works from a uifigure; a cancelled or invalid entry is ignored.
            switch mode
                case "Last",  prompt = 'Summarize the last how many trials?';
                otherwise,    prompt = 'Summarize the first how many trials?';
            end

            w = obj.TrialWindow;
            if w.Mode == mode, dflt = num2str(w.N); else, dflt = '20'; end

            answer = obj.askUser_('Trials Included', prompt, dflt);
            if isempty(answer), return; end

            n = str2double(answer);
            try
                obj.setTrialWindow(psychophysics.TrialWindow(mode, n));
            catch ME
                vprintf(0,1,'gui.components.SessionPerformance: %s', ME.message)
            end
        end

        function promptRange_(obj)
            w = obj.TrialWindow;
            if w.Mode == "Range"
                dflt = sprintf('%d-%g', w.Range(1), w.Range(2));
            else
                dflt = '1-100';
            end

            answer = obj.askUser_('Trials Included', ...
                'Trial range (e.g. 20-100, or 20-end):', dflt);
            if isempty(answer), return; end

            try
                obj.setTrialWindow(psychophysics.TrialWindow.parse(answer));
            catch ME
                vprintf(0,1,'gui.components.SessionPerformance: %s', ME.message)
            end
        end

        function answer = askUser_(~, title, prompt, dflt)
            answer = '';
            try
                a = inputdlg({prompt}, title, [1 40], {dflt});
            catch ME
                vprintf(0,1,'gui.components.SessionPerformance: cannot prompt for a trial window: %s', ME.message)
                return
            end
            if isempty(a), return; end
            answer = strtrim(a{1});
        end

        function copySummary_(obj)
            try
                clipboard('copy', obj.summaryText());
                vprintf(2,'gui.components.SessionPerformance: summary copied to the clipboard')
            catch ME
                vprintf(0,1,ME)
            end
        end

        function resetToDefaults_(obj)
            obj.setTrialWindow(psychophysics.TrialWindow.allTrials());
            obj.setMetrics(psychophysics.SessionMetrics.defaultMetrics());
        end

        function names = validateMetrics_(~, names)
            names = unique(reshape(string(names),1,[]),'stable');
            known = psychophysics.SessionMetrics.metricNames();
            bad = ~ismember(names, known);
            if any(bad)
                vprintf(1,'gui.components.SessionPerformance: ignoring unknown metric(s) %s', ...
                    strjoin(names(bad), ', '))
                names = names(~bad);
            end
            if isempty(names)
                names = psychophysics.SessionMetrics.defaultMetrics();
            end
        end

        % -- Preference persistence (mirrors gui.components.NextTrial) ----------------

        function loadPreferences_(obj)
            try
                pname = obj.preferenceName_();
                if ~ispref(obj.PREF_GROUP, pname), return; end
                s = getpref(obj.PREF_GROUP, pname);

                if isfield(s,'Metrics') && ~isempty(s.Metrics)
                    obj.Metrics_ = obj.validateMetrics_(string(s.Metrics));
                end
                if isfield(s,'TrialWindow')
                    obj.Analysis.TrialWindow = psychophysics.TrialWindow.fromStruct(s.TrialWindow);
                end
                if isfield(s,'FontSize') && isscalar(s.FontSize) && isfinite(s.FontSize) ...
                        && s.FontSize > 0
                    % Applied by the rows built after this returns.
                    obj.FontSize_ = min(max(round(s.FontSize), 6), 72);
                end
                vprintf(3,'gui.components.SessionPerformance: loaded saved preferences "%s"', pname)
            catch ME
                vprintf(2,'gui.components.SessionPerformance: failed to load preferences: %s', ME.message)
            end
        end

        function savePreferences_(obj)
            try
                s = struct('Metrics', {cellstr(obj.Metrics_)}, ...
                    'TrialWindow', obj.TrialWindow.toStruct(), ...
                    'FontSize', obj.FontSize_);
                setpref(obj.PREF_GROUP, obj.preferenceName_(), s);
            catch ME
                vprintf(2,'gui.components.SessionPerformance: failed to save preferences: %s', ME.message)
            end
        end

        function n = preferenceName_(obj)
            % Preference key scoped to the hosting GUI: explicit tag, else
            % the ancestor figure Tag, else its Name, else 'default'.
            n = obj.PreferenceTag_;
            if isempty(n)
                try
                    f = ancestor(obj.Parent,'figure');
                    if ~isempty(f) && isvalid(f)
                        if ~isempty(f.Tag)
                            n = f.Tag;
                        elseif ~isempty(f.Name)
                            n = f.Name;
                        end
                    end
                catch
                end
            end
            if isempty(n), n = 'default'; end
            n = matlab.lang.makeValidName(n);
        end
    end
end
