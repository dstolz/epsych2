classdef PsychPlot < gui.PopOut
    % obj = gui.components.PsychPlot(pObj, ax)
    % Psychometric summary of a psychophysics.Detection: one metric (d',
    % A', hit rate, false-alarm rate, criterion, B'') against the stimulus
    % value, marker size following the trials behind each point.
    %
    % Everything drawn comes from pObj.Results in one read -- the values
    % and the metric over them -- so the two cannot disagree, and the plot
    % follows the analysis's Events.NewData, which it broadcasts on every
    % trial and on every change of its settings.
    %
    % Click the y label to choose the metric, the x label to choose which
    % DATA field the analysis groups the stimulus trials by (that sets
    % pObj.Parameter, so every other display over the same analysis follows
    % too). Right-click the axes for "Open in Separate Window" (see
    % gui.PopOut): a second, independent plot whose metric is its own.
    %
    % Inputs:
    %   pObj - psychophysics.Detection.
    %   ax   - Target axes (default = gca).

    properties
        ax       (1,1)

        psychObj % psychophysics.Detection

        % Metric on the y axis; one of ValidPlotTypes.
        PlotType    (1,:) char {mustBeMember(PlotType,{'DPrime','APrime','HitRate','FARate','Criterion','BPrimePrime'})} = 'DPrime';

        LineColor   (:,:) double {mustBeNonnegative,mustBeLessThanOrEqual(LineColor,1)}   = [.2 .6 1; 1 .6 .2];
        MarkerColor (:,:) double {mustBeNonnegative,mustBeLessThanOrEqual(MarkerColor,1)} = [0 .4 .8; .8 .4 0];

        logx    (1,1) logical = false
    end

    properties (SetAccess = private)
        LineH
        ScatterH

        hl_NewData
    end

    properties (Access = private)
        ContextMenuH_ = [] % right-click menu on the axes

        % The reference line, held because it is HandleVisibility 'off'
        % and findobj cannot see it: looked up by tag, it was never found,
        % so it stayed at 1 whatever the metric.
        RefH_ = []

        % Redraws skipped while the axes sit on a hidden tab, caught up
        % when the tab is shown (gui.isShown / gui.onShown).
        Stale_ (1,1) logical = false
        TabListeners_ = event.listener.empty(1,0)
    end

    properties (Dependent)
        ParameterName
    end

    properties (Constant)
        ValidPlotTypes = {'DPrime','APrime','HitRate','FARate','Criterion','BPrimePrime'};
    end

    methods (Static)
        function s = getComponentSpec()
            % s = gui.components.PsychPlot.getComponentSpec()
            % Draws into a CLASSIC axes, not a uiaxes, so add makes one
            % inside the container: pass a panel or a grid cell, never an
            % axes of your own. See gui.ComponentSpec.
            s = gui.ComponentSpec();
            s.type        = 'PsychPlot';
            s.label       = 'Psych Plot';
            s.category    = 'Displays';
            s.description = 'Psychometric plot (requires a Detection analysis)';
            s.shape       = ["psych","canvas"];
            s.canvas      = 'axes';
            s.requires    = "psych";
            s.psychTypes  = "psychophysics.Detection";
        end
    end

    methods
        function obj = PsychPlot(pObj,ax)
            % obj = PsychPlot(pObj,ax)
            %
            % pObj      psychophysics.Detection
            % ax        Target axes (default = gca)

            arguments
                pObj (1,1) psychophysics.Detection
                ax (1,1) matlab.graphics.axis.Axes = gca
            end

            obj.ax = ax;

            obj.psychObj = pObj;

            obj.hl_NewData = listener(pObj.Events,'NewData',@obj.update_plot);
            obj.TabListeners_ = gui.onShown(ax, @() obj.catchUp_());

            obj.build_context_menu_;
        end

        function delete(obj)
            % Destructor: cleans up the listeners and the context menu.
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

        function n = get.ParameterName(obj)
            n = obj.psychObj.ParameterName;
        end

        function set.PlotType(obj, v)
            obj.PlotType = v;
            obj.update_plot;
        end

        function update_plot(obj,~,~)
            % Redraw from the analysis's current Results.
            vprintf(4,'Updating PsychPlot')
            if isempty(obj.ax) || ~isvalid(obj.ax) || isempty(obj.psychObj) || ~isvalid(obj.psychObj)
                return
            end

            % On a hidden tab a redraw costs and shows nothing: defer it to
            % the moment the tab is shown.
            if ~gui.isShown(obj.ax)
                obj.Stale_ = true;
                return
            end
            obj.Stale_ = false;

            obj.ensureGraphics_();

            R = obj.psychObj.Results;
            X = R.Values;
            Y = obj.psychObj.metric(string(obj.PlotType));
            N = R.N.Trials;

            if isempty(X)
                set([obj.LineH obj.ScatterH],'XData',nan,'YData',nan);
            else
                set(obj.LineH,'XData',X,'YData',Y);
                set(obj.ScatterH,'XData',X,'YData',Y,'SizeData',N*10+1, ...
                    'CData',repmat(obj.MarkerColor(1,:),numel(X),1));
                uistack(obj.ScatterH,'top');
            end

            % Only what changed is written; a redraw per trial is enough
            % graphics traffic without rewriting what already holds.
            [refY, yl] = obj.referenceAndLimits_(Y);
            wantVisible = ~isnan(refY);
            if logical(obj.RefH_.Visible) ~= wantVisible
                obj.RefH_.Visible = wantVisible;
            end
            if wantVisible && ~isequal(obj.RefH_.YData, [refY refY])
                obj.RefH_.YData = [refY refY];
            end
            if ~isequal(obj.ax.YLim, yl)
                set(obj.ax,'YLim',yl);
            end

            if obj.logx
                obj.ax.XScale = 'log';
            end

            % Labels and titles are set only when their text changes, so a
            % trial does not re-lay out the axes for nothing.
            if ~strcmp(string(obj.ax.XLabel.String), string(obj.ParameterName))
                obj.setup_xaxis_label;
            end
            if ~strcmp(string(obj.ax.YLabel.String), string(obj.PlotType))
                obj.setup_yaxis_label;
            end
            sub = sprintf('# Stimulus Trials = %d',sum(N));
            if ~strcmp(string(obj.ax.Subtitle.String), sub)
                obj.ax.Subtitle.String = sub;
            end
            ttl = obj.psychObj.sourceLabel();
            if ~strcmp(string(obj.ax.Title.String), ttl)
                obj.ax.Title.String = ttl;
                obj.ax.Title.Interpreter = 'none';
                obj.ax.TitleHorizontalAlignment = 'right';
            end
        end

        function update_parameter(obj,hObj,~)
            % Click on an axis label: choose what it shows.
            switch hObj.Tag
                case 'abscissa'
                    % The analysis's grouping field, so every display over
                    % it follows; it recomputes and broadcasts on the set.
                    list = obj.psychObj.candidateParameters();
                    if isempty(list), return; end
                    i = find(list == obj.psychObj.ParameterField, 1);
                    if isempty(i), i = 1; end
                    [sel,ok] = listdlg('ListString',cellstr(list), ...
                        'SelectionMode','single', ...
                        'InitialValue',i,'Name','Plot', ...
                        'PromptString','Select Independent Variable:', ...
                        'ListSize',[180 150]);
                    if ~ok, return; end
                    obj.psychObj.Parameter = list(sel);

                case 'ordinate'
                    i = find(ismember(obj.ValidPlotTypes,obj.PlotType));
                    [sel,ok] = listdlg('ListString',obj.ValidPlotTypes, ...
                        'SelectionMode','single', ...
                        'InitialValue',i,'Name','Plot', ...
                        'PromptString','Select Plot Type:', ...
                        'ListSize',[180 150]);
                    if ~ok, return; end
                    obj.PlotType = obj.ValidPlotTypes{sel};
            end
        end

        function setup_xaxis_label(obj)
            x = xlabel(obj.ax,obj.ParameterName,'Tag','abscissa','Interpreter','none');
            x.ButtonDownFcn = @obj.update_parameter;
        end

        function setup_yaxis_label(obj)
            y = ylabel(obj.ax,obj.PlotType,'Tag','ordinate','Interpreter','none');
            y.ButtonDownFcn = @obj.update_parameter;
        end

        function set.psychObj(obj,pobj)
            obj.psychObj = pobj;
            obj.update_plot;
        end
    end


    methods (Access = protected)

        function c = popOutHostContainer_(obj)
            % Axes this plot was built into (gui.PopOut).
            c = obj.ax;
        end

        function h = createPopOut_(obj,container)
            % A second psychometric plot on the same analysis, in its own
            % window. gui.components.PsychPlot needs a classic axes, which
            % axes() inside the pop-out's panel provides.
            popAx = axes(container);
            h = gui.components.PsychPlot(obj.psychObj,popAx);
            h.LineColor   = obj.LineColor;
            h.MarkerColor = obj.MarkerColor;
            h.logx        = obj.logx;
            h.PlotType    = obj.PlotType;
        end
    end


    methods (Access = private)

        function catchUp_(obj)
            % A tab selection changed: draw now if this plot was skipped
            % while hidden and is shown at last.
            if obj.Stale_ && gui.isShown(obj.ax)
                obj.update_plot();
            end
        end

        function ensureGraphics_(obj)
            % The line, the markers and the reference line, made once.
            if ~isempty(obj.LineH) && isvalid(obj.LineH) && ~isempty(obj.ScatterH) && isvalid(obj.ScatterH) ...
                    && ~isempty(obj.RefH_) && isvalid(obj.RefH_)
                return
            end
            old = [obj.LineH obj.ScatterH obj.RefH_];
            if ~isempty(old), delete(old(isvalid(old))); end
            obj.ScatterH = scatter(obj.ax,nan,nan,100,'filled','Marker','s');
            obj.LineH = line(obj.ax,nan,nan,'Marker','none', ...
                'AlignVertexCenters','on', ...
                'LineWidth',2,'Color',obj.LineColor(1,:));
            obj.RefH_ = line(obj.ax,[-1 1]*1e6,[1 1],Color = 'k', ...
                AffectAutoLimits = 'off', ...
                HandleVisibility = 'off', ...
                Tag = 'reference');
            grid(obj.ax,'on');
            box(obj.ax,'on');
        end

        function [refY, yl] = referenceAndLimits_(obj, Y)
            % The landmark each metric is read against -- d' = 1, chance
            % (0.5) for A', no bias (0) for c and B'' -- and y limits that
            % keep it and the data in view. Rates are bounded to [0 1] and
            % need no landmark.
            switch obj.PlotType
                case {'HitRate','FARate'}
                    refY = NaN;
                    yl = [0 1.05];
                    return
                case 'APrime',      refY = 0.5;
                case 'DPrime',      refY = 1;
                otherwise,          refY = 0;
            end
            v = [Y(isfinite(Y)) refY];
            lo = min(v); hi = max(v);
            pad = max(0.1*(hi - lo), 0.25);
            yl = [lo - pad, hi + pad];
            if strcmp(obj.PlotType,'APrime')
                yl = [0 1];
            end
        end

        function build_context_menu_(obj)
            % The pop-out item is the whole menu here: everything else this
            % plot offers is on the clickable axis labels.
            f = ancestor(obj.ax,'figure');
            if isempty(f) || ~isvalid(f), return; end
            try
                cm = uicontextmenu(f);
                obj.ContextMenuH_ = cm;
                obj.addPopOutMenu_(cm,Separator=false);
                obj.ax.ContextMenu = cm;
            catch ME
                vprintf(3,'gui.components.PsychPlot: context menu unavailable: %s',ME.message)
                obj.ContextMenuH_ = [];
            end
        end
    end

end
