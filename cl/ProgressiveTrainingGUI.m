classdef ProgressiveTrainingGUI < handle
%PROGRESSIVETRAININGGUI Configure progressive training parameters with staged edits.
%
%   This class provides a small configuration GUI for adjusting step sizes
%   and bounds associated with a hw.Parameter object.
%
%   STAGED EDIT MODEL
%     - Table edits are staged (not immediately applied to properties).
%     - Rows with staged edits are highlighted yellow.
%     - Pressing "Commit" applies all staged values/limits to the public
%       properties and clears row highlighting.
%     - Invalid edits are reverted to the previous value.
%
%   STEP SEMANTICS
%     - StepUp and StepDown are positive magnitudes.
%     - updateParameter("up")   adds StepUp to Parameter.Value.
%     - updateParameter("down") subtracts StepDown from Parameter.Value.
%     - The updated value is clamped to [MinValue, MaxValue].
%
%     IMPORTANT:
%       updateParameter() directly writes to Parameter.Value. It does not
%       perform synchronization, locking, or state checks. The caller is
%       responsible for ensuring this method is invoked only during a safe
%       execution window (e.g., inter-trial interval).
%
%   WINDOW POSITION
%     - The window position is stored in preferences under
%       'ProgressiveTrainingGUI' on deletion.
%
%   CONSTRUCTOR
%     G = ProgressiveTrainingGUI(Parameter)
%     G = ProgressiveTrainingGUI(Parameter, Name=Value,...)
%
%   NAME–VALUE OPTIONS
%     StepUp            (1,1) double
%     StepDown          (1,1) double
%     MinValue          (1,1) double
%     MaxValue          (1,1) double
%     StepUpLimits      (1,2) double
%     StepDownLimits    (1,2) double
%     MinValueLimits    (1,2) double
%     MaxValueLimits    (1,2) double
%     WindowStyle       (1,1) string   "modal" | "normal"
%
%   See also uifigure, uitable, uistyle

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

        WindowStyle (1,1) string {mustBeMember(WindowStyle,["normal","modal"])} = "modal"
    end

    properties (SetAccess = private, GetAccess = public)
        Parameter (1,1) % hw.Parameter object this GUI is configuring

        Parent
    end

    properties (Access = protected)
        ParamNameLabel  matlab.ui.control.Label
        ParamValueLabel matlab.ui.control.Label
        ParamTable      matlab.ui.control.Table
        CommitButton    matlab.ui.control.Button

        % staged values/limits (hold until Commit)
        Staged struct = struct( ...
            'StepUp',[],'StepDown',[],'MinValue',[],'MaxValue',[], ...
            'StepUpLimits',[],'StepDownLimits',[],'MinValueLimits',[],'MaxValueLimits',[])

        % staged row tracking for uistyle
        ModifiedRows (1,4) logical = false(1,4)

        StagedBG (1,3) double = [1 1 0] % yellow
    end

    methods
        function obj = ProgressiveTrainingGUI(Parameter, options)
            arguments
                Parameter % hw.Parameter

                options.parent = []

                options.MinValue (1,1) double = -inf
                options.MaxValue (1,1) double = inf
                options.StepUp   (1,1) double {mustBeFinite, mustBePositive} = 1
                options.StepDown (1,1) double {mustBeFinite, mustBePositive} = 1
                options.StepUpLimits   (1,2) double = [0 100]
                options.StepDownLimits (1,2) double = [0 100]
                options.MinValueLimits (1,2) double = [-inf inf]
                options.MaxValueLimits (1,2) double = [-inf inf]
                options.WindowStyle (1,1) string {mustBeMember(options.WindowStyle,["normal","modal"])} = "modal"
            end

            obj.Parameter = Parameter;

            for f = string(fieldnames(options))'
                obj.(f) = options.(f);
            end

            obj.createUI();
            obj.updateUIFromCommitted();
        end

        function delete(obj)
            if ~isempty(obj.Parent) && isvalid(obj.Parent) && isa(obj.Parent,'matlab.ui.Figure')
                setpref('ProgressiveTrainingGUI','Position',obj.Parent.Position);
                delete(obj.Parent)
            end
        end

        function updateParameter(obj, stepDirection)
            % updateParameter(stepDirection) adjusts Parameter.Value by:
            %   + StepUp   when stepDirection == "up"
            %   - StepDown when stepDirection == "down"
            % The result is clamped to [MinValue, MaxValue].
            %
            % NOTE: Only call during an appropriate interval where updating
            % will not interfere with other processes (e.g. ITI).

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

            % Ensure new value is within Min/Max bounds
            v = max(v, obj.MinValue);
            v = min(v, obj.MaxValue);

            obj.Parameter.Value = v;
        end
    end

    methods (Access = private)
        function createUI(obj)

            if isempty(options.parent)
                fpos = getpref('ProgressiveTrainingGUI','Position',[500 400 520 320]);
                parent = uifigure('Name','Progressive Training','Position',fpos);
                movegui(parent,'onscreen');
                parent.WindowStyle = char(obj.WindowStyle);
                parent.CloseRequestFcn = @(~,~)delete(obj);
                obj.Parent = parent;
            end

            parent = obj.Parent;

            gl = uigridlayout(parent,[4 1]);
            gl.RowHeight = {22,22,'1x',34};
            gl.ColumnWidth = {'1x'};
            gl.Padding = [12 12 12 12];
            gl.RowSpacing = 8;

            obj.ParamNameLabel = uilabel(gl,'Text',obj.Parameter.Name,'FontWeight','bold');
            obj.ParamNameLabel.Layout.Row = 1;

            obj.ParamValueLabel = uilabel(gl,'Text',obj.Parameter.ValueStr,'FontAngle','italic');
            obj.ParamValueLabel.Layout.Row = 2;

            obj.ParamTable = uitable(gl);
            obj.ParamTable.Layout.Row = 3;
            obj.ParamTable.ColumnName = {'Param', char(8805), char(8804), 'Value'};
            obj.ParamTable.ColumnEditable = [false true true true];
            obj.ParamTable.CellEditCallback = @(src,evt)obj.tableCellEdited(src,evt);
            obj.ParamTable.RowName = [];

            obj.CommitButton = uibutton(gl,'push','Text','Commit',...
                'ButtonPushedFcn',@(~,~)obj.commitButtonPushed());
            obj.CommitButton.Layout.Row = 4;
        end

        function tableCellEdited(obj,src,evt)
            r = evt.Indices(1);
            c = evt.Indices(2);

            field = obj.rowFieldName(r);
            if field == ""
                return
            end

            switch c
                case 2 % >= (lower limit)
                    v = evt.NewData;
                    if ~(isnumeric(v) && isscalar(v) && ~isnan(v))
                        src.Data{r,c} = evt.PreviousData;
                        vprintf(0,1,'Invalid input: limits must be numeric scalars.')
                        return
                    end

                    limField = field + "Limits";
                    L = obj.(limField);
                    if ~isempty(obj.Staged.(limField))
                        L = obj.Staged.(limField);
                    end
                    if isempty(L) || numel(L)~=2
                        L = [-inf inf];
                    end

                    if any(field == ["StepUp","StepDown"]) && v < 0
                        src.Data{r,c} = evt.PreviousData;
                        vprintf(0,1,'Invalid input: step limits must be nonnegative.')
                        return
                    end

                    if v > L(2)
                        src.Data{r,c} = evt.PreviousData;
                        vprintf(0,1,'Lower limit must be ≤ upper limit (%g).', L(2));
                        return
                    end
                    obj.Staged.(limField) = L;
                    src.Data{r,2} = L(1);
                    src.Data{r,3} = L(2);

                case 3 % <= (upper limit)
                    v = evt.NewData;
                    if ~(isnumeric(v) && isscalar(v) && ~isnan(v))
                        src.Data{r,c} = evt.PreviousData;
                        vprintf(0,1,'Invalid input: limits must be numeric scalars.')
                        return
                    end

                    limField = field + "Limits";
                    L = obj.(limField);
                    if ~isempty(obj.Staged.(limField))
                        L = obj.Staged.(limField);
                    end
                    if isempty(L) || numel(L)~=2
                        L = [-inf inf];
                    end

                    if any(field == ["StepUp","StepDown"]) && v <= 0
                        src.Data{r,c} = evt.PreviousData;
                        vprintf(0,1,'Invalid input: step upper limit must be > 0.')
                        return
                    end

                    if v < L(1)
                        src.Data{r,c} = evt.PreviousData;
                        vprintf(0,1,'Upper limit must be ≥ lower limit (%g).', L(1));
                        return
                    end
                    obj.Staged.(limField) = L;
                    src.Data{r,2} = L(1);
                    src.Data{r,3} = L(2);

                case 4 % Value
                    v = evt.NewData;
                    if ~(isnumeric(v) && isscalar(v) && ~isnan(v))
                        src.Data{r,c} = evt.PreviousData;
                        vprintf(0,1,'Invalid input: value must be a numeric scalar.')
                        return
                    end

                    if any(field == ["StepUp","StepDown"]) && ~(isfinite(v) && v > 0)
                        src.Data{r,c} = evt.PreviousData;
                        vprintf(0,1,'Invalid input: step size must be finite and > 0.')
                        return
                    end

                    lowerLimit = src.Data{r,2};
                    upperLimit = src.Data{r,3};
                    if v < lowerLimit || v > upperLimit
                        src.Data{r,c} = evt.PreviousData;
                        vprintf(0,1,'Value must be between %g and %g.', lowerLimit, upperLimit)
                        return
                    end

                    obj.Staged.(field) = double(v);

                otherwise
                    return
            end

            obj.ModifiedRows(r) = true;
            obj.applyRowStyles();
        end

        function commitButtonPushed(obj)
            fields = ["StepUp","StepDown","MinValue","MaxValue", ...
                "StepUpLimits","StepDownLimits","MinValueLimits","MaxValueLimits"];

            for f = fields
                if ~isempty(obj.Staged.(f))
                    obj.(f) = obj.Staged.(f);
                    obj.Staged.(f) = [];
                end
            end

            obj.ModifiedRows(:) = false;
            obj.updateUIFromCommitted();
        end

        function resetRowStyles(obj)
            if ~isempty(obj.ParamTable) && isvalid(obj.ParamTable)
                removeStyle(obj.ParamTable)
            end

            obj.Staged = structfun(@(x)[], obj.Staged,'uni',0);
            
        end

        function applyRowStyles(obj)
            if isempty(obj.ParamTable) || ~isvalid(obj.ParamTable)
                return
            end
            removeStyle(obj.ParamTable)
            st = uistyle('BackgroundColor',obj.StagedBG);
            for r = 1:numel(obj.ModifiedRows)
                if obj.ModifiedRows(r)
                    addStyle(obj.ParamTable,st,'row',r);
                end
            end
        end

        function updateUIFromCommitted(obj)
            if ~isempty(obj.ParamNameLabel) && isvalid(obj.ParamNameLabel)
                obj.ParamNameLabel.Text = string(obj.Parameter.Name);
            end
            if ~isempty(obj.ParamValueLabel) && isvalid(obj.ParamValueLabel)
                obj.ParamValueLabel.Text = "Current: " + string(obj.Parameter.ValueStr);
            end

            if ~isempty(obj.ParamTable) && isvalid(obj.ParamTable)
                obj.ParamTable.Data = obj.committedTableData();
            end

            obj.resetRowStyles();
        end

        function data = committedTableData(obj)
            data = cell(4,4);
            data(1,:) = {'Step Up',   obj.StepUpLimits(1),   obj.StepUpLimits(2),   obj.StepUp};
            data(2,:) = {'Step Down', obj.StepDownLimits(1), obj.StepDownLimits(2), obj.StepDown};
            data(3,:) = {'Minimum',   obj.MinValueLimits(1), obj.MinValueLimits(2), obj.MinValue};
            data(4,:) = {'Maximum',   obj.MaxValueLimits(1), obj.MaxValueLimits(2), obj.MaxValue};
        end

        function field = rowFieldName(~,row)
            switch row
                case 1, field = "StepUp";
                case 2, field = "StepDown";
                case 3, field = "MinValue";
                case 4, field = "MaxValue";
                otherwise, field = "";
            end
        end

    end
end
