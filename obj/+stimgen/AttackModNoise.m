classdef AttackModNoise < stimgen.Noise

    % obj = stimgen.AttackModNoise(Name,Value,...)
    % Attack-modulated band-limited noise stimulus.
    %
    % Generates a noise carrier (via stimgen.Noise) and applies a ramped/
    % damped modulation envelope controlled by Z and AMRate.
    
    properties (SetObservable,AbortSet)
        AMDepth (1,1) double {mustBeGreaterThanOrEqual(AMDepth,0),mustBeLessThanOrEqual(AMDepth,1)} = 1; % [0 1] 
        AMRate  (1,1) double {mustBePositive,mustBeFinite} = 5; % Hz
        OnsetPhase (1,1) double = 0; % degrees
        
        Z     (1,1) double {mustBeGreaterThanOrEqual(Z,-1),mustBeLessThanOrEqual(Z,1)} = .4; % note that this gets converted to ramped/damped z = [1 2]
        
        AddOnOffperiods (1,1) logical = false;
        
        EnvelopeOnly (1,1) logical = false;
        
        ApplyViemeisterCorrection (1,1) logical = true;
    end
    
    
    properties (Constant)
        %IsMultiObj      = false;
        %CalibrationType = "noise"; % defined in stimgen.Noise superclass
        %Normalization = "rms"; % defined in stimgen.Noise superclass
    end
    
    methods
                
        function obj = AttackModNoise(varargin)
            obj = obj@stimgen.Noise(varargin{:});
            
            obj.DisplayName = 'Attack Modulated Noise';

            obj.UserProperties = ["SoundLevel","Duration","WindowDuration","ApplyWindow","HighPass","LowPass","AMDepth","AMRate","Z","EnvelopeOnly","ApplyViemeisterCorrection"];
            
            % override some default StimType property values
            obj.Duration = 1;
        end
        
        
        function update_signal(obj)
            if ~obj.EnvelopeOnly
                
                obj.temporarilyDisableSignalMods = true;
                
                update_signal@stimgen.Noise(obj);
                noise = obj.Signal;
                obj.temporarilyDisableSignalMods = false;
                
            end

            z = obj.Z;
            
            period = 1/obj.AMRate;
            t = linspace(0,1,round(period*obj.Fs));
            am = t.^(1-abs(z)).*(1-t);
            
            if z < 0 % Ramped
                am = fliplr(am);
            end

            am = am ./ max(am);
            
            nperiods = ceil(obj.Duration/period);
            
            am = repmat(am,1,nperiods);
            
            am(obj.N+1:end) = [];
            am(end+1:obj.N) = 0;
            
            if obj.AddOnOffperiods
                [~,i] = max(am);
                am = [am(i+1:end) am am(1:i)];
            end

            if obj.ApplyViemeisterCorrection
                am = am .* sqrt(1/(obj.AMDepth^2/2+1));
            end
            
            if obj.EnvelopeOnly
                obj.Signal = am;
            else
                obj.Signal = noise .* am;
            end
            
            obj.apply_normalization;
            
            obj.apply_calibration;
            
            obj.apply_gate;
        end
    end

    methods (Access = protected)
        function m = propMeta(obj)
            % propMeta() - Display metadata for AttackModNoise GUI properties.
            m = struct();
            m.Z          = struct('label', 'Z (Ramp/Damp)',         'format', '%.3f',    'limits', [-1 1]);
            m.AMDepth    = struct('label', 'AM Depth',              'format', '%.2f',    'limits', [0 1]);
            m.AMRate     = struct('label', 'AM Rate',               'format', '%.1f Hz', 'limits', [0.1 500]);
            m.EnvelopeOnly              = struct('label', 'Envelope Only');
            m.ApplyViemeisterCorrection = struct('label', 'Viemeister Correction');
            m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.Noise(obj));
        end
    end

end
