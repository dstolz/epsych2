classdef AdaptiveTraining < handle
%ADAPTIVETRAINING Configure adaptive training step rules (immediate commit).
%
%   This GUI edits the step rule that drives a single hw.Parameter during
%   progressive training: the step magnitudes, the bounds they are clamped
%   to, and -- under Advanced -- the VALUE SPACE the steps are taken in.
%
%   Edits apply immediately: any valid change is written directly to the
%   corresponding public property. Invalid edits are rejected, the widget is
%   reverted, and the reason is shown in the status line.
%
%   VALUE SPACES (ScaleType)
%     An adaptive track does not have to walk in equal native-unit steps. The step
%     magnitudes StepUp/StepDown always mean "this many parameter units at
%     the reference value"; ScaleType decides how the step grows or shrinks
%     as the value moves away from that reference:
%
%       "linear"      v -> v +/- Step. The reference is irrelevant.
%       "logarithmic" Proportional stepping: v -> v * exp(+/-Step/Ref), so a
%                     step is a fixed FRACTION of the reference and the
%                     ladder is geometric. Requires positive values.
%       "power"       v -> ((v^p) +/- Step*p*Ref^(p-1))^(1/p), with
%                     p = ScaleExponent. Steps compress (p<1) or expand
%                     (p>1) as the value rises -- the Stevens-law spacing a
%                     perceptual scale usually wants.
%       "piecewise"   Step magnitudes come from the Breakpoints table: the
%                     last row whose From value is <= the current value.
%                     Below the first breakpoint the StepUp/StepDown fields
%                     apply. Coarse steps far from threshold, fine near it.
%
%     Every space is calibrated so that AT the reference the step equals the
%     magnitude typed in. Switching space therefore never silently rescales
%     the ladder the operator already knows; it only changes how it spaces
%     out away from the reference. The preview line under the fields always
%     names the next up and down value in native units.
%
%   CONSTRAINT POLICY (REJECT)
%     - MinValue must be <= MaxValue. Edits that would violate this are
%       rejected and reverted.
%     - Each value must lie within its corresponding limits. Edits outside
%       limits are rejected and reverted.
%
%   STEP SEMANTICS
%     - StepUp and StepDown are positive magnitudes.
%     - updateParameter("up")   moves Parameter.Value up by StepUp.
%     - updateParameter("down") moves Parameter.Value down by StepDown.
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
%     G = gui.AdaptiveTraining(Parameter)
%     G = gui.AdaptiveTraining(Parameter, Name=Value,...)
%
%   NAME-VALUE OPTIONS
%     Parent           handle   (default = [])
%     StepUp            (1,1) double
%     StepDown          (1,1) double
%     MinValue          (1,1) double
%     MaxValue          (1,1) double
%     StepUpLimits      (1,2) double
%     StepDownLimits    (1,2) double
%     MinValueLimits    (1,2) double
%     MaxValueLimits    (1,2) double
%     ScaleType         (1,1) string   "linear" | "logarithmic" | "power" | "piecewise"
%     ScaleExponent     (1,1) double   power-law exponent (ScaleType="power")
%     ScaleReference    (1,1) double   value the step magnitude is calibrated at (NaN = auto)
%     Breakpoints       (:,3) double   [FromValue StepUp StepDown] rows (ScaleType="piecewise")
%     ShowAdvanced      (1,1) logical  open the Advanced section on creation
%     WindowStyle       (1,1) string   "alwaysontop" | "modal" | "normal" (only if Parent=[])
%
%   Documentation: documentation/gui/AdaptiveTraining.md
%   See also gui.eval_adaptive_training_mode, uifigure, uitable, uigridlayout

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

        % Value space the steps are taken in
        ScaleType (1,1) string {mustBeMember(ScaleType,["linear","logarithmic","power","piecewise"])} = "linear"
        ScaleExponent (1,1) double {mustBeFinite, mustBePositive} = 0.5
        ScaleReference (1,1) double = NaN % NaN = resolve automatically
        Breakpoints (:,3) double = zeros(0,3) % [FromValue StepUp StepDown]

        StepUpResponse (1,1) string {mustBeMember(StepUpResponse,["Hit","Miss","CorrectReject","FalseAlarm","Abort"])} = "Hit"
        StepDownResponse (1,1) string {mustBeMember(StepDownResponse,["Hit","Miss","CorrectReject","FalseAlarm","Abort"])} = "Abort"

        ShowAdvanced (1,1) logical = false

        WindowStyle (1,1) string {mustBeMember(WindowStyle, ["normal","alwaysontop","modal"])} = "alwaysontop"
    end

    properties (SetAccess = private, GetAccess = public)
        Parameter (1,1) % hw.Parameter object this GUI is configuring
        Parent % parent container handle (user-supplied or owned figure)
        ValueHistory (1,:) double = [] % history of committed parameter values
        StepDirections (1,:) double = [] % +1 up, -1 down, 0 for the starting value
    end

    properties (Constant, Access = protected)
        PREFERENCE_TAG = 'AdaptiveTraining'
        DEFAULT_SIZE = [400 560] % [width height] of an owned figure, Advanced collapsed
        ADVANCED_HEIGHT = 232 % rows the Advanced section takes when open
        COLOR_UP    = [0.85 0.33 0.10]
        COLOR_DOWN  = [0.00 0.45 0.74]
        COLOR_START = [0.45 0.45 0.45]
        COLOR_TRACE = [0.30 0.30 0.30]
        COLOR_BOUND = [0.60 0.60 0.60]
        COLOR_ERROR = [0.70 0.00 0.00]
        COLOR_MUTED = [0.35 0.35 0.35]
    end

    properties (Access = protected)
        RootGrid matlab.ui.container.GridLayout

        ParamNameLabel  matlab.ui.control.Label
        ParamValueLabel matlab.ui.control.Label
        ResponseLabel   matlab.ui.control.Label
        AdvancedButton  matlab.ui.control.StateButton

        SettingsPanel matlab.ui.container.Panel
        ValueFields   struct = struct() % one uieditfield per settable field
        UnitLabels    struct = struct()

        AdvancedPanel   matlab.ui.container.Panel
        AdvancedGrid    matlab.ui.container.GridLayout
        ScaleDropDown   matlab.ui.control.DropDown
        ExponentField   matlab.ui.control.NumericEditField
        ExponentLabel   matlab.ui.control.Label
        ReferenceField  matlab.ui.control.NumericEditField
        ReferenceLabel  matlab.ui.control.Label
        ScaleHelpLabel  matlab.ui.control.Label
        AdvancedTabs    matlab.ui.container.TabGroup
        LimitsTab       matlab.ui.container.Tab
        BreakpointTab   matlab.ui.container.Tab
        LimitsTable     matlab.ui.control.Table
        BreakpointTable matlab.ui.control.Table
        BreakpointGrid  matlab.ui.container.GridLayout

        PreviewLabel matlab.ui.control.Label

        ValueHistoryAxes matlab.ui.control.UIAxes
        ValueHistoryLine % stair trace through the committed values
        ValueHistoryDots % per-step markers, coloured by direction
        CurrentMarker    % emphasised marker on the newest value
        CurrentText      matlab.graphics.primitive.Text
        MinLine          % ConstantLine at MinValue
        MaxLine          % ConstantLine at MaxValue

        StatusLabel matlab.ui.control.Label

        OwnsParentFigure (1,1) logical = false
        ParentDestroyedListener event.listener = event.listener.empty

        UIReady (1,1) logical = false % property set methods refresh only once the UI exists
        Committing (1,1) logical = false % a widget commit is under way; it refreshes once when it ends
        LastStepMessage (1,1) string = "" % latch, so a rule that cannot step logs once
        AdvancedHeightApplied (1,1) double = 0 % rows currently given to the Advanced section
    end


    methods
        function obj = AdaptiveTraining(Parameter, options)
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
                options.ScaleType (1,1) string {mustBeMember(options.ScaleType,["linear","logarithmic","power","piecewise"])} = "linear"
                options.ScaleExponent (1,1) double {mustBeFinite, mustBePositive} = 0.5
                options.ScaleReference (1,1) double = NaN
                options.Breakpoints (:,3) double = zeros(0,3)
                % No default: "not stated" has to stay distinguishable from
                % "stated as false", since unstated defers to the operator's
                % remembered preference.
                options.ShowAdvanced (1,1) logical
                options.WindowStyle (1,1) string {mustBeMember(options.WindowStyle, ["normal","alwaysontop","modal"])} = "alwaysontop"
                options.StepUpResponse (1,1) string {mustBeMember(options.StepUpResponse,["Hit","Miss","CorrectReject","FalseAlarm","Abort"])} = "Hit"
                options.StepDownResponse (1,1) string {mustBeMember(options.StepDownResponse,["Hit","Miss","CorrectReject","FalseAlarm","Abort"])} = "Abort"
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
            obj.ScaleExponent = options.ScaleExponent;
            obj.ScaleReference = options.ScaleReference;
            obj.Breakpoints = options.Breakpoints;
            obj.ScaleType = options.ScaleType;
            obj.StepUpResponse = options.StepUpResponse;
            obj.StepDownResponse = options.StepDownResponse;
            obj.WindowStyle = options.WindowStyle;

            % The operator's own preference decides whether Advanced starts
            % open; an explicit ShowAdvanced= from the caller outranks it.
            if isfield(options,'ShowAdvanced')
                obj.ShowAdvanced = options.ShowAdvanced;
            else
                obj.ShowAdvanced = getpref(obj.PREFERENCE_TAG, 'ShowAdvanced', false);
            end

            obj.validateAndReconcileInitialState();

            % An unwritten parameter starts an empty history, not a bogus point.
            obj.ValueHistory = double.empty(1,0);
            obj.StepDirections = double.empty(1,0);
            if isnumeric(Parameter.Value) && isscalar(Parameter.Value)
                obj.ValueHistory = Parameter.Value;
                obj.StepDirections = 0;
            end

            obj.createUI();
            obj.UIReady = true;
            obj.refreshUI();
        end

        function delete(obj)
            % Destructor: delete owned UI and persist window position if we owned the figure.
            if ~isempty(obj.ParentDestroyedListener)
                delete(obj.ParentDestroyedListener)
            end
            setpref(obj.PREFERENCE_TAG, 'ShowAdvanced', obj.ShowAdvanced);
            if ~isempty(obj.RootGrid) && isvalid(obj.RootGrid)
                delete(obj.RootGrid)
            end
            if obj.OwnsParentFigure && ~isempty(obj.Parent) && isvalid(obj.Parent)
                setpref(obj.PREFERENCE_TAG, 'Position', obj.Parent.Position);
                delete(obj.Parent)
            end
        end

        function v = updateParameter(obj, stepDirection)
            % Apply a step to Parameter.Value and append to history.
            % stepDirection should be "up" or "down" (case-insensitive); anything else is a no-op.
            % The step is taken in the configured value space (see ScaleType) and the
            % result is clamped to [MinValue, MaxValue]. The new value is returned.
            % The caller must ensure it is safe to update Parameter.Value when calling this method.
            % The updated value is appended to ValueHistory and the plot is refreshed.
            %
            % e.g. in a trial completion callback:
            %   if trial was a HIT
            %       G.updateParameter("down"); % make it harder
            %   elseif trial was a MISS
            %       G.updateParameter("up");   % make it easier
            %   end
            sd = lower(string(stepDirection));
            v = obj.Parameter.Value;

            if ~any(sd == ["up","down"])
                return
            end

            % A parameter the dispatcher has not written yet has an empty
            % Value: training mode can be switched on from a checkbox or a
            % phase load before the first trial. There is nothing to step
            % away from, so say so and leave it alone.
            if ~gui.AdaptiveTraining.isSteppable(v)
                obj.setStatus("Waiting for the first value of " + ...
                    string(obj.Parameter.Name) + ".", isError=false);
                return
            end

            nv = namedargs2cell(obj.stepOptions(v));
            [v, info] = obj.stepValue(v, sd, nv{:});

            % A rule the current value cannot be stepped in (a logarithmic
            % ladder that has reached zero) reports once, not once a trial.
            if ~info.Ok
                if info.Message ~= obj.LastStepMessage
                    vprintf(0,1,'%s adaptive step skipped: %s', obj.Parameter.Name, info.Message);
                    obj.LastStepMessage = info.Message;
                end
                obj.setStatus(info.Message, isError=true);
                return
            end
            obj.LastStepMessage = "";

            obj.Parameter.Value = v; % direct write (caller must ensure safety)
            obj.ValueHistory(end+1) = v;
            obj.StepDirections(end+1) = info.Direction;

            obj.refreshCurrentValue();
            obj.refreshPreview(); % the preview follows the value, not the session start
            obj.updatePlot();

            % No drawnow here. During a session this runs from a NewData
            % listener, between a trial ending and the next one being
            % dispatched, and a drawnow there renders every pending update in
            % every window while the subject waits. MATLAB draws when the
            % callback that got here returns -- the timer tick, or the
            % operator's button press -- which is soon enough for a plot.
        end

        function resetHistory(obj)
            % Discard the plotted history and restart it from the current value.
            obj.ValueHistory = double.empty(1,0);
            obj.StepDirections = double.empty(1,0);
            if obj.hasCurrentValue()
                obj.ValueHistory = obj.Parameter.Value;
                obj.StepDirections = 0;
            end
            obj.refreshPreview();
            obj.updatePlot();
        end

        % The four step fields and their edit limits redraw when a script
        % assigns them, as the value-space properties below always have.
        % Assigning them does not re-validate: a script is trusted the way
        % the constructor's options are, and the fields' reject-on-violation
        % rules belong to the operator's edits.
        function set.StepUp(obj, value)
            obj.StepUp = value;
            obj.propertyChanged();
        end

        function set.StepDown(obj, value)
            obj.StepDown = value;
            obj.propertyChanged();
        end

        function set.MinValue(obj, value)
            obj.MinValue = value;
            obj.propertyChanged();
        end

        function set.MaxValue(obj, value)
            obj.MaxValue = value;
            obj.propertyChanged();
        end

        function set.StepUpLimits(obj, value)
            obj.StepUpLimits = value;
            obj.propertyChanged();
        end

        function set.StepDownLimits(obj, value)
            obj.StepDownLimits = value;
            obj.propertyChanged();
        end

        function set.MinValueLimits(obj, value)
            obj.MinValueLimits = value;
            obj.propertyChanged();
        end

        function set.MaxValueLimits(obj, value)
            obj.MaxValueLimits = value;
            obj.propertyChanged();
        end

        function set.ScaleType(obj, value)
            obj.ScaleType = value;
            obj.onScaleTypeChanged();
        end

        function set.ScaleExponent(obj, value)
            obj.ScaleExponent = value;
            obj.refreshUI();
        end

        function set.ScaleReference(obj, value)
            obj.ScaleReference = value;
            obj.refreshUI();
        end

        function set.Breakpoints(obj, value)
            obj.Breakpoints = gui.AdaptiveTraining.sortBreakpoints(value);
            obj.refreshUI();
        end

        function set.ShowAdvanced(obj, value)
            obj.ShowAdvanced = value;
            obj.applyAdvancedVisibility();
        end
    end

    methods (Static)
        [value, info] = stepValue(currentValue, direction, options)
        tf = isSteppable(value)
        B = sortBreakpoints(B)
    end

    methods (Access = protected)
        createUI(obj)
        refreshUI(obj)
        refreshPreview(obj)
        updatePlot(obj)
    end

    methods (Access = private)
        % Widget callbacks cannot assign to a property from an anonymous
        % function, so each settable rule field gets a one-line setter.
        function setShowAdvanced(obj, tf)
            obj.ShowAdvanced = logical(tf);
        end

        function setScaleType(obj, value)
            obj.ScaleType = string(value);
        end

        function setScaleExponent(obj, value)
            obj.ScaleExponent = value;
        end

        function setScaleReference(obj, value)
            obj.ScaleReference = value;
        end

        function propertyChanged(obj)
            % Redraw after a script's assignment. A widget commit assigns
            % up to two of these properties and then refreshes once itself;
            % each refresh reads Parameter.Value, a device round trip on a
            % hardware backend, so the per-property redraw stands down.
            if ~obj.Committing
                obj.refreshUI();
            end
        end

        function endCommit(obj)
            % onCleanup target for the widget commits: never leave the flag
            % set, or every later scripted assignment would stop redrawing.
            obj.Committing = false;
        end

        function opts = stepOptions(obj, currentValue)
            % Marshal the committed rule into the argument struct stepValue takes.
            %
            % currentValue is passed in by callers that have already read it.
            % On a hardware backend hw.Parameter.Value is a device round trip
            % that rethrows whatever the backend throws, so a display that
            % reads it once per widget it fills would put several transactions
            % behind every keystroke.
            arguments
                obj
                currentValue = []
            end
            opts = struct( ...
                'StepUp', obj.StepUp, ...
                'StepDown', obj.StepDown, ...
                'ScaleType', obj.ScaleType, ...
                'ScaleExponent', obj.ScaleExponent, ...
                'ScaleReference', obj.referenceValue(currentValue), ...
                'Breakpoints', obj.Breakpoints, ...
                'MinValue', obj.MinValue, ...
                'MaxValue', obj.MaxValue);
        end

        function tf = hasCurrentValue(obj)
            % True when the parameter holds a value a rule can be applied to.
            % Reads the parameter; prefer isSteppable where the value is in hand.
            tf = gui.AdaptiveTraining.isSteppable(obj.Parameter.Value);
        end

        function r = referenceValue(obj, currentValue)
            % Resolve the value the step magnitudes are calibrated at.
            %
            % currentValue is only a last-resort candidate, and is passed in
            % by callers holding it already rather than read again here.
            %
            % A reference the operator never chose has to be a FIXED value or
            % a proportional ladder is not proportional to anything: taking
            % the current value would make every step the same fraction of
            % wherever the track happens to be, which is just a linear
            % step with extra arithmetic. Min is the sensible anchor -- it is
            % the easy end the training starts from -- and the field is
            % seeded with the resolved number so it is never a mystery.
            arguments
                obj
                currentValue = []
            end

            r = obj.ScaleReference;
            if isfinite(r) && r ~= 0
                return
            end

            if isempty(currentValue)
                currentValue = obj.Parameter.Value;
            end
            candidates = [obj.MinValue, obj.MaxValue, 1];
            if gui.AdaptiveTraining.isSteppable(currentValue)
                candidates = [obj.MinValue, obj.MaxValue, currentValue, 1];
            end
            if obj.ScaleType == "logarithmic"
                candidates = candidates(candidates > 0);
            else
                candidates = candidates(candidates ~= 0);
            end
            candidates = candidates(isfinite(candidates));
            if isempty(candidates)
                r = 1;
            else
                r = candidates(1);
            end
        end

        function onScaleTypeChanged(obj)
            % Seed the reference so a warped space always shows what it is calibrated at.
            if obj.ScaleType ~= "linear" && ~isfinite(obj.ScaleReference)
                obj.ScaleReference = obj.referenceValue();
            end
            obj.refreshUI();
        end

        function s = percentStepText(obj)
            % The up step as a percentage, which is what a proportional ladder means.
            r = obj.referenceValue();
            if ~(r > 0) || ~isfinite(r)
                s = '?';
                return
            end
            s = sprintf('%+.3g%%', 100*(exp(obj.StepUp/r) - 1));
        end

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
                vprintf(0,1,'AdaptiveTraining:InvalidMinMax', ...
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
                vprintf(0,1,'AdaptiveTraining:InvalidLimits', ...
                    '%s must be a 1x2 numeric vector.', propName);
            end
            L = double(L(:)).';

            if L(1) > L(2)
                vprintf(0,1,'AdaptiveTraining:InvalidLimits', ...
                    '%s lower bound must be <= upper bound.', propName);
            end

            if options.isStep
                if L(1) < 0
                    vprintf(0,1,'AdaptiveTraining:InvalidLimits', ...
                        '%s lower bound must be >= 0.', propName);
                end
                if L(2) <= 0
                    vprintf(0,1,'AdaptiveTraining:InvalidLimits', ...
                        '%s upper bound must be > 0.', propName);
                end
            end

            obj.(propName) = L;
        end

        function valueFieldChanged(obj, field, src)
            % Commit an edit from one of the four value fields (reject on violation).
            obj.Committing = true;
            done = onCleanup(@() obj.endCommit());
            [ok,msg] = obj.applyValueEdit(field, src.Value);
            delete(done);
            src.Value = obj.(field); % revert on rejection; harmless when accepted
            if ok
                obj.setStatus("");
            else
                obj.setStatus(msg, isError=true);
            end
            obj.refreshUI();
        end

        function limitsTableEdited(obj, evt)
            % Commit an edit from the Advanced limits table (reject on violation).
            r = evt.Indices(1);
            c = evt.Indices(2);
            field = obj.rowFieldName(r);
            if field == "" || ~any(c == [2 3])
                return
            end

            obj.Committing = true;
            done = onCleanup(@() obj.endCommit());
            [ok,msg] = obj.applyLimitEdit(field, c - 1, evt.NewData);
            delete(done);

            if ok
                obj.setStatus("");
            else
                obj.setStatus(msg, isError=true);
            end
            obj.refreshUI();
        end

        function breakpointsEdited(obj, evt)
            % Commit an edit to the piecewise breakpoint table (reject on violation).
            B = obj.Breakpoints;
            r = evt.Indices(1);
            c = evt.Indices(2);
            v = evt.NewData;

            if ~(isnumeric(v) && isscalar(v) && ~isnan(v))
                obj.setStatus("Breakpoint entries must be numeric.", isError=true);
                obj.refreshUI();
                return
            end
            % A non-finite From value is refused here rather than accepted and
            % then dropped by sortBreakpoints, which would look like the edit
            % simply vanished.
            if c == 1 && ~isfinite(v)
                obj.setStatus("A breakpoint's From value must be finite.", isError=true);
                obj.refreshUI();
                return
            end
            if c > 1 && ~(isfinite(v) && v > 0)
                obj.setStatus("Breakpoint step sizes must be finite and > 0.", isError=true);
                obj.refreshUI();
                return
            end

            B(r,c) = double(v);
            obj.Breakpoints = B; % set method sorts by From value
            obj.setStatus("");
        end

        function addBreakpoint(obj)
            % Append a breakpoint seeded between the current bounds.
            B = obj.Breakpoints;
            if isempty(B)
                from = obj.seedBreakpointValue();
            else
                from = B(end,1) + max(obj.StepUp, eps);
            end
            obj.Breakpoints = [B; from obj.StepUp obj.StepDown];
            obj.setStatus("");
        end

        function removeBreakpoint(obj)
            % Remove the selected breakpoint row, or the last one when nothing is selected.
            B = obj.Breakpoints;
            if isempty(B)
                return
            end
            r = size(B,1);
            sel = obj.BreakpointTable.Selection;
            if ~isempty(sel)
                r = sel(1,1);
            end
            B(r,:) = [];
            obj.Breakpoints = B;
            obj.setStatus("");
        end

        function v = seedBreakpointValue(obj)
            % A first breakpoint that lands inside the working range.
            lo = obj.MinValue;
            hi = obj.MaxValue;
            if isfinite(lo) && isfinite(hi)
                v = lo + (hi - lo)/2;
            elseif isfinite(lo)
                v = lo + obj.StepUp;
            elseif isfinite(hi)
                v = hi - obj.StepDown;
            else
                % Unbounded both ways: anchor on the current value, or on
                % zero before there is one. Not on MinValue, which is -Inf
                % here and would make a row sortBreakpoints drops.
                v = 0;
                if obj.hasCurrentValue(), v = obj.Parameter.Value; end
            end
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
            % Apply an edit to a value field with validation.
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

        function data = limitsTableData(obj)
            % Build the Advanced limits table from committed properties.
            data = cell(4,3);
            data(1,:) = {'Step Up',   obj.StepUpLimits(1),   obj.StepUpLimits(2)};
            data(2,:) = {'Step Down', obj.StepDownLimits(1), obj.StepDownLimits(2)};
            data(3,:) = {'Minimum',   obj.MinValueLimits(1), obj.MinValueLimits(2)};
            data(4,:) = {'Maximum',   obj.MaxValueLimits(1), obj.MaxValueLimits(2)};
        end

        function field = rowFieldName(~, row)
            % Map limits-table row index to the corresponding property name.
            switch row
                case 1, field = "StepUp";
                case 2, field = "StepDown";
                case 3, field = "MinValue";
                case 4, field = "MaxValue";
                otherwise, field = "";
            end
        end

        function s = formatValue(obj, v)
            % Format a parameter-space value the way the parameter itself would.
            if ~isfinite(v)
                s = sprintf('%g', v);
                return
            end
            fmt = obj.Parameter.Format;
            if isempty(fmt), fmt = '%g'; end
            try
                s = sprintf(fmt, v);
            catch
                s = sprintf('%g', v);
            end
        end

        function s = unitSuffix(obj)
            % " ms" when the parameter names a unit, "" when it does not.
            u = strtrim(obj.Parameter.Unit);
            if isempty(u)
                s = '';
            else
                s = [' ' u];
            end
        end

        function refreshCurrentValue(obj)
            % Refresh only the header readout (cheap; called on every step).
            if ~isempty(obj.ParamValueLabel) && isvalid(obj.ParamValueLabel)
                obj.ParamValueLabel.Text = "Current: " + string(obj.Parameter.ValueStr);
            end
        end

        function applyAdvancedVisibility(obj)
            % Show or hide the Advanced section, collapsing its row when hidden.
            if ~obj.UIReady || isempty(obj.AdvancedPanel) || ~isvalid(obj.AdvancedPanel)
                return
            end
            obj.AdvancedPanel.Visible = matlab.lang.OnOffSwitchState(obj.ShowAdvanced);
            if obj.ShowAdvanced
                target = obj.ADVANCED_HEIGHT;
                obj.AdvancedButton.Text = '▾ Advanced';
            else
                target = 0;
                obj.AdvancedButton.Text = '▸ Advanced';
            end
            obj.RootGrid.RowHeight{4} = target;
            obj.AdvancedButton.Value = obj.ShowAdvanced;

            obj.resizeOwnedFigure(target - obj.AdvancedHeightApplied);
            obj.AdvancedHeightApplied = target;
        end

        function resizeOwnedFigure(obj, delta)
            % Give the disclosure its own space rather than taking the plot's.
            %
            % Only for a window this object owns: an embedded parent belongs to
            % the behavior GUI around it, and growing that would move somebody
            % else's layout. The window grows DOWNWARD (y falls as the height
            % rises) so the title bar the operator just clicked stays put.
            if delta == 0 || ~obj.OwnsParentFigure
                return
            end
            if isempty(obj.Parent) || ~isvalid(obj.Parent)
                return
            end
            pos = obj.Parent.Position;
            pos(2) = pos(2) - delta;
            pos(4) = pos(4) + delta;
            obj.Parent.Position = gui.fitPositionToMonitor(pos);
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
                obj.StatusLabel.FontColor = obj.COLOR_ERROR;
            else
                obj.StatusLabel.FontColor = obj.COLOR_MUTED;
            end
        end
    end
end
