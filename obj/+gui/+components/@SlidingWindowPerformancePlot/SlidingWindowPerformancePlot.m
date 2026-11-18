classdef SlidingWindowPerformancePlot < handle
    % SlidingWindowPerformancePlot - A detection metric over trials, one line
    % per stimulus value.
    %
    %   obj = gui.components.SlidingWindowPerformancePlot(pObj, ax)
    %
    %   Plots one metric of a psychophysics.Detection as a curve over the
    %   session: the point at trial t is computed from every trial so far
    %   (windowSize = 0, cumulative) or from the last windowSize trials. The
    %   curve is pObj.windowed(windowSize) -- the analysis computes it, this
    %   class only draws it -- so it is redrawn whole on every update: a
    %   review scrubbed backwards, an offline analysis, an ExcludedTrials
    %   change all show the right curve, not one point per event received.
    %
    %   Metrics (plotType): "DPrime", "APrime", "HitRate", "Criterion" -- one
    %   line per stimulus value -- and "FARate", one line for the pooled catch
    %   trials. Right-click the axes to change the metric or the window.
    %
    %   Example:
    %       swp = gui.components.SlidingWindowPerformancePlot(D, axes(fig));
    %       swp.plotType = "HitRate";
    %       swp.windowSize = 50;   % the last 50 trials
    %
    % See also psychophysics.Detection.windowed, gui.components.PsychPlot

    properties (SetObservable)
        psychObj  % psychophysics.Detection the curve is computed by

        % Metric plotted.
        plotType (1,1) string {mustBeMember(plotType,["DPrime","APrime","HitRate","FARate","Criterion"])} = "DPrime"

        palettename (1,1) string = "lines"  % Colormap function for the lines

        MarkerSize (1,1) {mustBePositive} = 10
        Marker (1,1) char = '.'
        LineStyle (1,:) char = ':'
        LineWidth (1,1) double = 1.5

        % Trials in each window: 0 is cumulative (every trial so far).
        windowSize (1,1) double {mustBeNonnegative,mustBeInteger,mustBeFinite} = 0
    end

    properties (SetAccess = private)
        hAxes                       % Axes handle for plotting
        hLines = gobjects(0)        % One line per plotted series
        Curves = []                 % psychObj.windowed(windowSize) as last drawn
        hl_NewData                  % Listener for new data events
        cm                          % Line colours
    end

    properties (Access = private)
        built_ (1,1) logical = false
        ContextMenuH_ = []

        % The reference line, made once and moved. It is HandleVisibility
        % 'off' (kept out of the legend), which also hides it from findobj,
        % so it is held here: looking it up by tag found nothing and a new
        % one piled up on every redraw.
        RefLine_ = []
        LegendKey_ (1,1) string = ""  % series + title the legend was built for

        % Updates skipped while the axes sit on a hidden tab, caught up when
        % the tab is shown (gui.isShown / gui.onShown).
        Stale_ (1,1) logical = false
        TabListeners_ = event.listener.empty(1,0)
    end

    properties (Constant)
        WINDOW_CHOICES = [0 10 20 50 100]  % offered on the right-click menu
    end

    methods (Static)
        function s = getComponentSpec()
            % s = gui.components.SlidingWindowPerformancePlot.getComponentSpec()
            % Classic axes, like the psychometric plot. See gui.ComponentSpec.
            s = gui.ComponentSpec();
            s.type        = 'SlidingWindow';
            s.label       = 'Sliding Window';
            s.category    = 'Displays';
            s.description = 'Hit rate, FA rate, d'', A'' or c over trials, cumulative or windowed (requires a Detection analysis)';
            s.shape       = ["psych","canvas"];
            s.canvas      = 'axes';
            s.requires    = "psych";
            s.psychTypes  = "psychophysics.Detection";
        end
    end

    methods
        function obj = SlidingWindowPerformancePlot(pObj, ax)
            % obj = SlidingWindowPerformancePlot(pObj, ax)
            %
            %   pObj - psychophysics.Detection
            %   ax   - Axes for plotting (default gca)
            arguments
                pObj (1,1) psychophysics.Detection
                ax = gca
            end
            obj.hAxes = ax;
            obj.psychObj = pObj;
            obj.cm = feval(obj.palettename, 64);

            grid(obj.hAxes, 'on');
            box(obj.hAxes, 'on');
            xlabel(obj.hAxes, 'Trials');
            obj.buildContextMenu_();

            obj.hl_NewData = listener(pObj.Events, 'NewData', @obj.update);
            obj.TabListeners_ = gui.onShown(ax, @() obj.catchUp_());
            obj.built_ = true;
            obj.update();
        end

        function delete(obj)
            try
                delete(obj.hl_NewData);
                delete(obj.TabListeners_);
            catch
            end
            try
                if ~isempty(obj.ContextMenuH_) && isvalid(obj.ContextMenuH_)
                    delete(obj.ContextMenuH_);
                end
            catch
            end
        end

        function set.plotType(obj, v)
            obj.plotType = v;
            obj.redrawIfBuilt_();
        end

        function set.windowSize(obj, v)
            obj.windowSize = v;
            obj.updateIfBuilt_();
        end

        function set.Marker(obj, v),     obj.Marker = v;     obj.restyle_(); end
        function set.MarkerSize(obj, v), obj.MarkerSize = v; obj.restyle_(); end
        function set.LineStyle(obj, v),  obj.LineStyle = v;  obj.restyle_(); end
        function set.LineWidth(obj, v),  obj.LineWidth = v;  obj.restyle_(); end

        function update(obj, ~, ~)
            % Recompute the curve from the analysis and redraw it.
            if isempty(obj.hAxes) || ~isvalid(obj.hAxes) || ~isvalid(obj.psychObj), return; end
            % On a hidden tab a redraw costs and shows nothing: defer it.
            if ~gui.isShown(obj.hAxes)
                obj.Stale_ = true;
                return
            end
            obj.Stale_ = false;
            obj.Curves = obj.psychObj.windowed(obj.windowSize);
            obj.plot();
        end

        function plot(obj)
            % Draw obj.Curves as the selected metric.
            W = obj.Curves;
            if isempty(W) || isempty(obj.hAxes) || ~isvalid(obj.hAxes), return; end

            if obj.plotType == "FARate"
                Y = W.FARate;
                labels = "Catch trials";
                legendTitle = "False alarms";
            else
                Y = W.(obj.plotType);
                labels = string(W.Values);
                legendTitle = string(obj.psychObj.ParameterName);
            end
            x = W.TrialIndex;

            % New series (a value first seen, a metric switched to or from
            % the pooled false-alarm line) rebuild the lines; otherwise only
            % their data change.
            current = strings(0, 1);
            if ~isempty(obj.hLines) && all(isvalid(obj.hLines))
                current = string(get(obj.hLines, 'DisplayName'));
            end
            if numel(current) ~= numel(labels) || ~isequal(current(:), labels(:))
                delete(obj.hLines(isvalid(obj.hLines)));
                obj.hLines = gobjects(1, numel(labels));
                for i = 1:numel(labels)
                    obj.hLines(i) = line(obj.hAxes, nan, nan, ...
                        Color = obj.cm(mod(i-1, size(obj.cm,1)) + 1, :), ...
                        DisplayName = labels(i), ...
                        Marker = obj.Marker, MarkerSize = obj.MarkerSize, ...
                        LineStyle = obj.LineStyle, LineWidth = obj.LineWidth);
                end
            end
            % Only the data change per trial; style is set when a line is
            % made (and by restyle_ when a style property changes).
            for i = 1:numel(labels)
                set(obj.hLines(i), XData = x, YData = Y(:, i));
            end

            switch obj.plotType
                case "DPrime",    refY = 1;
                case "APrime",    refY = 0.5;
                case "Criterion", refY = 0;
                otherwise,        refY = NaN;
            end
            if isempty(obj.RefLine_) || ~isvalid(obj.RefLine_)
                obj.RefLine_ = yline(obj.hAxes, 0, '--k', HandleVisibility = "off", ...
                    Tag = 'reference', Visible = 'off');
            end
            wantVisible = ~isnan(refY);
            if logical(obj.RefLine_.Visible) ~= wantVisible
                obj.RefLine_.Visible = wantVisible;
            end
            if wantVisible && obj.RefLine_.Value ~= refY
                obj.RefLine_.Value = refY;
            end

            % The legend, labels and title change only with the series, the
            % metric or the window; rebuilding them on every trial made each
            % redraw re-lay out the axes.
            if obj.windowSize == 0
                ttl = "Cumulative";
            else
                ttl = sprintf("Last %d trials", obj.windowSize);
            end
            key = strjoin([obj.plotType; labels(:); legendTitle; ttl], "|");
            if key ~= obj.LegendKey_
                if isempty(labels)
                    legend(obj.hAxes, 'off');
                else
                    h = legend(obj.hAxes, Location = "eastoutside");
                    h.Title.String = legendTitle;
                end
                ylabel(obj.hAxes, obj.plotType);
                title(obj.hAxes, ttl, 'FontWeight', 'normal');
                obj.LegendKey_ = key;
            end
        end
    end

    methods (Access = private)
        function redrawIfBuilt_(obj)
            if obj.built_, obj.plot(); obj.syncMenu_(); end
        end

        function updateIfBuilt_(obj)
            if obj.built_, obj.update(); obj.syncMenu_(); end
        end

        function buildContextMenu_(obj)
            % Metric and window, the two things an operator changes.
            f = ancestor(obj.hAxes, 'figure');
            if isempty(f) || ~isvalid(f), return; end
            try
                cm_ = uicontextmenu(f);
                mt = uimenu(cm_, Text = 'Metric');
                for t = ["DPrime","APrime","HitRate","FARate","Criterion"]
                    uimenu(mt, Text = t, Tag = "metric|" + t, ...
                        MenuSelectedFcn = @(~,~) obj.choose_('plotType', t));
                end
                mw = uimenu(cm_, Text = 'Window');
                for w = obj.WINDOW_CHOICES
                    if w == 0, txt = 'Cumulative'; else, txt = sprintf('Last %d trials', w); end
                    uimenu(mw, Text = txt, Tag = "window|" + w, ...
                        MenuSelectedFcn = @(~,~) obj.choose_('windowSize', w));
                end
                obj.hAxes.ContextMenu = cm_;
                obj.ContextMenuH_ = cm_;
                obj.syncMenu_();
            catch ME
                vprintf(3, 'gui.components.SlidingWindowPerformancePlot: context menu unavailable: %s', ME.message)
            end
        end

        function catchUp_(obj)
            % A tab selection changed: update now if this plot was skipped
            % while hidden and is shown at last.
            if obj.Stale_ && gui.isShown(obj.hAxes)
                obj.update();
            end
        end

        function restyle_(obj)
            % Apply the style properties to the lines already drawn; new
            % lines take them when they are made.
            ok = obj.hLines(isgraphics(obj.hLines));
            if isempty(ok), return; end
            set(ok, Marker = obj.Marker, MarkerSize = obj.MarkerSize, ...
                LineStyle = obj.LineStyle, LineWidth = obj.LineWidth);
        end

        function choose_(obj, prop, value)
            % Menu callback; the property setter redraws.
            obj.(prop) = value;
        end

        function syncMenu_(obj)
            if isempty(obj.ContextMenuH_) || ~isvalid(obj.ContextMenuH_), return; end
            items = findall(obj.ContextMenuH_, 'Type', 'uimenu');
            for it = reshape(items, 1, [])
                tag = string(it.Tag);
                if startsWith(tag, "metric|")
                    it.Checked = extractAfter(tag, "|") == obj.plotType;
                elseif startsWith(tag, "window|")
                    it.Checked = str2double(extractAfter(tag, "|")) == obj.windowSize;
                end
            end
        end
    end
end
