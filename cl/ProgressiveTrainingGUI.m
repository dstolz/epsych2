classdef ProgressiveTrainingGUI < handle
%PROGRESSIVETRAININGGUI Modal GUI for configuring progressive training parameters.
%
%   This class provides a modal configuration interface for adjusting
%   step sizes and bounds associated with a hw.Parameter object. The GUI
%   operates in a staged-edit model: user edits are not applied to class
%   properties until explicitly committed.
%
%   VALIDATION RULES
%     - StepUp and StepDown must be finite, nonnegative scalars.
%     - StepUp represents a positive increment added to the current
%       Parameter.Value when stepping "up".
%     - StepDown represents a positive decrement subtracted from the
%       current Parameter.Value when stepping "down".
%     - Limits (≥, ≤) must be numeric scalars.
%     - Lower bound must be ≤ upper bound.
%     - Value must be numeric scalar within the displayed limits.
%     - Invalid edits are reverted to the previous value.
%
%   STAGED EDIT BEHAVIOR
%     - Any valid edit to a row stages that row.
%     - Staged rows are highlighted in yellow using uistyle.
%     - Staged values are stored internally in the Staged struct.
%     - Pressing "Commit" copies all staged values/limits to the
%       corresponding public properties and clears row highlighting.
%
%   PARAMETER UPDATE
%     updateParameter(stepDirection) modifies Parameter.Value by:
%       + StepUp   when stepDirection == "up"
%       - StepDown when stepDirection == "down"
%
%     StepUp and StepDown are always treated as positive magnitudes.
%     Stepping "down" subtracts StepDown from the current value;
%     Stepping "up" adds StepUp to the current value.
%
%     The updated value is clamped to the closed interval
%       [MinValue, MaxValue].
%
%     IMPORTANT:
%       updateParameter() directly writes to Parameter.Value. It does not
%       perform synchronization, locking, or state checks. The caller is
%       responsible for ensuring this method is invoked only during a
%       safe execution window (e.g., inter-trial interval) where updating
%       the underlying parameter will not interfere with acquisition,
%       stimulus delivery, or other time-critical processes.
%
%   WINDOW BEHAVIOR
%     - Window position is stored in preferences under
%       'ProgressiveTrainingGUI'.
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
%


    properties (SetObservable)

        % Committed (active) values
        StepUp   (1,1) double {mustBeFinite}
        StepDown (1,1) double {mustBeFinite}
        MinValue (1,1) double
        MaxValue (1,1) double

        % Limits for each field (modifiable by user of the class)
        StepUpLimits   (1,2) double
        StepDownLimits (1,2) double
        MinValueLimits (1,2) double
        MaxValueLimits (1,2) double
    end

    properties (SetAccess = private, GetAccess = public)
        Parameter % hw.Parameter object this GUI is configuring
        UIFigure matlab.ui.Figure
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

                options.MinValue (1,1) = -inf
                options.MaxValue (1,1) = inf
                options.StepUp   (1,1) = 1
                options.StepDown (1,1) = 1
                options.StepUpLimits   (1,2) = [0 100]
                options.StepDownLimits (1,2) = [-100 0]
                options.MinValueLimits (1,2) = [-inf inf]
                options.MaxValueLimits (1,2) = [-inf inf]
                options.WindowStyle (1,:) char {mustBeMember(options.WindowStyle,{'normal','modal','docked','floating'})} = 'modal'
            end

            obj.Parameter = Parameter;


            for f = string(fieldnames(options))'
                obj.(f) = options.(f);
            end

            obj.createUI();
            obj.updateUIFromCommitted();
        end

        function delete(obj)
            if ~isempty(obj.UIFigure) && isvalid(obj.UIFigure)
                setpref('ProgressiveTrainingGUI','Position',obj.UIFigure.Position);
                delete(obj.UIFigure)
            end
        end



        function updateParameter(obj,stepDirection)
            % updateParameter(stepDirection) adjusts Parameter.Value by:
            %   + StepUp   when stepDirection == "up"
            %   - StepDown when stepDirection == "down"
            % The result is clamped to [MinValue, MaxValue].
            %
            % NOTE: This function should only be called during the appropriate interval when 
            % updating will not interfere with other processes (e.g. during inter-trial interval).
            v = obj.Parameter.Value;
            switch lower(stepDirection)
                case "up"
                    v = v + obj.StepUp;
                case "down"
                    v = v - obj.StepDown;
            end

            % Ensure new value is within Min/Max bounds
            v = max(v, obj.MinValue);
            v = min(v, obj.MaxValue);

            % Apply the current Value to the Parameter
            obj.Parameter.Value = v;
        end
    end

    methods (Access = private)
        function createUI(obj)
            fpos = getpref('ProgressiveTrainingGUI','Position',[500 400 520 320]);
            fig = uifigure('Name','Progressive Training','Position',fpos);
            movegui(fig,'onscreen');
            fig.WindowStyle = options.WindowStyle;
            fig.CloseRequestFcn = @(~,~)delete(obj);
            obj.UIFigure = fig;

            gl = uigridlayout(fig,[4 1]);
            gl.RowHeight = {22,22,'1x',34};
            gl.ColumnWidth = {'1x'};
            gl.Padding = [12 12 12 12];
            gl.RowSpacing = 8;

            obj.ParamNameLabel = uilabel(gl,'Text',"",'FontWeight','bold');
            obj.ParamNameLabel.Layout.Row = 1;

            obj.ParamValueLabel = uilabel(gl,'Text',"",'FontAngle','italic');
            obj.ParamValueLabel.Layout.Row = 2;

            obj.ParamTable = uitable(gl);
            obj.ParamTable.Layout.Row = 3;
            obj.ParamTable.ColumnName = {'Name', char(8805), char(8804), 'Value'};
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

            field = src.Data{r,1};

            switch c
                case 2 % >= (lower limit)
                    v = evt.NewData;
                    if ~(isnumeric(v) && isscalar(v))
                        src.Data{r,c} = evt.PreviousData;
                        vprintf(0,1,'Invalid input: limits must be numeric scalars.')
                        return
                    end

                    % Determine current (committed) limits, then overwrite staged side
                    limField = field + "Limits";
                    L = obj.(limField);
                    if ~isempty(obj.Staged.(limField))
                        L = obj.Staged.(limField);
                    end
                    
                    if v > L(2)
                        src.Data{r,c} = evt.PreviousData;
                        vprintf(0,1,'Lower limit must be ≤ upper limit (%g).', L(2))
                        return
                    end
                    L(1) = double(v);

                    obj.Staged.(limField) = L;

                    % Keep table consistent
                    src.Data{r,2} = L(1);
                    src.Data{r,3} = L(2);

                case 3 % <= (upper limit)
                    v = evt.NewData;
                    if ~(isnumeric(v) && isscalar(v))
                        src.Data{r,c} = evt.PreviousData;
                        vprintf(0,1,'Invalid input: limits must be numeric scalars.')
                        return
                    end

                    % Determine current (committed) limits, then overwrite staged side
                    limField = field + "Limits";
                    L = obj.(limField);
                    if ~isempty(obj.Staged.(limField))
                        L = obj.Staged.(limField);
                    end
                    
                    if v < L(1)
                        src.Data{r,c} = evt.PreviousData;
                        vprintf(0,1,'Upper limit must be ≥ lower limit (%g).', L(1))
                        return
                    end
                    L(2) = double(v);

                    obj.Staged.(limField) = L;

                    % Keep table consistent
                    src.Data{r,2} = L(1);
                    src.Data{r,3} = L(2);


                case 4 % Value
                    v = evt.NewData;
                    if ~(isnumeric(v) && isscalar(v))
                        src.Data{r,c} = evt.PreviousData;
                        vprintf(0,1,'Invalid input: value must be a numeric scalar.')
                        return
                    end

                    % Check if value is within limits
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
            obj.resetRowStyles();
            obj.updateUIFromCommitted();
        end

        function resetRowStyles(obj)
            if ~isempty(obj.ParamTable) && isvalid(obj.ParamTable)
                removeStyle(obj.ParamTable)
            end
            obj.Staged = structfun(@(a) [],obj.Staged,'uni',0);
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

 

        
    end
end
