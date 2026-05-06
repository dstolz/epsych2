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

    % --- Constructor and property accessors (inline) ---
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

    end % methods (constructor + property accessors)

    % --- Public external method declarations ---
    methods
        S = toStruct(obj)                                                         % Serialize to struct
        h = plot(obj, ax)                                                         % Plot Signal vs Time
        h = plot_spectrogram(obj, ax, nfft, overlap, window)                      % Plot power spectrogram
        play(obj)                                                                  % Audition current Signal
        v = selected_value(obj, propName)                                         % Scalar value for a vectorized property
        value = evalPropertyExpression(obj, propName, expressionText)             % Evaluate a property expression
        info = get_variant_info(obj)                                              % Variant-combination state
        info = set_variant_index(obj, idx)                                        % Select variant by index
        info = step_variant(obj, step)                                            % Step variant index
        text = current_parameter_summary(obj)                                     % Non-default parameter summary
        h = create_gui(obj, src, event)                                           % Auto-build parameter GUI
        m = get_prop_meta(obj)                                                    % Public accessor for propMeta()
    end % methods (public external)

    % --- Protected external method declarations ---
    methods (Access = protected)
        apply_normalization(obj)                                                   % Normalize Signal
        apply_gate(obj)                                                            % Apply onset/offset window to Signal
        apply_calibration(obj)                                                     % Apply LUT or filter+gain calibration
        create_listeners(obj)                                                      % Attach PostSet listeners to observable properties
        onPropertyChanged(obj, src, event)                                         % Listener: recompute Signal and refresh plot
        refresh_plot_if_valid(obj)                                                 % Update live plot line if handle is valid
        update_handle_value(obj, src, event)                                       % Sync GUI widget to property value
        interpret_gui(obj, src, event)                                             % Parse and apply widget value-change
        call_update_signal_with_variant_cycle_(obj)                               % Wrap update_signal with one variant selection
        begin_variant_cycle_(obj)                                                  % Select and lock active variant index
        end_variant_cycle_(obj)                                                    % Release variant cycle lock
        value = get_selected_property_value_(obj, propName)                       % Scalar value using active variant
        refresh_variant_cache_if_needed_(obj)                                     % Rebuild combination table when signature changes
        [propNames, propValues] = get_variant_source_values_(obj)                 % Collect vectorized property values
        signature = build_variant_signature_(obj, propNames, propValues)          % Hash string for cache invalidation
        [comboTable, comboProps] = build_variant_combinations_(obj, propNames, propValues) % Build combination table
        idx = select_variant_index_(obj)                                          % Choose next variant index per selection mode
        selector = get_or_create_variant_selector_(obj)                           % Lazy-init custom selector object
        tf = is_non_vectorizable_property_(obj, propName)                         % True for Fs, ApplyCalibration, ApplyWindow
        info = apply_variant_index_and_update_(obj, idx)                          % Lock index, update signal, return info
        value = evaluate_property_expression_(obj, propName, expressionText)      % Evaluate guarded MATLAB expression
        context = build_expression_context_(obj, targetPropName)                  % Numeric property context for eval
        expressionText = rewrite_qualified_property_refs_(obj, expressionText)    % Replace Class.Prop refs with bare Prop
        tf = is_variant_policy_property_(obj, propName)                           % True for variant-policy property names
        on_gui_changed(obj, propName, value)                                       % Hook: called after GUI widget change
        m = propMeta(obj)                                                          % Return GUI display metadata struct
    end % methods (protected external)

    % --- Static protected (inline: cannot live in external files) ---
    methods (Static, Access = protected)
        m = merge_prop_meta(a, b)                                                 % Append fields of b into a
        wt = resolve_widget_type(propName, pm, pl)                                % Infer widget type from metadata/property class
    end % methods (Static, Access = protected)

    methods (Static)
        obj = fromStruct(S)                                                        % Reconstruct StimType from serialized struct
        c = list                                                                    % Enumerate available stimgen stimulus classes
    end % methods (Static)

    methods (Static, Access = private)
        text = localFormatPropertyValue_(value)                                   % Format numeric values for GUI edit fields
        text = format_summary_value_(value)                                       % Format values for compact parameter summary
    end % methods (Static, Access = private)

end
