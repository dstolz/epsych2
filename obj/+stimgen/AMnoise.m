classdef AMnoise < stimgen.Noise

    % obj = stimgen.AMnoise(Name,Value,...)
    % Amplitude-modulated band-limited noise stimulus.
    %
    % Generates a noise carrier (via stimgen.Noise) and applies sinusoidal
    % amplitude modulation with adjustable depth and rate.
    
    properties (SetObservable,AbortSet)
        AMDepth (1,1) double {mustBeGreaterThanOrEqual(AMDepth,0),mustBeLessThanOrEqual(AMDepth,1)} = 1; % [0 1] 
        AMRate  (1,1) double {mustBePositive,mustBeFinite} = 5; % Hz
        
        OnsetPhase (1,1) double = 180; % degrees
        
%         AMExponential (1,1) double
        
        EnvelopeOnly (1,1) logical = false;
        
        ApplyViemeisterCorrection (1,1) logical = true;
    end
    
    

    properties (Constant)
        %IsMultiObj      = false;
        %CalibrationType = "noise"; % defined in stimgen.Noise superclass
        %Normalization = "rms"; % defined in stimgen.Noise superclass
    end
    
    methods
                
        function obj = AMnoise(varargin)
            obj = obj@stimgen.Noise(varargin{:});

            obj.DisplayName = 'AM Noise';
            obj.UserProperties = ["SoundLevel","Duration","WindowDuration","ApplyWindow","HighPass","LowPass","AMDepth","AMRate","OnsetPhase","EnvelopeOnly","ApplyViemeisterCorrection"]; 
                        
            obj.Duration = 1;
        end
        
        
        function update_signal(obj)
            obj.temporarilyDisableSignalMods = true;
            
            update_signal@stimgen.Noise(obj);
            noise = obj.Signal;
            
            obj.temporarilyDisableSignalMods = false;
           
            
%             x(t) = A(t) sin(2 pi fc t)
%             A(t) = A [1 + m sin(2 pi fm t)]

            
            am = cos(2.*pi.*obj.AMRate.*obj.Time+deg2rad(obj.OnsetPhase));
            am = (am + 1)./2;
            am = am .* obj.AMDepth + 1 - obj.AMDepth;
            
            if obj.ApplyViemeisterCorrection
                am = am .* sqrt(1/(obj.AMDepth^2/2+1));
            end
            
            if obj.EnvelopeOnly
                obj.Signal = am;
            else
                obj.Signal = noise .* am;
            end
            
            obj.apply_gate;
            
            obj.apply_normalization;
            
            obj.apply_calibration;
        end
    end

    methods (Access = protected)
        function m = propMeta(obj)
            % propMeta() - Display metadata for AMnoise GUI properties.
            m = struct();
            m.AMDepth    = struct('label', 'AM Depth',              'format', '%.2f',     'limits', [0 1]);
            m.AMRate     = struct('label', 'AM Rate',               'format', '%.1f Hz',  'limits', [0.1 500]);
            m.OnsetPhase = struct('label', 'Onset Phase',           'format', '%.1f deg');
            m.EnvelopeOnly               = struct('label', 'Envelope Only');
            m.ApplyViemeisterCorrection  = struct('label', 'Viemeister Correction');
            m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.Noise(obj));
        end
    end

