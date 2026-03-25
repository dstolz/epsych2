classdef StaircaseTraining < handle
%STAIRCASETRAINING Configure staircase training parameters (immediate commit).
%
%   This GUI edits StepUp, StepDown, MinValue, MaxValue and their limits.
%   Edits apply immediately: any valid change in the table is written
%   directly to the corresponding public property.
%
%   CONSTRAINT POLICY (REJECT)
%     - MinValue must be <= MaxValue. Edits that would violate this are
%       rejected and reverted.
%     - Each value must lie within its corresponding limits. Edits outside
%       limits are rejected and reverted.
%
%   STATUS
%     - Validation failures are shown in a status label at the bottom.
%
%   STEP SEMANTICS
%     - StepUp and StepDown are positive magnitudes.
%     - updateParameter("up")   adds StepUp to Parameter.Value.
%     - updateParameter("down") subtracts StepDown from Parameter.Value.
%     - The updated value is clamped to [MinValue, MaxValue].
%
%   EMBEDDING
%     - Provide Parent=... to embed the GUI inside an existing container
%       (uifigure/uipanel/uigridlayout/etc.). If Parent is empty, a new
%       uifigure is created and owned by the object.
%
%   NOTE
%     - updateParameter() directly writes Parameter.Value; the caller must
%       ensure it is safe to update (synchronization is external).
%
%   CONSTRUCTOR
%     G = gui.StaircaseTraining(Parameter)
%     G = gui.StaircaseTraining(Parameter, Name=Value,...)
%
%   NAME–VALUE OPTIONS
%     Parent           handle   (default = [])
%     StepUp            (1,1) double
%     StepDown          (1,1) double
%     MinValue          (1,1) double
%     MaxValue          (1,1) double
%     StepUpLimits      (1,2) double
%     StepDownLimits    (1,2) double
%     MinValueLimits    (1,2) double
%     MaxValueLimits    (1,2) double
%     WindowStyle       (1,1) string   "alwaysontop" | "modal" | "normal" (only if Parent=[])
%
%   See also uifigure, uitable, uigridlayout

    properties (SetObservable)
        % Committed (active) values
        StepUp   (1,1) double {mustBeFinite, mustBePositive} = 1
        StepDown (1,1) double {mustBeFinite, mustBePositive} = 1
        MinValue (1,1) double = -inf
        MaxValue (1,1) double = inf

        % Limits for each field (modifiable by user of the class)
        StepUpLimits   (1,2) double = [0 100]
        StepDownLimits (1,2) double = [0 100]
        MinValueLimits (1,2) double = [-inf inf]
        MaxValueLimits (1,2) double = [-inf inf]

        StepUpResponse (1,1) string {mustBeMember(StepUpResponse,["Hit","Miss","CorrectReject","CorrectReject","FalseAlarm","Abort"])} = "Hit"
        StepDownResponse (1,1) string {mustBeMember(StepDownResponse,["Hit","Miss","CorrectReject","CorrectReject","FalseAlarm","Abort"])} = "Abort"

        WindowStyle (1,1) string {mustBeMember(WindowStyle, ["normal","alwaysontop","modal"])} = "alwaysontop"
    end

    properties (SetAccess = private, GetAccess = public)
        Parameter (1,1) % hw.Parameter object this GUI is configuring
        Parent % parent container handle (user-supplied or owned figure)
        ValueHistory (1,:) double = [] % history of committed parameter values
    end

    properties (Access = protected)
        RootGrid matlab.ui.container.GridLayout

        ParamNameLabel  matlab.ui.control.Label
        ParamValueLabel matlab.ui.control.Label
        ParamTable      matlab.ui.control.Table

        ValueHistoryAxes %matlab.ui.control.UIAxes
        ValueHistoryLine %matlab.graphics.chart.primitive.Line

        StatusLabel matlab.ui.control.Label

        OwnsParentFigure (1,1) logical = false
        ParentDestroyedListener event.listener = event.listener.empty
    end

    methods
        function obj = StaircaseTraining(Parameter, options)
            % Constructor; embed into Parent if provided, otherwise create figure.
            arguments
                Parameter % hw.Parameter

                options.Parent = []

                options.MinValue (1,1) double = -inf
                options.MaxValue (1,1) double = inf
                options.StepUp   (1,1) double {mustBeFinite, mustBePositive} = 1
                options.StepDown (1,1) double {mustBeFinite, mustBePositive} = 1
                options.StepUpLimits   (1,2) double = [0 100]
                options.StepDownLimits (1,2) double = [0 100]
                options.MinValueLimits (1,2) double = [-inf inf]
                options.MaxValueLimits (1,2) double = [-inf inf]
                options.WindowStyle (1,1) string {mustBeMember(options.WindowStyle, ["normal","alwaysontop","modal"])} = "alwaysontop"
                options.StepUpResponse (1,1) string {mustBeMember(options.StepUpResponse,["Hit","Miss","CorrectReject","CorrectReject","FalseAlarm","Abort"])} = "Hit"
                options.StepDownResponse (1,1) string {mustBeMember(options.StepDownResponse,["Hit","Miss","CorrectReject","CorrectReject","FalseAlarm","Abort"])} = "Abort"
            end

            obj.Parameter = Parameter;
            obj.Parent = options.Parent;

            obj.MinValue = options.MinValue;
            obj.MaxValue = options.MaxValue;
            obj.StepUp = options.StepUp;
            obj.StepDown = options.StepDown;
            obj.StepUpLimits = options.StepUpLimits;
            obj.StepDownLimits = options.StepDownLimits;
            obj.MinValueLimits = options.MinValueLimits;
            obj.MaxValueLimits = options.MaxValueLimits;
            obj.WindowStyle = options.WindowStyle;

            obj.validateAndReconcileInitialState();

            obj.ValueHistory = Parameter.Value;

            obj.createUI();
            obj.updateUIFromCommitted();
        end

        function delete(obj)
            % Destructor: delete owned UI and persist window position if we owned the figure.
            if ~isempty(obj.ParentDestroyedListener)
                delete(obj.ParentDestroyedListener)
            end
            if ~isempty(obj.RootGrid) && isvalid(obj.RootGrid)
                delete(obj.RootGrid)
            end
            if obj.OwnsParentFigure && ~isempty(obj.Parent) && isvalid(obj.Parent)
                setpref('StaircaseTraining', 'Position', obj.Parent.Position);
                delete(obj.Parent)
            end
        end

        function v = updateParameter(obj, stepDirection)
            % Apply a step to Parameter.Value and append to history.
            % stepDirection should be "up" or "down" (case-insensitive); anything else is a no-op.
            % The updated value is clamped to [MinValue, MaxValue]. The new value is returned.
            % The caller must ensure it is safe to update Parameter.Value when calling this method.
            % The updated value is appended to ValueHistory and the plot is refreshed.
            % Example usage: call this method from a trial-completion event listener, passing "up" or "down" based on trial outcome.
            % e.g. in a trial completion callback:
            %   if trial was a HIT
            %       G.updateParameter("down"); % make it harder
            %   elseif trial was a MISS
            %       G.updateParameter("up");   % make it easier
            %   end
            %
            % v = obj.updateParameter("up"); % returns the new parameter value after applying the step
            sd = lower(string(stepDirection));
            v = obj.Parameter.Value;

            switch sd
                case "up"
                    v = v + obj.StepUp;
                case "down"
                    v = v - obj.StepDown;
                otherwise
                    return
            end

            v = min(max(v, obj.MinValue), obj.MaxValue);

            obj.Parameter.Value = v; % direct write (caller must ensure safety)
            obj.ValueHistory(end+1) = v;

            obj.ParamValueLabel.Text = "Current: " + string(obj.Parameter.ValueStr);
            obj.updateValueHistoryPlot();

            drawnow
        end
    end

    methods (Access = private)
        function validateAndReconcileInitialState(obj)
            % Validate limit properties and clamp values to limits.
            obj.validateLimits("StepUpLimits", isStep=true);
            obj.validateLimits("StepDownLimits", isStep=true);
            obj.validateLimits("MinValueLimits", isStep=false);
            obj.validateLimits("MaxValueLimits", isStep=false);

            obj.StepUp   = min(max(obj.StepUp,   obj.StepUpLimits(1)),   obj.StepUpLimits(2));
            obj.StepDown = min(max(obj.StepDown, obj.StepDownLimits(1)), obj.StepDownLimits(2));
            obj.MinValue = min(max(obj.MinValue, obj.MinValueLimits(1)), obj.MinValueLimits(2));
            obj.MaxValue = min(max(obj.MaxValue, obj.MaxValueLimits(1)), obj.MaxValueLimits(2));

            if obj.MinValue > obj.MaxValue
                vprintf(0,1,'StaircaseTraining:InvalidMinMax', ...
                    'MinValue must be <= MaxValue.');
            end
        end

        function validateLimits(obj, propName, options)
            % Validate a 1x2 limits property.
            arguments
                obj
                propName (1,1) string
                options.isStep (1,1) logical = false
            end

            L = obj.(propName);
            if ~(isnumeric(L) && isvector(L) && numel(L) == 2 && all(~isnan(L)))
                vprintf(0,1,'StaircaseTraining:InvalidLimits', ...
                    '%s must be a 1x2 numeric vector.', propName);
            end
            L = double(L(:)).';

            if L(1) > L(2)
                vprintf(0,1,'StaircaseTraining:InvalidLimits', ...
                    '%s lower bound must be <= upper bound.', propName);
            end

            if options.isStep
                if L(1) < 0
                    vprintf(0,1,'StaircaseTraining:InvalidLimits', ...
                        '%s lower bound must be >= 0.', propName);
                end
                if L(2) <= 0
                    vprintf(0,1,'StaircaseTraining:InvalidLimits', ...
                        '%s upper bound must be > 0.', propName);
                end
            end

            obj.(propName) = L;
        end

        function createUI(obj)
            % Create UI under Parent (embedded) or inside a new owned figure.
            if isempty(obj.Parent)
                fpos = getpref('StaircaseTraining', 'Position', [500 400 300 400]);
                fig = uifigure('Name', 'Staircase Training', 'Position', fpos);
                movegui(fig, 'onscreen');
                fig.WindowStyle = char(obj.WindowStyle);
                fig.CloseRequestFcn = @(~,~)delete(obj);
                obj.Parent = fig;
                obj.OwnsParentFigure = true;
            else
                if ~isvalid(obj.Parent)
                    vprintf(0,1,'StaircaseTraining:InvalidParent','Parent is not valid.');
                end
            end

            if ~obj.OwnsParentFigure
                obj.ParentDestroyedListener = listener(obj.Parent, 'ObjectBeingDestroyed', @(~,~)delete(obj));
            end

            obj.RootGrid = uigridlayout(obj.Parent, [5 1]);
            obj.RootGrid.RowHeight = {22,22,'1x',100,22};
            obj.RootGrid.ColumnWidth = {'1x'};
            obj.RootGrid.Padding = [5 5 5 5];
            obj.RootGrid.RowSpacing = 2;

            obj.ParamNameLabel = uilabel(obj.RootGrid,'Text',"",'FontWeight','bold');
            obj.ParamNameLabel.Layout.Row = 1;

            obj.ParamValueLabel = uilabel(obj.RootGrid,'Text',"",'FontAngle','italic');
            obj.ParamValueLabel.Layout.Row = 2;

            obj.ParamTable = uitable(obj.RootGrid);
            obj.ParamTable.Layout.Row = 3;
            obj.ParamTable.ColumnName = {'Param', char(8805), char(8804), 'Value'};
            obj.ParamTable.ColumnEditable = [false true true true];
            obj.ParamTable.CellEditCallback = @(src,evt)obj.tableCellEdited(src,evt);
            obj.ParamTable.RowName = [];

            obj.ValueHistoryAxes = uiaxes(obj.RootGrid);
            obj.ValueHistoryAxes.Layout.Row = 4;
            obj.ValueHistoryAxes.XAxis.Visible = 'off';
            obj.ValueHistoryAxes.YAxis.Visible = 'off';
            obj.ValueHistoryLine = line(obj.ValueHistoryAxes, NaN, NaN, LineWidth=1, Color='k');

            obj.StatusLabel = uilabel(obj.RootGrid,'Text',"",'FontColor',[0.20 0.20 0.20]);
            obj.StatusLabel.Layout.Row = 5;
        end

        function tableCellEdited(obj, ~, evt)
            % Validate and immediately apply edits from the table.
            r = evt.Indices(1);
            c = evt.Indices(2);
            field = obj.rowFieldName(r);
            if field == ""
                return
            end

            [ok,msg] = obj.applyTableEdit(field, c, evt.NewData);

            obj.refreshRow(r);

            if ok
                obj.setStatus("");
            else
                obj.setStatus(msg, isError=true);
            end
        end

        function [ok,msg] = applyTableEdit(obj, field, col, newData)
            % Apply a table edit to properties with reject-on-violation policy.
            if col == 2 || col == 3
                idx = col - 1; % 2->1 (lower), 3->2 (upper)
                [ok,msg] = obj.applyLimitEdit(field, idx, newData);
                return
            end

            if col == 4
                [ok,msg] = obj.applyValueEdit(field, newData);
                return
            end

            ok = true;
            msg = "";
        end

        function [ok,msg] = applyLimitEdit(obj, field, idx, v)
            % Apply an edit to a lower/upper limit with validation.
            ok = false;

            if ~(isnumeric(v) && isscalar(v) && ~isnan(v))
                msg = "Limits must be numeric scalars.";
                return
            end

            limField = field + "Limits";
            L = obj.(limField);
            if isempty(L) || numel(L) ~= 2
                L = [-inf inf];
            end

            Lcand = double(L);
            Lcand(idx) = double(v);

            if Lcand(1) > Lcand(2)
                msg = "Lower limit must be ≤ upper limit.";
                return
            end

            isStep = any(field == ["StepUp","StepDown"]);
            if isStep
                if Lcand(1) < 0
                    msg = "Step limits must be ≥ 0.";
                    return
                end
                if Lcand(2) <= 0
                    msg = "Step upper limit must be > 0.";
                    return
                end
            end

            valCand = obj.(field);
            valCand = min(max(double(valCand), Lcand(1)), Lcand(2));

            if isStep
                if ~(isfinite(valCand) && valCand > 0)
                    msg = "Step value must be finite and > 0.";
                    return
                end
            end

            % Cross-field constraint (reject)
            if field == "MinValue" && valCand > obj.MaxValue
                msg = "Rejected: MinValue must be ≤ MaxValue.";
                return
            end
            if field == "MaxValue" && obj.MinValue > valCand
                msg = "Rejected: MaxValue must be ≥ MinValue.";
                return
            end

            obj.(limField) = Lcand;
            obj.(field) = valCand;

            ok = true;
            msg = "";
        end

        function [ok,msg] = applyValueEdit(obj, field, v)
            % Apply an edit to a value cell with validation.
            ok = false;

            if ~(isnumeric(v) && isscalar(v) && ~isnan(v))
                msg = "Value must be a numeric scalar.";
                return
            end

            v = double(v);

            isStep = any(field == ["StepUp","StepDown"]);
            if isStep
                if ~(isfinite(v) && v > 0)
                    msg = "Step size must be finite and > 0.";
                    return
                end
            end

            limField = field + "Limits";
            L = obj.(limField);
            if isempty(L) || numel(L) ~= 2
                L = [-inf inf];
            end

            if v < L(1) || v > L(2)
                msg = sprintf('Value must be between %g and %g.', L(1), L(2));
                return
            end

            % Cross-field constraint (reject)
            if field == "MinValue" && v > obj.MaxValue
                msg = "Rejected: MinValue must be ≤ MaxValue.";
                return
            end
            if field == "MaxValue" && obj.MinValue > v
                msg = "Rejected: MaxValue must be ≥ MinValue.";
                return
            end

            obj.(field) = v;

            ok = true;
            msg = "";
        end

        function refreshRow(obj, r)
            % Refresh one table row from committed properties.
            if isempty(obj.ParamTable) || ~isvalid(obj.ParamTable)
                return
            end
            data = obj.ParamTable.Data;
            if isempty(data)
                data = obj.committedTableData();
            end
            data(r,:) = obj.committedRowData(r);
            obj.ParamTable.Data = data;
        end

        function row = committedRowData(obj, r)
            % Return a 1x4 row cell for the given table row index.
            switch r
                case 1
                    row = {'Step Up', obj.StepUpLimits(1), obj.StepUpLimits(2), obj.StepUp};
                case 2
                    row = {'Step Down', obj.StepDownLimits(1), obj.StepDownLimits(2), obj.StepDown};
                case 3
                    row = {'Minimum', obj.MinValueLimits(1), obj.MinValueLimits(2), obj.MinValue};
                case 4
                    row = {'Maximum', obj.MaxValueLimits(1), obj.MaxValueLimits(2), obj.MaxValue};
                otherwise
                    row = {'',NaN,NaN,NaN};
            end
        end

        function updateUIFromCommitted(obj)
            % Refresh labels and table to reflect committed values.
            if ~isempty(obj.ParamNameLabel) && isvalid(obj.ParamNameLabel)
                obj.ParamNameLabel.Text = string(obj.Parameter.Name);
            end
            if ~isempty(obj.ParamValueLabel) && isvalid(obj.ParamValueLabel)
                obj.ParamValueLabel.Text = "Current: " + string(obj.Parameter.ValueStr);
            end

            obj.setStatus("");
            if ~isempty(obj.ParamTable) && isvalid(obj.ParamTable)
                obj.ParamTable.Data = obj.committedTableData();
            end
        end

        function data = committedTableData(obj)
            % Build the table data from committed properties.
            data = cell(4,4);
            data(1,:) = {'Step Up', obj.StepUpLimits(1), obj.StepUpLimits(2), obj.StepUp};
            data(2,:) = {'Step Down', obj.StepDownLimits(1), obj.StepDownLimits(2), obj.StepDown};
            data(3,:) = {'Minimum', obj.MinValueLimits(1), obj.MinValueLimits(2), obj.MinValue};
            data(4,:) = {'Maximum', obj.MaxValueLimits(1), obj.MaxValueLimits(2), obj.MaxValue};
        end

        function field = rowFieldName(~, row)
            % Map table row index to the corresponding property name.
            switch row
                case 1, field = "StepUp";
                case 2, field = "StepDown";
                case 3, field = "MinValue";
                case 4, field = "MaxValue";
                otherwise, field = "";
            end
        end

        function updateValueHistoryPlot(obj)
            % Refresh the value-history plot.
            if isempty(obj.ValueHistory) || isempty(obj.ValueHistoryAxes) || ~isvalid(obj.ValueHistoryAxes)
                if ~isempty(obj.ValueHistoryAxes) && isvalid(obj.ValueHistoryAxes)
                    cla(obj.ValueHistoryAxes);
                end
                return
            end
            obj.ValueHistoryLine.XData = 1:numel(obj.ValueHistory);
            obj.ValueHistoryLine.YData = obj.ValueHistory;
            axis(obj.ValueHistoryAxes, 'tight');
        end

        function setStatus(obj, msg, options)
            % Set the status label text (optionally as an error).
            arguments
                obj
                msg (1,1) string
                options.isError (1,1) logical = false
            end
            if isempty(obj.StatusLabel) || ~isvalid(obj.StatusLabel)
                return
            end
            obj.StatusLabel.Text = msg;
            if options.isError && strlength(msg) > 0
                obj.StatusLabel.FontColor = [0.70 0.00 0.00];
            else
                obj.StatusLabel.FontColor = [0.20 0.20 0.20];
            end
        end
    end
end
