classdef Noise < stimgen.StimType

    % obj = stimgen.Noise(Name,Value,...)
    % Band-limited noise stimulus generator.
    %
    % Generates Gaussian noise filtered between HighPass and LowPass.
    % The waveform is optionally windowed/gated and calibrated.
    
    properties (SetObservable,AbortSet)
        HighPass  (1,:) double {mustBeNonnegative,mustBeFinite} = 500; % Hz
        LowPass   (1,:) double {mustBeNonnegative,mustBeFinite} = 20000; % Hz
        
        FilterOrder (1,1) double {mustBePositive,mustBeInteger,mustBeFinite} = 40;
        digFilter % designfilt object
    end
   
    
    properties (Constant)
        IsMultiObj      = false;
        CalibrationType = "filter";
        Normalization   = "rms";
    end
    
    methods
                
        function obj = Noise(varargin)
            obj = obj@stimgen.StimType(varargin{:});

            obj.DisplayName = 'Noise';

            obj.UserProperties = ["SoundLevel","Duration","WindowDuration","ApplyWindow","HighPass","LowPass"];
        end
        
        function set.digFilter(obj,d)
            assert(isa(d,'digitalFilter'),'Must use a designfilt object')            
            obj.digFilter = d;
        end
        
        function update_signal(obj)
            if ~obj.variantCycleActive_
                obj.call_update_signal_with_variant_cycle_();
                return
            end

            t = obj.Time;
            highPass = double(obj.selected_value("HighPass"));
            lowPass = double(obj.selected_value("LowPass"));

            if lowPass <= highPass
                error('stimgen:Noise:InvalidBand', 'LowPass must be greater than HighPass.');
            end

            y = randn(length(t),1);
            
            obj.update_digFilter(highPass, lowPass);
            y = filter(obj.digFilter,y);
            
            obj.Signal = y';
            
            obj.apply_normalization;
            
            obj.apply_calibration;
            
            obj.apply_gate;
        end
    
        function update_digFilter(obj, highPass, lowPass)
            if nargin < 2
                highPass = double(obj.selected_value("HighPass"));
                lowPass = double(obj.selected_value("LowPass"));
            end
            fsValue = double(obj.selected_value("Fs"));
            obj.digFilter = designfilt('bandpassfir', ...
                    'FilterOrder',obj.FilterOrder, ...
                    'CutoffFrequency1',highPass, ...
                    'CutoffFrequency2',lowPass, ...
                    'SampleRate',fsValue);
        end
        
        
        
    end

    methods (Access = protected)
        function m = propMeta(obj)
            % propMeta() - Display metadata for Noise GUI properties.
            m = struct();
            m.HighPass = struct('label', 'High Pass Fc', 'format', '%.1f Hz', 'limits', [100 40000]);
            m.LowPass  = struct('label', 'Low Pass Fc',  'format', '%.1f Hz', 'limits', [100 40000]);
            m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.StimType(obj));
        end
    end

end
