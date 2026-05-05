classdef (Hidden) StimType < handle & matlab.mixin.Heterogeneous & matlab.mixin.Copyable & matlab.mixin.SetGet

    % obj = stimgen.StimType(Name,Value,...)
    % Abstract base class for stimulus generation objects.
    %
    % Package guide: documentation/stimgen/stimgen_overview.md
    % Class guide: documentation/stimgen/stimgen_StimType.md
    %
    % Subclasses implement update_signal() and define calibration and
    % normalization behavior. This base class provides shared properties for
    % level, duration, gating/windowing, sampling rate, plotting, and audio
    % playback.
    %
    % Properties (selected):
    %   SoundLevel, Duration, Fs, ApplyCalibration, ApplyWindow
    %
    % Methods:
    %   update_signal  - (Abstract) Update Signal based on current properties.
    %   plot, play     - Convenience visualization/playback helpers.

    properties
        Calibration     (1,1) stimgen.StimCalibration
        UserProperties  (1,:) string = string.empty
        DisplayName   (1,1) string = "undefined";
    end

    properties (SetObservable,AbortSet)
        SoundLevel     (1,:) double {mustBeFinite} = 60; % dB SPL if calibrated
        Duration       (1,:) double {mustBePositive,mustBeFinite} = 0.1;  % seconds

        WindowDuration (1,:) double {mustBeNonnegative,mustBeFinite} = 0.002; % seconds
        WindowFcn      (1,1) string = "cos2";

        ApplyCalibration (1,1) logical = true;
        ApplyWindow      (1,1) logical = true;

        Fs             (1,1) double {mustBePositive,mustBeFinite} = 97656.25; % Hz

        VariantSelectionMode (1,1) string {mustBeMember(VariantSelectionMode,["Serial","ShuffleUniform","ShuffleLeastUsed","CustomSelector"])} = "Serial"
        VariantCombinationMode (1,1) string {mustBeMember(VariantCombinationMode,["Cartesian","PairwiseStrict","PairwiseScalarExpand"])} = "Cartesian"
        VariantSelectorClass (1,1) string = ""
        VariantSelectorConfig (1,1) struct = struct()
        VariantReselectOnUpdate (1,1) logical = true
    end


    properties (SetAccess = protected, SetObservable)
        Signal       (1,:) = [];
    end

    properties (Dependent)
        N
        Time
        Window
        StrProps
    end


    properties (Hidden,Access = protected)
        temporarilyDisableSignalMods (1,1) logical = false;
        els
        GUIHandles
        calibrationWarningIssued (1,1) logical = false;
        plotLineHandle matlab.graphics.chart.primitive.Line = matlab.graphics.chart.primitive.Line.empty
        plotAxHandle   matlab.graphics.axis.Axes = matlab.graphics.axis.Axes.empty

        variantCombinationTable_ (1,:) struct = struct.empty(1,0)
        variantCombinationPropNames_ (1,:) string = string.empty(1,0)
        variantUseCount_ (1,:) double = zeros(1,0)
        variantCurrentIdx_ (1,1) double = 1
        variantActiveIdx_ (1,1) double = 1
        variantCycleActive_ (1,1) logical = false
        variantSignature_ (1,1) string = ""
        variantSelectorObj_
    end


    properties (Abstract, Constant)
        IsMultiObj      (1,1) logical
        CalibrationType (1,1) string % "noise","tone","click"
        Normalization   (1,1) string {mustBeMember(Normalization,["absmax","max","min","rms"])} 
    end

    methods (Abstract)
        update_signal(obj); % implemented in subclasses
    end

    methods

        function obj = StimType(varargin)
            % does no property name case matching
            for i = 1:2:length(varargin)
                if isfield(obj,varargin{i})
                    obj.(varargin{i}) = varargin{i+1};
                end
            end

            obj.create_listeners;
        end

        function S = toStruct(obj)
            %TOSTRUCT  Serialize StimType object to a struct.

            % Basic class metadata
            S = struct;
            S.Class        = string(class(obj));
            S.DisplayName  = obj.DisplayName;

            % Core StimType properties
            S.SoundLevel       = obj.SoundLevel;
            S.Duration         = obj.Duration;
            S.WindowDuration   = obj.WindowDuration;
            S.WindowFcn        = obj.WindowFcn;
            S.ApplyCalibration = obj.ApplyCalibration;
            S.ApplyWindow      = obj.ApplyWindow;
            S.Fs               = obj.Fs;
            S.VariantSelectionMode = obj.VariantSelectionMode;
            S.VariantCombinationMode = obj.VariantCombinationMode;
            S.VariantSelectorClass = obj.VariantSelectorClass;
            S.VariantSelectorConfig = obj.VariantSelectorConfig;
            S.VariantReselectOnUpdate = obj.VariantReselectOnUpdate;

            % Abstract/constant properties (same across instances of subclass)
            S.CalibrationType  = obj.CalibrationType;
            S.Normalization    = obj.Normalization;
            S.IsMultiObj       = obj.IsMultiObj;

            % Calibration
            S.Calibration = obj.Calibration.toStruct;


            % User-defined property list and values
            S.UserProperties = obj.UserProperties;
            for k = 1:numel(obj.UserProperties)
                pname = obj.UserProperties(k);
                if isprop(obj,pname)
                    S.(pname) = obj.(pname);
                end
            end

            % Do NOT store Signal, GUIHandles, listeners, etc. here
        end

        function set.Calibration(obj,calObj)
            obj.Calibration = calObj;
            if obj.IsMultiObj
                arrayfun(@(x) set(x,'Calibration',calObj), obj.MultiObjects);
            end
        end

        function s = get.StrProps(obj)
            pr = obj.UserProperties;
            s = string();
            for i = 1:length(pr)
                s = s+pr(i)+": "+string(obj.(pr(i))) + "; ";
            end
        end

        function t = get.Time(obj)
            durationValue = double(obj.get_selected_property_value_("Duration"));
            fsValue = double(obj.get_selected_property_value_("Fs"));
            nSamples = max(1, round(fsValue * durationValue));
            t = linspace(0, durationValue - 1./fsValue, nSamples);
        end

        function n = get.N(obj)
            durationValue = double(obj.get_selected_property_value_("Duration"));
            fsValue = double(obj.get_selected_property_value_("Fs"));
            n = round(fsValue * durationValue);
        end


        function g = get.Window(obj)
            windowDurationValue = double(obj.get_selected_property_value_("WindowDuration"));
            fsValue = double(obj.get_selected_property_value_("Fs"));
            n = round(windowDurationValue .* fsValue);
            n = n + rem(n,2);

            windowFcnValue = string(obj.get_selected_property_value_("WindowFcn"));
            switch windowFcnValue
                case ""
                    g = ones(1,n);
                case "cos2"
                    g = hann(n);
                otherwise
                    g = feval(char(windowFcnValue),n);
            end
            g = g(:)'; % conform to row vector
        end

        function h = plot(obj,ax)
            % PLOT  Plot current Signal vs Time.
            %   If a valid plot already exists, its data are updated instead
            %   of creating a new line.
            if nargin < 2 || isempty(ax)
                if ~isempty(obj.plotAxHandle) && isvalid(obj.plotAxHandle)
                    ax = obj.plotAxHandle;
                else
                    ax = gca;
                end
            end

            if isempty(obj.Signal)
                obj.call_update_signal_with_variant_cycle_(); % subclass implementation
            end

            if ~isempty(obj.plotLineHandle) && isvalid(obj.plotLineHandle) && ...
                    isvalid(obj.plotAxHandle) && obj.plotAxHandle == ax
                set(obj.plotLineHandle,'XData',obj.Time,'YData',obj.Signal);
                h = obj.plotLineHandle;
            else
                h = plot(ax,obj.Time,obj.Signal);
                obj.plotLineHandle = h;
                obj.plotAxHandle   = ax;
            end
            grid(ax,'on');
            xlabel(ax,'time (s)');
        end

        function play(obj)
            fsValue = double(obj.get_selected_property_value_("Fs"));
            ap = audioplayer(obj.Signal./max(abs(obj.Signal)), fsValue);
            playblocking(ap);
            delete(ap);
        end

        function v = selected_value(obj, propName)
            % selected_value(obj, propName)
            % Return the scalar value chosen for a potentially-vectorized property.
            arguments
                obj (1,1) stimgen.StimType
                propName (1,1) string
            end
            v = obj.get_selected_property_value_(propName);
        end

        function value = evalPropertyExpression(obj, propName, expressionText)
            % value = evalPropertyExpression(obj, propName, expressionText)
            % Evaluate a guarded MATLAB expression for a vectorizable numeric property.
            % Accepts range syntax (0:10:50), vector literals ([1 2 3]), general
            % MATLAB expressions, and cross-property references using bare property
            % names or qualified ClassName.PropertyName notation.
            %
            % Parameters:
            %   propName       - Name of the target property.
            %   expressionText - MATLAB expression string to evaluate.
            %
            % Returns:
            %   value - Resulting double scalar or vector.
            value = obj.evaluate_property_expression_(propName, char(string(expressionText)));
        end

        function info = get_variant_info(obj)
            % info = get_variant_info(obj)
            % Return current variant-combination state for this stimulus.
            %
            % Returns:
            %   info.NumCombinations - Number of variant combinations.
            %   info.ActiveIndex     - Active 1-based combination index.
            %   info.PropertyNames   - Vectorized property names.

            obj.refresh_variant_cache_if_needed_();

            nComb = numel(obj.variantCombinationTable_);
            if nComb < 1
                nComb = 1;
            end

            activeIdx = min(max(obj.variantActiveIdx_, 1), nComb);
            info = struct(...
                'NumCombinations', nComb, ...
                'ActiveIndex', activeIdx, ...
                'PropertyNames', obj.variantCombinationPropNames_);
        end

        function info = set_variant_index(obj, idx)
            % info = set_variant_index(obj, idx)
            % Select a specific variant combination and regenerate Signal.
            %
            % Parameters:
            %   idx - 1-based variant index (wraps cyclically).
            %
            % Returns:
            %   info - Variant state struct.
            arguments
                obj (1,1) stimgen.StimType
                idx (1,1) double {mustBeFinite,mustBePositive}
            end

            info = obj.apply_variant_index_and_update_(round(double(idx)));
        end

        function info = step_variant(obj, step)
            % info = step_variant(obj)
            % info = step_variant(obj, step)
            % Step variant combination index and regenerate Signal.
            %
            % Parameters:
            %   step - Signed integer step (default +1).
            %
            % Returns:
            %   info - Variant state struct.
            arguments
                obj (1,1) stimgen.StimType
                step (1,1) double {mustBeFinite,mustBeInteger} = 1
            end

            state = obj.get_variant_info();
            info = obj.apply_variant_index_and_update_(state.ActiveIndex + step);
        end

        function text = current_parameter_summary(obj)
            % text = current_parameter_summary(obj)
            % Return a compact summary of currently active stimulus parameters
            % that differ from their class defaults. Only non-default values
            % are included.

            meta = obj.get_prop_meta();
            propNames = string(obj.UserProperties);
            propNames = propNames(~ismember(propNames, [ ...
                "VariantSelectionMode", ...
                "VariantCombinationMode", ...
                "VariantSelectorClass", ...
                "VariantSelectorConfig", ...
                "VariantReselectOnUpdate" ...
            ]));

            % Build a map of property default values from metaclass
            mc = metaclass(obj);
            mcPropList = mc.PropertyList;
            mcNames = string({mcPropList.Name});

            parts = strings(1, 0);
            for k = 1:numel(propNames)
                propName = propNames(k);
                if ~isprop(obj, char(propName))
                    continue
                end

                try
                    value = obj.selected_value(propName);
                catch
                    value = obj.(char(propName));
                end

                % Skip if value matches the class default
                mcIdx = find(mcNames == propName, 1);
                if ~isempty(mcIdx) && mcPropList(mcIdx).HasDefault
                    defVal = mcPropList(mcIdx).DefaultValue;
                    if isequal(value, defVal)
                        continue
                    end
                end

                if isfield(meta, char(propName)) && isfield(meta.(char(propName)), 'label')
                    label = string(meta.(char(propName)).label);
                else
                    label = propName;
                end

                parts(end+1) = label + "=" + format_summary_value_(value); %#ok<AGROW>
            end

            text = strjoin(parts, ", ");
        end

        function h = create_gui(obj, src, ~)
            % create_gui(obj, src) - Auto-build parameter GUI from propMeta().
            % Creates a two-column label+widget grid for each property returned
            % by propMeta(). Widget type is inferred from the property class
            % (double->numeric editfield, logical->checkbox, string->text
            % editfield) unless overridden via the 'widget' metadata field.
            %
            % Parameters:
            %   src - parent UI container (e.g. uipanel)
            % Returns:
            %   h   - struct of widget handles keyed by property name

            meta   = obj.propMeta();
            fields = fieldnames(meta);
            nRows  = numel(fields);

            mc = metaclass(obj);
            pl = mc.PropertyList;

            g = uigridlayout(src);
            g.ColumnWidth = {'1x', '1x'};
            g.RowHeight   = repmat({25}, 1, nRows);

            h = struct();
            for i = 1:nRows
                propName = fields{i};
                pm = meta.(propName);

                lbl = uilabel(g, 'Text', pm.label);
                lbl.Layout.Column = 1;
                lbl.Layout.Row    = i;
                lbl.HorizontalAlignment = 'right';

                wt = stimgen.StimType.resolve_widget_type(propName, pm, pl);

                switch wt
                    case 'numeric'
                        if obj.is_non_vectorizable_property_(propName)
                            x = uieditfield(g, 'numeric', 'Tag', propName);
                            x.Value = obj.(propName);
                            if isfield(pm, 'format')
                                x.ValueDisplayFormat = pm.format;
                            end
                            if isfield(pm, 'limits')
                                x.Limits = pm.limits;
                            end
                        else
                            x = uieditfield(g, 'Tag', propName);
                            x.Value = localFormatPropertyValue_(obj.(propName));
                            x.UserData = struct('isNumericExpression', true, 'propMeta', pm);
                        end
                    case 'checkbox'
                        x = uicheckbox(g, 'Tag', propName, 'Text', '');
                        x.Value = obj.(propName);
                    case 'dropdown'
                        x = uidropdown(g, 'Tag', propName);
                        x.Items = pm.items;
                        if isfield(pm, 'itemsData')
                            x.ItemsData = pm.itemsData;
                        end
                        x.Value = obj.(propName);
                    otherwise % 'text'
                        x = uieditfield(g, 'Tag', propName);
                        x.Value = char(obj.(propName));
                end

                x.Layout.Column = 2;
                x.Layout.Row    = i;
                h.(propName)    = x;
            end

            structfun(@(a) set(a, 'ValueChangedFcn', @obj.interpret_gui), h);
            obj.GUIHandles = h;
        end

        function m = get_prop_meta(obj)
            % get_prop_meta(obj) - Public accessor for propMeta().
            % Returns the display metadata struct for this stimulus type.
            m = obj.propMeta();
        end
    end % methods (Access = public)

    methods (Access = protected)

        function apply_normalization(obj)
            % Apply normalization to obj.Signal according to the Normalization constant.
            if obj.temporarilyDisableSignalMods || isempty(obj.Signal), return; end
            switch obj.Normalization
                case "absmax"
                    obj.Signal = obj.Signal ./ max(abs(obj.Signal));
                case "max"
                    obj.Signal = obj.Signal ./ max(obj.Signal);
                case "min"
                    obj.Signal = obj.Signal ./ min(obj.Signal);
                case "rms"
                    obj.Signal = obj.Signal ./ sqrt(mean(obj.Signal.^2));
            end
        end

        function apply_gate(obj)
            applyWindowValue = logical(obj.get_selected_property_value_("ApplyWindow"));
            if ~applyWindowValue || obj.temporarilyDisableSignalMods, return; end

            g = obj.Window;

            n = length(g);
            ga = g(1:n/2);
            gb = g(n/2+1:end);

            obj.Signal(1:n/2) = obj.Signal(1:n/2) .* ga;
            obj.Signal(end-n/2+1:end) = obj.Signal(end-n/2+1:end) .* gb;
        end


        function apply_calibration(obj)
            %APPLY_CALIBRATION  Apply either scalar (LUT) calibration or filter+gain calibration.

            if ~obj.ApplyCalibration || obj.temporarilyDisableSignalMods
                return
            end

            C = obj.Calibration;

            if ~isa(C,'stimgen.StimCalibration') || isempty(C.CalibrationData)
                if obj.calibrationWarningIssued
                    vprintf(2,1,'No calibration data available for stim');
                else
                    vprintf(0,1,'No calibration data available for stim');
                    obj.calibrationWarningIssued = true;
                end
                return
            end

            type  = obj.CalibrationType;
            level = double(obj.get_selected_property_value_("SoundLevel"));

            % Resolve LUT "value" where relevant
            switch type
                case "tone"
                    value = double(obj.get_selected_property_value_("Frequency"));
                case "click"
                    value = double(obj.get_selected_property_value_("ClickDuration"));
                otherwise
                    value = NaN;
            end

            % Start with the generated signal; may be replaced by filtered version.
            y = obj.Signal;

            % --- Filter-based calibration: equalize spectrum + apply level gain ---
            if type == "filter" && isfield(C.CalibrationData,'filter')

                Hd = C.CalibrationData.filter;

                % Robust group-delay compensation (pre/post pad avoids start-up transient)
                gd = round(C.CalibrationData.filterGrpDelay);
                
                if gd > 0
                    xpad = [zeros(1,gd) obj.Signal zeros(1,gd)];
                    ypad = filter(Hd,xpad);
                    y = ypad(gd+1:gd+numel(obj.Signal));
                else
                    y = filter(Hd,obj.Signal);
                end
            end

            switch obj.Normalization
                case "absmax"
                    y = y ./ max(abs(y));
                case "max"
                    y = y ./ max(y);
                case "min"
                    y = y ./ min(y);
                case "rms"
                    y = y ./ sqrt(mean(y.^2));
            end


            % Apply level (scalar) calibration for the filtered waveform
            v = C.compute_adjusted_voltage(type,value,level);



            if v > 10
                warning('stimgen:StimType:apply_calibration:OutOfRange', ...
                    'Calculated voltage value > 10 V')
            end

            obj.Signal = v .* y;

        end


        function create_listeners(obj)
            m = metaclass(obj);
            p = m.PropertyList;
            ind = [p.SetObservable] & string({p.SetAccess}) == "public";
            p(~ind) = [];

            for i = 1:length(p)
                e(i) = addlistener(obj,p(i).Name,'PostSet',@obj.onPropertyChanged);
            end
            obj.els = e;
        end

        function onPropertyChanged(obj,src,~)
            % Listener callback: update signal and refresh plot if it exists.
            if ~isempty(src) && obj.is_variant_policy_property_(string(src.Name))
                % Policy edits should not force immediate signal recompute while
                % users are still configuring vectorized properties.
                obj.variantSignature_ = "";
                obj.variantSelectorObj_ = [];
                return
            end
            obj.call_update_signal_with_variant_cycle_(); % subclass implementation handles args
            obj.refresh_plot_if_valid;
        end

        function refresh_plot_if_valid(obj)
            if ~isempty(obj.plotLineHandle) && isvalid(obj.plotLineHandle)
                if isempty(obj.Signal)
                    return
                end
                set(obj.plotLineHandle,'XData',obj.Time,'YData',obj.Signal);
                if ~isempty(obj.plotAxHandle) && isvalid(obj.plotAxHandle)
                    grid(obj.plotAxHandle,'on');
                    xlabel(obj.plotAxHandle,'time (s)');
                end
            end
        end

        function update_handle_value(obj,src,event)
            h = obj.GUIHandles;

            h.(src.Name).Value = obj.(src.Name);
        end

        function interpret_gui(obj, src, event)
            isNumExpr = isstruct(src.UserData) && isfield(src.UserData, 'isNumericExpression') && src.UserData.isNumericExpression;
            try
                if isNumExpr
                    value = obj.evaluate_property_expression_(src.Tag, char(string(event.Value)));
                else
                    value = event.Value;
                end
                obj.(src.Tag) = value;
            catch ME
                if isNumExpr
                    src.Value = localFormatPropertyValue_(obj.(src.Tag));
                else
                    obj.(src.Tag) = event.PreviousValue;
                end
                fig = ancestor(src, 'matlab.ui.Figure');
                if ~isempty(fig) && isvalid(fig)
                    uialert(fig, ME.message, sprintf('Invalid value for %s', src.Tag));
                end
                return
            end
            if isNumExpr
                src.Value = localFormatPropertyValue_(obj.(src.Tag));
            end
            obj.on_gui_changed(src.Tag, event.Value);
            obj.call_update_signal_with_variant_cycle_();
        end

        function call_update_signal_with_variant_cycle_(obj)
            % Ensure one deterministic variant selection per signal update call.
            cycleWasActive = obj.variantCycleActive_;
            if ~cycleWasActive
                obj.begin_variant_cycle_();
            end
            try
                obj.update_signal;
            catch ME
                if ~cycleWasActive
                    obj.end_variant_cycle_();
                end
                rethrow(ME)
            end
            if ~cycleWasActive
                obj.end_variant_cycle_();
            end
        end

        function begin_variant_cycle_(obj)
            obj.refresh_variant_cache_if_needed_();
            obj.variantCycleActive_ = true;
            if isempty(obj.variantCombinationTable_)
                obj.variantActiveIdx_ = 1;
                return
            end
            obj.variantActiveIdx_ = obj.select_variant_index_();
            if numel(obj.variantUseCount_) >= obj.variantActiveIdx_
                obj.variantUseCount_(obj.variantActiveIdx_) = obj.variantUseCount_(obj.variantActiveIdx_) + 1;
            end
        end

        function end_variant_cycle_(obj)
            obj.variantCycleActive_ = false;
        end

        function value = get_selected_property_value_(obj, propName)
            % Return scalar value for propName using the active variant combination.
            if ~isprop(obj, char(propName))
                error('stimgen:StimType:UnknownProperty', 'Unknown property "%s".', char(propName));
            end

            raw = obj.(char(propName));
            if obj.is_non_vectorizable_property_(propName) && numel(raw) > 1
                error('stimgen:StimType:NonVectorizableProperty', ...
                    'Property "%s" is not vectorizable and must be scalar.', char(propName));
            end

            if numel(raw) <= 1
                value = raw;
                return
            end

            obj.refresh_variant_cache_if_needed_();
            if isempty(obj.variantCombinationTable_)
                value = raw(1);
                return
            end

            idx = obj.variantActiveIdx_;
            if ~obj.variantCycleActive_
                if obj.VariantReselectOnUpdate
                    idx = obj.select_variant_index_();
                    obj.variantActiveIdx_ = idx;
                    if numel(obj.variantUseCount_) >= idx
                        obj.variantUseCount_(idx) = obj.variantUseCount_(idx) + 1;
                    end
                else
                    if isempty(obj.variantCombinationTable_)
                        idx = 1;
                    else
                        idx = min(max(obj.variantActiveIdx_, 1), numel(obj.variantCombinationTable_));
                    end
                end
            end

            key = char(propName);
            combo = obj.variantCombinationTable_(idx);
            if isfield(combo, key)
                value = combo.(key);
            else
                value = raw(1);
            end
        end

        function refresh_variant_cache_if_needed_(obj)
            [propNames, propValues] = obj.get_variant_source_values_();
            signature = obj.build_variant_signature_(propNames, propValues);
            if signature == obj.variantSignature_
                return
            end

            [comboTable, comboProps] = obj.build_variant_combinations_(propNames, propValues);
            obj.variantCombinationTable_ = comboTable;
            obj.variantCombinationPropNames_ = comboProps;
            obj.variantUseCount_ = zeros(1, numel(comboTable));
            obj.variantCurrentIdx_ = 1;
            obj.variantActiveIdx_ = 1;
            obj.variantSignature_ = signature;
            obj.variantSelectorObj_ = [];
        end

        function [propNames, propValues] = get_variant_source_values_(obj)
            propNames = string.empty(1,0);
            propValues = {};
            if isempty(obj.UserProperties)
                return
            end

            for k = 1:numel(obj.UserProperties)
                pname = string(obj.UserProperties(k));
                if ~isprop(obj, char(pname))
                    continue
                end
                raw = obj.(char(pname));
                if obj.is_non_vectorizable_property_(pname)
                    if numel(raw) > 1
                        error('stimgen:StimType:NonVectorizableProperty', ...
                            'Property "%s" is not vectorizable and must be scalar.', char(pname));
                    end
                    continue
                end
                if numel(raw) > 1
                    propNames(end+1) = pname; %#ok<AGROW>
                    if isrow(raw)
                        propValues{end+1} = raw; %#ok<AGROW>
                    else
                        propValues{end+1} = reshape(raw, 1, []); %#ok<AGROW>
                    end
                end
            end
        end

        function signature = build_variant_signature_(obj, propNames, propValues)
            parts = strings(1, numel(propNames) + 3);
            parts(1) = obj.VariantSelectionMode;
            parts(2) = obj.VariantCombinationMode;
            parts(3) = obj.VariantSelectorClass;
            for k = 1:numel(propNames)
                v = propValues{k};
                if isnumeric(v) || islogical(v)
                    vtxt = mat2str(v);
                elseif isstring(v)
                    vtxt = strjoin(v, '|');
                elseif ischar(v)
                    vtxt = string(v);
                else
                    vtxt = string(class(v)) + ":" + string(numel(v));
                end
                parts(k+3) = propNames(k) + "=" + vtxt;
            end
            signature = strjoin(parts, "||");
        end

        function [comboTable, comboProps] = build_variant_combinations_(obj, propNames, propValues)
            comboProps = propNames;
            if isempty(propNames)
                comboTable = struct.empty(1,0);
                return
            end

            nProps = numel(propNames);
            mode = obj.VariantCombinationMode;
            switch mode
                case "Cartesian"
                    grids = cell(1, nProps);
                    [grids{:}] = ndgrid(propValues{:});
                    nComb = numel(grids{1});
                    fieldNames = cellstr(propNames);
                    fieldValues = repmat({[]}, 1, nProps);
                    seed = cell2struct(fieldValues, fieldNames, 2);
                    comboTable = repmat(seed, 1, nComb);
                    for i = 1:nComb
                        for p = 1:nProps
                            comboTable(i).(fieldNames{p}) = grids{p}(i);
                        end
                    end
                otherwise
                    lengths = cellfun(@numel, propValues);
                    maxLen = max(lengths);
                    switch mode
                        case "PairwiseStrict"
                            if any(lengths ~= maxLen)
                                error('stimgen:StimType:PairwiseLengthMismatch', ...
                                    'PairwiseStrict requires equal vector lengths for all vectorized properties.');
                            end
                            expanded = propValues;
                        case "PairwiseScalarExpand"
                            valid = (lengths == 1) | (lengths == maxLen);
                            if ~all(valid)
                                error('stimgen:StimType:PairwiseLengthMismatch', ...
                                    'PairwiseScalarExpand requires each vector length to be either 1 or the shared max length.');
                            end
                            expanded = propValues;
                            for p = 1:nProps
                                if numel(expanded{p}) == 1
                                    expanded{p} = repmat(expanded{p}, 1, maxLen);
                                end
                            end
                        otherwise
                            error('stimgen:StimType:InvalidCombinationMode', ...
                                'Unknown VariantCombinationMode "%s".', char(mode));
                    end

                    fieldNames = cellstr(propNames);
                    fieldValues = repmat({[]}, 1, nProps);
                    seed = cell2struct(fieldValues, fieldNames, 2);
                    comboTable = repmat(seed, 1, maxLen);
                    for i = 1:maxLen
                        for p = 1:nProps
                            comboTable(i).(fieldNames{p}) = expanded{p}(i);
                        end
                    end
            end
        end

        function idx = select_variant_index_(obj)
            nComb = numel(obj.variantCombinationTable_);
            if nComb <= 1
                idx = 1;
                return
            end

            switch obj.VariantSelectionMode
                case "Serial"
                    idx = obj.variantCurrentIdx_;
                    idx = min(max(idx,1), nComb);
                    obj.variantCurrentIdx_ = mod(idx, nComb) + 1;
                case "ShuffleUniform"
                    idx = randi(nComb);
                    obj.variantCurrentIdx_ = idx;
                case "ShuffleLeastUsed"
                    counts = obj.variantUseCount_;
                    if isempty(counts) || numel(counts) ~= nComb
                        counts = zeros(1, nComb);
                        obj.variantUseCount_ = counts;
                    end
                    minCount = min(counts);
                    candidates = find(counts == minCount);
                    idx = candidates(randi(numel(candidates)));
                    obj.variantCurrentIdx_ = idx;
                case "CustomSelector"
                    selector = obj.get_or_create_variant_selector_();
                    trialRows = num2cell((1:nComb).');
                    trialsStruct = struct('trials', {trialRows});
                    idx = selector.selectNext(trialsStruct);
                    if ~isscalar(idx) || ~isfinite(idx) || idx < 1 || idx > nComb
                        error('stimgen:StimType:InvalidSelectorIndex', ...
                            'Custom selector returned invalid index for %d variants.', nComb);
                    end
                    idx = double(idx);
                    obj.variantCurrentIdx_ = idx;
                otherwise
                    error('stimgen:StimType:InvalidSelectionMode', ...
                        'Unknown VariantSelectionMode "%s".', char(obj.VariantSelectionMode));
            end
        end

        function selector = get_or_create_variant_selector_(obj)
            if ~isempty(obj.variantSelectorObj_) && isa(obj.variantSelectorObj_, 'handle') && isvalid(obj.variantSelectorObj_)
                selector = obj.variantSelectorObj_;
                return
            end

            className = strtrim(char(obj.VariantSelectorClass));
            if isempty(className)
                error('stimgen:StimType:MissingSelectorClass', ...
                    'VariantSelectorClass must be provided when VariantSelectionMode is CustomSelector.');
            end
            if exist(className, 'class') ~= 8
                error('stimgen:StimType:SelectorClassNotFound', ...
                    'Variant selector class "%s" was not found.', className);
            end

            selector = feval(className);
            if ~isa(selector, 'epsych.TrialSelector')
                error('stimgen:StimType:SelectorClassType', ...
                    'Variant selector class "%s" must inherit epsych.TrialSelector.', className);
            end

            if ~isempty(fieldnames(obj.VariantSelectorConfig))
                cfgNames = fieldnames(obj.VariantSelectorConfig);
                for k = 1:numel(cfgNames)
                    cfgName = cfgNames{k};
                    if isprop(selector, cfgName)
                        selector.(cfgName) = obj.VariantSelectorConfig.(cfgName);
                    end
                end
            end

            trialsStruct = struct('trials', {num2cell((1:max(1,numel(obj.variantCombinationTable_))).')});
            selector.initialize(trialsStruct);
            obj.variantSelectorObj_ = selector;
        end

        function tf = is_non_vectorizable_property_(~, propName)
            tf = any(strcmp(string(propName), ["Fs","ApplyCalibration","ApplyWindow"]));
        end

        function info = apply_variant_index_and_update_(obj, idx)
            % apply_variant_index_and_update_(obj, idx)
            % Internal helper to lock one variant index for a full update.

            obj.refresh_variant_cache_if_needed_();

            nComb = numel(obj.variantCombinationTable_);
            if nComb < 1
                nComb = 1;
            end

            targetIdx = mod(round(double(idx)) - 1, nComb) + 1;

            cycleWasActive = obj.variantCycleActive_;
            prevActiveIdx = obj.variantActiveIdx_;

            obj.variantCycleActive_ = true;
            obj.variantActiveIdx_ = targetIdx;
            if numel(obj.variantUseCount_) >= targetIdx
                obj.variantUseCount_(targetIdx) = obj.variantUseCount_(targetIdx) + 1;
            end

            try
                obj.update_signal;
            catch ME
                obj.variantActiveIdx_ = prevActiveIdx;
                obj.variantCycleActive_ = cycleWasActive;
                rethrow(ME)
            end

            obj.variantCycleActive_ = cycleWasActive;
            obj.variantCurrentIdx_ = mod(targetIdx, nComb) + 1;

            info = obj.get_variant_info();
        end

        function value = evaluate_property_expression_(obj, propName, expressionText)
            % value = evaluate_property_expression_(obj, propName, expressionText)
            % Evaluate a guarded MATLAB expression for a numeric property.
            % Supports vector/range literals, MATLAB expressions, and references
            % to other properties by bare name or ClassName.PropertyName form.
            %
            % Parameters:
            %   propName       - Name of the target property being set.
            %   expressionText - MATLAB expression string entered by the user.
            %
            % Returns:
            %   value - Evaluated double vector or scalar.
            expressionText = strtrim(expressionText);
            if isempty(expressionText)
                error('Expression cannot be empty.');
            end
            if ~isempty(regexp(expressionText, '(?<![<>=~])=(?!=)', 'once'))
                error('Assignments are not allowed in expressions.');
            end
            if contains(expressionText, ';')
                error('Only a single expression is allowed.');
            end
            expressionText = obj.rewrite_qualified_property_refs_(expressionText);
            expressionText = strip(expressionText, 'both', '"');
            expressionText = strip(expressionText, 'both', '''');
            context = obj.build_expression_context_(propName);
            names = fieldnames(context);
            for k_ = 1:numel(names)
                eval(sprintf('%s = context.(names{%d});', names{k_}, k_));
            end
            value = eval(expressionText);
            if ischar(value) || (isstring(value) && isscalar(value))
                nestedExpression = strtrim(char(string(value)));
                if strcmp(nestedExpression, expressionText)
                    error('Expression for %s must evaluate to a numeric or logical value.', propName);
                end
                value = eval(nestedExpression);
            end
            if ~(isnumeric(value) || islogical(value)) || isempty(value)
                error('Expression for %s must evaluate to a numeric or logical value.', propName);
            end
            if ~all(isfinite(value(:)))
                error('Expression for %s must evaluate to finite numeric values.', propName);
            end
            value = double(value);
        end

        function context = build_expression_context_(obj, targetPropName)
            % context = build_expression_context_(obj, targetPropName)
            % Build a struct of current numeric property values as eval context.
            % Excludes the target property to prevent self-reference.
            context = struct();
            if isempty(obj.UserProperties)
                return
            end
            for k_ = 1:numel(obj.UserProperties)
                pname = char(obj.UserProperties(k_));
                if strcmp(pname, targetPropName)
                    continue
                end
                if ~isprop(obj, pname)
                    continue
                end
                raw = obj.(pname);
                if isnumeric(raw) || islogical(raw)
                    safeName = matlab.lang.makeValidName(pname);
                    context.(safeName) = double(raw);
                end
            end
        end

        function expressionText = rewrite_qualified_property_refs_(obj, expressionText)
            % expressionText = rewrite_qualified_property_refs_(obj, expressionText)
            % Replace ClassName.PropertyName tokens with bare PropertyName
            % when PropertyName is a recognized property of this StimType.
            mc = metaclass(obj);
            validNames = {mc.PropertyList.Name};
            [tokens, starts, ends_] = regexp(expressionText, ...
                '(?<!\.)\<([A-Za-z]\w*)\.([A-Za-z]\w*)\>', ...
                'tokens', 'start', 'end');
            for k_ = numel(starts):-1:1
                propName = tokens{k_}{2};
                if ismember(propName, validNames)
                    expressionText = [expressionText(1:starts(k_)-1), propName, expressionText(ends_(k_)+1:end)];
                end
            end
        end

        function tf = is_variant_policy_property_(~, propName)
            tf = any(strcmp(string(propName), [ ...
                "VariantSelectionMode", ...
                "VariantCombinationMode", ...
                "VariantSelectorClass", ...
                "VariantSelectorConfig", ...
                "VariantReselectOnUpdate" ...
            ]));
        end

        function on_gui_changed(~, ~, ~)
            % Override in subclasses to respond to a specific property change
            % triggered from the GUI, e.g. to update a sibling widget's format.
        end

        function m = propMeta(~)
            % propMeta() - Return display metadata for GUI-visible base properties.
            % Subclasses override this and chain via propMeta@stimgen.StimType(obj),
            % merging results with stimgen.StimType.merge_prop_meta(subMeta, baseMeta).
            %
            % Each field name matches a property name. Each value is a struct with:
            %   label     (required) - display label string
            %   format    (optional) - printf format string for numeric fields
            %   limits    (optional) - [min max] for numeric editfield
            %   widget    (optional) - 'numeric'|'text'|'checkbox'|'dropdown'
            %   items     (optional) - string/cell array of dropdown items
            %   itemsData (optional) - cell array of underlying dropdown values
            m = struct();
            m.SoundLevel     = struct('label', 'Sound Level',     'format', '%.1f dB SPL');
            m.Duration       = struct('label', 'Duration',        'format', '%.3f s',  'limits', [0.001 10]);
            m.WindowDuration = struct('label', 'Window Duration', 'format', '%.4f s',  'limits', [1e-6 10]);
            m.ApplyWindow    = struct('label', 'Apply Window');
            m.VariantSelectionMode = struct('label', 'Variant Selection', 'widget', 'dropdown', ...
                'items', ["Serial" "ShuffleUniform" "ShuffleLeastUsed" "CustomSelector"]);
            m.VariantCombinationMode = struct('label', 'Variant Combination', 'widget', 'dropdown', ...
                'items', ["Cartesian" "PairwiseStrict" "PairwiseScalarExpand"]);
            m.VariantSelectorClass = struct('label', 'Variant Selector Class');
            m.VariantReselectOnUpdate = struct('label', 'Reselect Variant Each Update');
        end
    end % methods (Access = protected)

    methods (Static, Access = protected)
        function m = merge_prop_meta(a, b)
            % merge_prop_meta(a, b) - Append fields of struct b into struct a.
            % Used by subclass propMeta() to append base-class metadata.
            bf = fieldnames(b);
            for i = 1:numel(bf)
                a.(bf{i}) = b.(bf{i});
            end
            m = a;
        end

        function wt = resolve_widget_type(propName, pm, pl)
            % resolve_widget_type - Determine widget type for a property.
            % Uses explicit 'widget' field in pm if present; otherwise infers
            % from property class: double->numeric, logical->checkbox, else text.
            if isfield(pm, 'widget')
                wt = pm.widget;
                return
            end
            idx = strcmp({pl.Name}, propName);
            if ~any(idx) || isempty(pl(idx).Validation) || isempty(pl(idx).Validation.Class)
                wt = 'text';
                return
            end
            switch pl(idx).Validation.Class.Name
                case 'double'
                    wt = 'numeric';
                case 'logical'
                    wt = 'checkbox';
                otherwise
                    wt = 'text';
            end
        end
    end % methods (Static, Access = protected)

    methods (Static)
        function obj = fromStruct(S)
            % obj = stimgen.StimType.fromStruct(S)
            % Reconstruct a stimgen.StimType subclass instance from a serialized struct.
            % The struct must have been produced by stimgen.StimType.toStruct().
            % Signal is not restored; call obj.update_signal() if needed.
            %
            % Parameters
            %   S - Struct with at least a Class field and UserProperties list.
            %
            % Returns
            %   obj - Reconstructed stimgen.StimType subclass instance.
            obj = feval(char(S.Class));
            obj.DisplayName = S.DisplayName;
            obj.Fs               = S.Fs;
            obj.ApplyCalibration = S.ApplyCalibration;
            obj.ApplyWindow      = S.ApplyWindow;
            if isfield(S, 'VariantSelectionMode')
                obj.VariantSelectionMode = string(S.VariantSelectionMode);
            end
            if isfield(S, 'VariantCombinationMode')
                obj.VariantCombinationMode = string(S.VariantCombinationMode);
            end
            if isfield(S, 'VariantSelectorClass')
                obj.VariantSelectorClass = string(S.VariantSelectorClass);
            end
            if isfield(S, 'VariantSelectorConfig')
                obj.VariantSelectorConfig = S.VariantSelectorConfig;
            end
            if isfield(S, 'VariantReselectOnUpdate')
                obj.VariantReselectOnUpdate = logical(S.VariantReselectOnUpdate);
            end
            for k = 1:numel(S.UserProperties)
                pname = char(S.UserProperties(k));
                if isprop(obj, pname) && isfield(S, pname)
                    obj.(pname) = S.(pname);
                end
            end
        end

        function c = list
            r = which('stimgen.StimType');
            pth = fileparts(r);
            d = dir(fullfile(pth,'*.m'));
            f = {d.name};
            f(ismember(f,{'StimType.m','StimPlay.m','donotsavedatafcn.m','multiTone.m'})) = [];
            f(contains(f,'Calib')) = [];
            c = cellfun(@(a) a(1:end-2),f,'uni',0);
        end
    end % methods (Static)
end

function text = localFormatPropertyValue_(value)
% Format a numeric property value as a display string for a text edit field.
% Scalars render as a bare number; vectors render in mat2str bracket notation.
if isscalar(value)
    text = num2str(double(value), '%g');
else
    text = mat2str(double(value));
end
end

function text = format_summary_value_(value)
% Format a selected property value for compact display in plot titles.
if isstring(value)
    text = strjoin(value, ',');
elseif ischar(value)
    text = string(value);
elseif islogical(value)
    if isscalar(value)
        text = string(matlab.lang.OnOffSwitchState(value));
    else
        text = string(mat2str(value));
    end
elseif isnumeric(value)
    if isscalar(value)
        text = string(num2str(double(value), '%g'));
    else
        text = string(mat2str(double(value)));
    end
else
    text = string(value);
end
end
