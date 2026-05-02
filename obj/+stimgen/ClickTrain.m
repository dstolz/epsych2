classdef ClickTrain < stimgen.StimType

    % obj = stimgen.ClickTrain(Name,Value,...)
    % Click-train stimulus generator.
    %
    % Generates a train of short-duration clicks at a specified Rate,
    % polarity pattern, and duration.
    
    
    properties (AbortSet,SetObservable)
        Rate        (1,:) double {mustBePositive,mustBeFinite} = 10; % Hz
        Polarity    (1,:) double {mustBeMember(Polarity,[-1 0 1])} = 1;
        ClickDuration (1,:) double {mustBePositive,mustBeFinite} = 20e-6; % s
        OnsetDelay  (1,:) double {mustBeNonnegative,mustBeFinite} = 0; % sec
        Truncate    (1,:) logical = false;
    end
    
    properties (Dependent)
        ClickInterval
    end

    
    properties (Constant)
        IsMultiObj      = false;
        CalibrationType = "click";
        Normalization   = "absmax"
    end
    
    methods
        
        function obj = ClickTrain(varargin)
            
            obj = obj@stimgen.StimType(varargin{:});

            obj.DisplayName = 'Click Train';

            obj.UserProperties = ["SoundLevel","Duration","WindowDuration","ApplyWindow","Rate","Polarity","ClickDuration","OnsetDelay","Truncate"];

            % override some default StimType property values
            obj.Duration = 1;
            obj.ApplyWindow = false;
            obj.WindowFcn = "";
            
            
        end
        
        
        function ci = get.ClickInterval(obj)
            ci = 1/obj.Rate;
        end
        
        function update_signal(obj)
            if ~obj.variantCycleActive_
                obj.call_update_signal_with_variant_cycle_();
                return
            end

            fsValue = double(obj.selected_value("Fs"));
            d = double(obj.selected_value("Duration"));
            rate = double(obj.selected_value("Rate"));
            polarity = double(obj.selected_value("Polarity"));
            clickDuration = double(obj.selected_value("ClickDuration"));
            onsetDelay = double(obj.selected_value("OnsetDelay"));
            truncateValue = logical(obj.selected_value("Truncate"));

            p = 1 / rate;

            assert(clickDuration <= p,'stimgen:ClickTrain:ClickDuration:InvalidValue', ...
                'Click duration is too long for the selected click Rate');
            assert(round(fsValue*clickDuration) > 0,'stimgen:ClickTrain:ClickDuration:InvalidValue', ...
                'Click duration is less than 1 sample at the current sampling rate');
            
            y = ones(1,round(fsValue*clickDuration));
            
            
            yoff = zeros(1,round(fsValue*p)-length(y));
            y = [y yoff];
            
            yd = length(y)/fsValue;
            n = max(floor(d / yd),1);
            
            if polarity == 0
                x = -1;
                yx = y;
                for i = 2:n
                    y = [y x*yx];
                    x = -x;
                end
            else
                y = polarity .* y;
                y = repmat(y,1,n);
            end
            
            yon  = zeros(1,max(round(fsValue*onsetDelay-1/fsValue),0));
            y = [yon y];
            
            if ~truncateValue && obj.N > length(y)
                y = [y,zeros(1,obj.N-length(y))];
            elseif obj.N < length(y)
                y(obj.N+1:end) = [];
            end
            
            obj.Signal = y;
            
            
            obj.apply_normalization;
            
            obj.apply_calibration;
            
            obj.apply_gate;
        end
    end

    methods (Access = protected)
        function m = propMeta(obj)
            % propMeta() - Display metadata for ClickTrain GUI properties.
            m = struct();
            m.Rate          = struct('label', 'Rate',           'format', '%.1f Hz',  'limits', [0.1 1e6]);
            m.ClickDuration = struct('label', 'Click Duration', 'format', '%.6f s',   'limits', [1e-6 1]);
            m.Polarity      = struct('label', 'Polarity', 'widget', 'dropdown', ...
                                    'items',     {{'+ Positive', '+/- Alternate', '- Negative'}}, ...
                                    'itemsData', {{1, 0, -1}});
            m.OnsetDelay    = struct('label', 'Onset Delay',    'format', '%.4f s');
            m.Truncate      = struct('label', 'Truncate');
            base = propMeta@stimgen.StimType(obj);
            base.Duration.label = 'Train Duration';
            m = stimgen.StimType.merge_prop_meta(m, base);
        end
    end

end