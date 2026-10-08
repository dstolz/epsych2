classdef (Abstract) View < handle
    % gui.behavior.View  What every tab of epsych.BehaviorAnalysis is.
    %
    % A view owns ITS graphics inside a container the window gives it, reads
    % everything it shows from a behavior.Study, and changes nothing but
    % through the Study's methods -- so the Study's events are the only way a
    % view learns that something changed, and two views can never disagree.
    % The base class gives each view the Study, the container, a handle
    % struct H, a subscription to the Study's events that calls refresh with
    % the event's name, a status line it can post to, and a teardown that
    % releases its listeners and graphics.
    %
    % Subclasses implement:
    %   build(obj)            - create the graphics under obj.Parent into obj.H;
    %                           obj.H.root must be the one top-level container
    %   refresh(obj, reason)  - redraw for a Study event name ("CatalogChanged",
    %                           "ProjectChanged", "SettingsChanged",
    %                           "SelectionChanged", "ResultsChanged") or for
    %                           "show" (the window asked), never throwing for a
    %                           session that cannot be drawn
    %
    % Properties:
    %   Study     - the behavior.Study
    %   Parent    - the container the window gave this view
    %   H         - graphics handles
    %   StatusFcn - @(text) the window's status line ([] = log only)
    %
    % OPEN IN NEW FIGURE. A subclass draws each plot through plotInto_,
    % handing it the drawing as a function of the axes. That function is
    % kept, and every such axes gets "Open in New Figure" on its right-click
    % menu: openInFigure runs the same function again into an ordinary
    % MATLAB figure of its own -- so the plot is redrawn at the new size
    % rather than copied, and the figure has MATLAB's whole toolbar, menus,
    % gca and savefig. It is a SNAPSHOT: the function closes over the data
    % it drew, so the figure keeps showing it after the tab moves on to
    % another subject, session or setting -- open a second one to compare.
    % plots() lists what can be opened, which the window's View menu offers.
    %
    % See also: epsych.BehaviorAnalysis, behavior.Study

    properties (SetAccess = protected)
        Study
        Parent
        H (1,1) struct = struct()
    end

    properties
        StatusFcn = []
    end

    properties (Constant)
        FIGURE_TAG (1,:) char = 'EPsychBehaviorPlotFigure'    % on every figure openInFigure makes
        FIGURE_SIZE (1,2) double = [900 600]
    end

    properties (Access = protected)
        Listeners_ = event.listener.empty
        Refreshing_ (1,1) logical = false
        Plots_ (1,1) struct = struct()       % key -> struct Axes, Fcn, Name (plotInto_)
        PlotMenus_ (1,1) struct = struct()   % key -> the uicontextmenu carrying Open in New Figure
    end

    methods
        function obj = View(parent, study)
            arguments
                parent
                study (1,1) behavior.Study
            end
            obj.Parent = parent;
            obj.Study = study;
            obj.build();
            obj.listen_();
        end

        function delete(obj)
            % Release the Study listeners first, then the graphics, so a late
            % event cannot reach a view whose widgets are gone.
            try
                L = obj.Listeners_;
                L = L(isvalid(L));
                if ~isempty(L), delete(L); end
                obj.Listeners_ = event.listener.empty;
            catch ME
                vprintf(2, ME);
            end
            try
                if isfield(obj.H, 'root') && isgraphics(obj.H.root)
                    delete(obj.H.root);
                end
                % Context menus belong to the window, not to H.root.
                for f = reshape(string(fieldnames(obj.PlotMenus_)), 1, [])
                    if isgraphics(obj.PlotMenus_.(f)), delete(obj.PlotMenus_.(f)); end
                end
            catch ME
                vprintf(2, ME);
            end
        end

        function fig = openInFigure(obj, key, options)
            % fig = openInFigure(obj, key, Visible = true)
            % The plot drawn under key (plots() lists them), drawn again into
            % a new MATLAB figure of its own and titled with its name. A
            % snapshot: it does not follow the tab afterwards. Returns the
            % figure, or empty when nothing is drawn under key.
            arguments
                obj
                key (1,1) string
                options.Visible (1,1) logical = true
            end
            fig = gobjects(0);
            if ~isfield(obj.Plots_, key)
                obj.setStatus("Nothing is drawn there yet to open in a figure.");
                return
            end
            P = obj.Plots_.(key);
            fig = figure('Name', char(P.Name), 'NumberTitle', 'off', 'Color', 'w', ...
                'Visible', matlab.lang.OnOffSwitchState(options.Visible), 'Tag', obj.FIGURE_TAG);
            pos = fig.Position;
            fig.Position = [pos(1), pos(2) + pos(4) - obj.FIGURE_SIZE(2), obj.FIGURE_SIZE];
            ax = axes(fig);
            try
                P.Fcn(ax);
                title(ax, P.Name, 'Interpreter', 'none');
            catch ME
                vprintf(0, 1, ME);
                cla(ax, 'reset');
                text(ax, 0.5, 0.5, string(ME.message), 'Units', 'normalized', ...
                    'HorizontalAlignment', 'center', 'Interpreter', 'none');
            end
            set(groot, 'CurrentFigure', fig);    % so gca/gcf reach it from the command line
            obj.setStatus("Opened """ + P.Name + """ in a figure of its own.");
        end

        function L = plots(obj)
            % L = plots(obj)
            % What openInFigure can open now: struct array Key, Name.
            keys = reshape(string(fieldnames(obj.Plots_)), 1, []);
            names = arrayfun(@(f) obj.Plots_.(f).Name, keys);
            L = struct('Key', num2cell(keys), 'Name', num2cell(names));
        end

        function setStatus(obj, text)
            % setStatus(obj, text)
            % Post a line to the window's status bar, or log it without one.
            arguments
                obj
                text (1,1) string
            end
            if isempty(obj.StatusFcn)
                vprintf(2, '%s: %s', class(obj), text);
            else
                try
                    obj.StatusFcn(text);
                catch ME
                    vprintf(2, ME);
                end
            end
        end
    end

    methods (Abstract)
        build(obj)
        refresh(obj, reason)
    end

    methods (Access = protected)
        function [out, ok] = plotInto_(obj, key, ax, fcn, name)
            % [out, ok] = plotInto_(obj, key, ax, fcn, name)
            % Draw out = fcn(ax) -- fcn returns the plot's handle struct, as
            % every behavior.Plot figure does -- and keep fcn under key, so
            % "Open in New Figure" on ax's right-click menu, and
            % openInFigure(key), can draw it again. fcn must close over the
            % data, not over the view. A draw that throws writes its message
            % into ax, forgets key, and returns ok false with out [].
            arguments
                obj
                key (1,1) string
                ax (1,1)
                fcn (1,1) function_handle
                name (1,1) string
            end
            out = [];
            ok = false;
            try
                out = fcn(ax);
                ok = true;
            catch ME
                vprintf(0, 1, ME);
                cla(ax);
                text(ax, 0.5, 0.5, string(ME.message), 'Units', 'normalized', ...
                    'HorizontalAlignment', 'center', 'Color', [0.35 0.38 0.42], 'Interpreter', 'none');
            end
            if ok
                obj.Plots_.(key) = struct('Axes', ax, 'Fcn', fcn, 'Name', name);
            elseif isfield(obj.Plots_, key)
                obj.Plots_ = rmfield(obj.Plots_, key);
            end
            obj.attachPlotMenu_(key, ax);
        end

        function forgetPlot_(obj, key)
            % forgetPlot_(obj, key)
            % The axes under key was cleared: nothing there to open now.
            if isfield(obj.Plots_, key)
                ax = obj.Plots_.(key).Axes;
                obj.Plots_ = rmfield(obj.Plots_, key);
                if isgraphics(ax)
                    obj.attachPlotMenu_(key, ax);    % a cla(ax, 'reset') took the menu
                end
            end
        end

        function attachPlotMenu_(obj, key, ax)
            % Give ax -- and what is drawn in it, since a heatmap's image
            % covers every point a right-click could land on -- the menu
            % carrying Open in New Figure. A menu the view already gave the
            % axes (the Subject tab's overlay) gains the item; otherwise the
            % axes gets a menu of its own. Re-run after every draw: a plot
            % that resets its axes (psignifit's) takes the menu with it.
            if ~isgraphics(ax), return, end
            if isfield(obj.PlotMenus_, key) && isgraphics(obj.PlotMenus_.(key))
                m = obj.PlotMenus_.(key);
            else
                m = ax.ContextMenu;
                if isempty(m) || ~isgraphics(m)
                    m = uicontextmenu(ancestor(ax, 'figure'));
                end
                sep = ~isempty(m.Children);
                uimenu(m, 'Text', 'Open in New Figure', 'Separator', matlab.lang.OnOffSwitchState(sep), ...
                    'Tag', 'BehaviorView:OpenInFigure', 'MenuSelectedFcn', @(~,~) obj.openInFigure(key));
                obj.PlotMenus_.(key) = m;
            end
            ax.ContextMenu = m;
            for c = reshape(ax.Children, 1, [])
                if isempty(c.ContextMenu)
                    c.ContextMenu = m;
                end
            end
        end

        function listen_(obj)
            names = ["CatalogChanged" "ProjectChanged" "SettingsChanged" "SelectionChanged" "ResultsChanged"];
            for name = names
                obj.Listeners_(end+1) = addlistener(obj.Study, name, @(~,~) obj.onStudyEvent_(name));
            end
        end

        function onStudyEvent_(obj, name)
            % A view that throws from a listener would stop the event reaching
            % the other views; it reports instead. A refresh that triggers the
            % event it is listening to (mirroring a plot's menu into Settings)
            % is not re-entered.
            if obj.Refreshing_ || ~isvalid(obj)
                return
            end
            obj.Refreshing_ = true;
            cleanup = onCleanup(@() obj.doneRefreshing_());
            try
                obj.refresh(name);
            catch ME
                vprintf(0, 1, ME);
            end
            delete(cleanup);
        end

        function doneRefreshing_(obj)
            if isvalid(obj)
                obj.Refreshing_ = false;
            end
        end
    end
end
