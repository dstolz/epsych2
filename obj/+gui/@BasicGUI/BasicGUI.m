classdef BasicGUI < handle
% gui.BasicGUI  Minimal protocol-driven GUI for development and prototyping.
%
% Automatically builds a tabbed interface from an epsych.Protocol:
%   - One tab per hw.Interface with visible writable parameters
%   - One labeled panel per hw.Module within each tab
%   - gui.Parameter_Control (type='auto') for each visible writable parameter
%   - gui.Parameter_Monitor (table, right panel) for strictly Read-access parameters
%   - gui.Parameter_Update button below the tabs when RUNTIME is supplied
%
% Intended as a functional starting point for custom experiment GUIs. Subclasses
% can access every generated control via the Controls struct and modify behavior
% after construction.
%
% obj = gui.BasicGUI(Protocol)
% obj = gui.BasicGUI(Protocol, RUNTIME=R)
% obj = gui.BasicGUI(Protocol, RUNTIME=R, parent=p, colWidth=200, monitorWidth=250, pollPeriod=1)
%
% Parameters
%   Protocol         - epsych.Protocol to build controls from.
% Name-Value
%   RUNTIME          - Runtime object; enables the Parameter_Update button. Default [].
%   parent           - Parent graphics container. Creates a uifigure when empty. Default [].
%   colWidth    (1,1) double  - Approximate pixel width per parameter column. Default 200.
%   monitorWidth (1,1) double - Pixel width of right-side monitor panel. Default 250.
%   pollPeriod  (1,1) double  - Parameter_Monitor poll period in seconds. Default 1.
%
% Properties (SetAccess=protected)
%   Figure        - uifigure or supplied parent container.
%   Protocol      - The epsych.Protocol.
%   RUNTIME       - Runtime object (may be empty).
%   Controls      - Struct of gui.Parameter_Control handles keyed by Parameter.validName.
%   Monitor       - gui.Parameter_Monitor handle.
%   UpdateButton  - gui.Parameter_Update handle (empty when no RUNTIME supplied).
%   colWidth      - Column width in pixels.
%   monitorWidth  - Monitor panel width in pixels.
%
% Example
%   prot = epsych.Protocol;
%   prot.addParameter('SoftwareModule', 'Frequency', 1000, Unit='Hz');
%   g = gui.BasicGUI(prot);
%   % Access the generated control for a parameter named 'Frequency':
%   g.Controls.Frequency
%
% See also gui.Parameter_Control, gui.Parameter_Update, gui.Parameter_Monitor,
%   epsych.Protocol

    properties (SetAccess = protected)
        Figure
        Protocol    (1,1) epsych.Protocol
        RUNTIME

        Controls    (1,1) struct = struct()  % keyed by Parameter.validName
        Monitor                              % gui.Parameter_Monitor
        UpdateButton                         % gui.Parameter_Update (empty when no RUNTIME)

        colWidth     (1,1) double = 200      % px per parameter column
        monitorWidth (1,1) double = 250      % px for right monitor panel
    end

    properties (Access = private)
        ownsFigure_  (1,1) logical = false
        pollPeriod_  (1,1) double  = 1
    end

    methods

        function obj = BasicGUI(Protocol, options)
            % obj = gui.BasicGUI(Protocol)
            % obj = gui.BasicGUI(Protocol, RUNTIME=R, parent=p, colWidth=200, monitorWidth=250, pollPeriod=1)
            % Construct and display the protocol GUI.
            %
            % Parameters
            %   Protocol          - epsych.Protocol to build controls from.
            % Name-Value
            %   RUNTIME           - Runtime object; enables the Parameter_Update button.
            %   parent            - Parent graphics container. Creates uifigure if empty.
            %   colWidth    (1,1) double  - Pixel width per parameter column. Default 200.
            %   monitorWidth (1,1) double - Pixel width of monitor panel. Default 250.
            %   pollPeriod  (1,1) double  - Monitor poll period in seconds. Default 1.
            arguments
                Protocol             (1,1) epsych.Protocol
                options.RUNTIME           = []
                options.parent            = []
                options.colWidth     (1,1) double = 200
                options.monitorWidth (1,1) double = 250
                options.pollPeriod   (1,1) double = 1
            end

            obj.Protocol     = Protocol;
            obj.RUNTIME      = options.RUNTIME;
            obj.colWidth     = options.colWidth;
            obj.monitorWidth = options.monitorWidth;
            obj.pollPeriod_  = options.pollPeriod;

            obj.build_gui(options.parent);
        end

        function delete(obj)
            if ~isempty(obj.Monitor) && isvalid(obj.Monitor)
                delete(obj.Monitor);
            end
            if obj.ownsFigure_ && ~isempty(obj.Figure) && ishandle(obj.Figure)
                delete(obj.Figure);
            end
        end

    end

    methods (Access = protected)

        function build_gui(obj, parent)
            % build_gui  Create figure (if needed) and top-level layout, then dispatch.
            if isempty(parent)
                obj.Figure      = uifigure('Name', 'Protocol GUI', ...
                                           'Position', [100 100 900 600]);
                obj.ownsFigure_ = true;
            else
                obj.Figure = parent;
            end

            % Outer [1×2]: left (tabs + update button) | right (monitor)
            outerGrid               = uigridlayout(obj.Figure, [1 2]);
            outerGrid.ColumnWidth   = {'1x', obj.monitorWidth};
            outerGrid.Padding       = [4 4 4 4];
            outerGrid.ColumnSpacing = 6;

            % Left [2×1]: tab group (flex) | update button row (40 px)
            leftGrid               = uigridlayout(outerGrid, [2 1]);
            leftGrid.Layout.Row    = 1;
            leftGrid.Layout.Column = 1;
            leftGrid.RowHeight     = {'1x', 40};
            leftGrid.Padding       = [0 0 0 0];
            leftGrid.RowSpacing    = 4;

            % Right: monitor panel
            rightPanel               = uipanel(outerGrid, 'Title', 'Monitor');
            rightPanel.Layout.Row    = 1;
            rightPanel.Layout.Column = 2;

            obj.build_tabs(leftGrid);
            obj.build_monitor(rightPanel);
            obj.build_update_button(leftGrid);
        end

        function build_tabs(obj, leftGrid)
            % build_tabs  Create the uitabgroup and one tab per Interface.
            tg               = uitabgroup(leftGrid);
            tg.Layout.Row    = 1;
            tg.Layout.Column = 1;

            for i = 1:numel(obj.Protocol.Interfaces)
                iface = obj.Protocol.Interfaces(i);
                if isempty(iface.all_parameters(Access='Write'))
                    continue
                end
                tab = uitab(tg, 'Title', iface.Type);
                obj.build_interface_tab(tab, iface);
            end
        end

        function build_interface_tab(obj, tab, iface)
            % build_interface_tab  Populate one tab with scrollable module panels.
            %
            % Parameters
            %   tab   - uitab to populate.
            %   iface - hw.Interface whose modules are displayed.

            % Single-cell grid fills the tab, holds a scrollable panel
            tabGrid               = uigridlayout(tab, [1 1]);
            tabGrid.Padding       = [2 2 2 2];
            scrollPanel           = uipanel(tabGrid, 'Scrollable', 'on', 'BorderType', 'none');
            scrollPanel.Layout.Row    = 1;
            scrollPanel.Layout.Column = 1;

            % Collect visible writable params per module, preserving module order
            modules   = iface.Module;
            modParams = cell(1, numel(modules));
            for m = 1:numel(modules)
                mp = modules(m).Parameters;
                if isempty(mp)
                    modParams{m} = hw.Parameter.empty(1,0);
                    continue
                end
                keep       = [mp.Visible] & ~strcmp({mp.Access}, 'Read');
                modParams{m} = mp(keep);
            end

            activeIdx = find(~cellfun(@isempty, modParams));
            if isempty(activeIdx), return; end

            modGrid             = uigridlayout(scrollPanel, [numel(activeIdx) 1]);
            modGrid.RowHeight   = repmat({'fit'}, 1, numel(activeIdx));
            modGrid.Padding     = [4 4 4 4];
            modGrid.RowSpacing  = 6;

            for r = 1:numel(activeIdx)
                m = activeIdx(r);
                obj.build_module_panel(modGrid, r, modules(m), modParams{m});
            end
        end

        function build_module_panel(obj, parent, row, moduleObj, params)
            % build_module_panel  Create a labeled panel with Parameter_Controls.
            %
            % Parameters
            %   parent    - uigridlayout to place the panel in.
            %   row       - Grid row index for this panel.
            %   moduleObj - hw.Module whose parameters are displayed.
            %   params    - 1×N hw.Parameter array of visible writable parameters.

            if ~isempty(moduleObj.Label)
                panelTitle = moduleObj.Label;
            else
                panelTitle = moduleObj.Name;
            end

            p               = uipanel(parent, 'Title', panelTitle);
            p.Layout.Row    = row;
            p.Layout.Column = 1;

            % Column count based on available figure width at build time
            figW   = obj.Figure.Position(3);
            availW = figW - obj.monitorWidth - 30;
            nCols  = max(1, floor(availW / obj.colWidth));
            nRows  = ceil(numel(params) / nCols);

            g                 = uigridlayout(p, [nRows nCols]);
            g.RowHeight       = repmat({30}, 1, nRows);
            g.Padding         = [4 8 4 4];
            g.ColumnSpacing   = 6;
            g.RowSpacing      = 4;

            for k = 1:numel(params)
                pr = params(k);
                pc = gui.Parameter_Control(g, pr, Type='auto', autoCommit=pr.isTrigger);
                obj.Controls.(pr.validName) = pc;
            end
        end

        function build_monitor(obj, rightPanel)
            % build_monitor  Collect strictly Read-access parameters and create monitor.
            %
            % Parameters
            %   rightPanel - uipanel container for the Parameter_Monitor.
            n        = numel(obj.Protocol.Interfaces);
            allPCell = cell(1, n);
            for i = 1:n
                allPCell{i} = obj.Protocol.Interfaces(i).all_parameters();
            end

            if any(~cellfun(@isempty, allPCell))
                allP       = [allPCell{:}];
                readParams = allP(strcmp({allP.Access}, 'Read'));
            else
                readParams = hw.Parameter.empty(1,0);
            end

            obj.Monitor = gui.Parameter_Monitor(rightPanel, readParams, ...
                pollPeriod=obj.pollPeriod_, type="table");
        end

        function build_update_button(obj, leftGrid)
            % build_update_button  Create Parameter_Update in row 2 of leftGrid.
            % No button is created when RUNTIME is empty.
            %
            % Parameters
            %   leftGrid - uigridlayout whose row 2 holds the button.
            btnContainer               = uigridlayout(leftGrid, [1 1]);
            btnContainer.Layout.Row    = 2;
            btnContainer.Layout.Column = 1;
            btnContainer.Padding       = [0 0 0 0];

            if isempty(obj.RUNTIME), return; end

            obj.UpdateButton = gui.Parameter_Update(obj.RUNTIME, btnContainer);

            % Wire all non-trigger controls as watched handles
            names = fieldnames(obj.Controls);
            if isempty(names), return; end

            ctrlCell    = cellfun(@(n) obj.Controls.(n), names, 'UniformOutput', false);
            allControls = [ctrlCell{:}];
            isTrig      = arrayfun(@(c) c.Parameter.isTrigger, allControls);
            nonTrigger  = allControls(~isTrig);

            if ~isempty(nonTrigger)
                obj.UpdateButton.watchedHandles = nonTrigger;
            end
        end

    end

end
