classdef FMtone < stimgen.StimType
    %FMtone  Frequency-modulated tone stimulus.
    %   obj = stimgen.FMtone(Fs, Calibration) creates an FM tone stimulus
    %   object with sampling rate Fs (Hz) and optional stimgen.StimCalibration
    %   object. Frequency modulation is defined by:
    %
    %     CarrierFrequency      - carrier frequency (Hz)
    %     ModulationFrequency   - modulation frequency (Hz)
    %     ModulationDepth       - peak deviation of instantaneous frequency (Hz)
    %     OnsetPhase            - initial phase of the carrier (radians)
    %
    %   Base-class properties (SoundLevel, Duration, WindowDuration,
    %   ApplyCalibration, etc.) control level, timing, and windowing.

    properties
        CarrierFrequency    (1,1) double {mustBePositive}    = 4000
        ModulationFrequency (1,1) double {mustBeNonnegative} = 10
        ModulationDepth     (1,1) double {mustBeNonnegative} = 1000
        OnsetPhase          (1,1) double                     = 0
    end
    

    properties (Constant)
        IsMultiObj      = false;
        CalibrationType = "filter"
        Normalization   = "absmax"
    end

    methods
        function obj = FMtone(varargin)
            %FMtone  Construct an FM tone stimulus.

            obj@stimgen.StimType(varargin{:});

            obj.DisplayName = 'FM Tone';
            obj.UserProperties = ["SoundLevel","Duration","WindowDuration","ApplyWindow","CarrierFrequency","ModulationFrequency","ModulationDepth","OnsetPhase"];


        end

        function update_signal(obj)
            %UPDATE_SIGNAL  Regenerate the FM tone waveform.

            t  = obj.Time;  % column vector from base class
            fc = obj.CarrierFrequency;
            fm = obj.ModulationFrequency;
            fd = obj.ModulationDepth;

            if fm == 0 || fd == 0
                % Reduce to pure tone if no modulation
                phase = 2*pi*fc*t + obj.OnsetPhase;
            else
                % Instantaneous frequency: f(t) = Fc + D*sin(2*pi*Fm*t)
                % Phase is integral of f(t):
                %   phi(t) = 2*pi*Fc*t - (2*pi*D/Fm)*cos(2*pi*Fm*t) + const
                phase = 2*pi*fc*t - (2*pi*fd/fm)*cos(2*pi*fm*t) + ...
                        (2*pi*fd/fm) + obj.OnsetPhase;
            end

            x = sin(phase);

                        % Set raw signal; any further processing should be handled
            % consistently with how Tone is implemented.
            obj.Signal = x;

            
            obj.apply_normalization;
            
            obj.apply_calibration;
            
            obj.apply_gate;
        end

    end

    methods (Access = protected)
        function m = propMeta(obj)
            % propMeta() - Display metadata for FMtone GUI properties.
            m = struct();
            m.CarrierFrequency    = struct('label', 'Carrier Freq',  'format', '%.1f Hz',  'limits', [1 80000]);
            m.ModulationFrequency = struct('label', 'FM Rate',        'format', '%.2f Hz',  'limits', [0 40000]);
            m.ModulationDepth     = struct('label', 'FM Depth (Hz)',  'format', '%.1f Hz',  'limits', [0 20000]);
            m.OnsetPhase          = struct('label', 'Onset Phase',    'format', '%.3f rad');
            m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.StimType(obj));
        end
    end
end
