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

    properties (Constant, Hidden)
        CalibrationType = "tone"
        Normalization   = "absmax"
    end

    methods
        function obj = FMtone(Fs, Calibration)
            %FMtone  Construct an FM tone stimulus.

            obj@stimgen.StimType(Fs, Calibration);
            obj.Name        = 'FM Tone';
            obj.DisplayName = 'FMtone';

            obj.update_signal;
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

            
            obj.apply_gate;
            
            obj.apply_normalization;
            
            obj.apply_calibration;
        end

        function h = create_gui(obj, parent)
            %CREATE_GUI  Create parameter controls for FMtone.
            %   h = create_gui(obj, parent) creates UI controls for
            %   CarrierFrequency, ModulationFrequency, ModulationDepth, and
            %   OnsetPhase in the specified parent container (uipanel/figure).
            %   Returns a struct of handle references.

            arguments
                obj
                parent = []
            end

            if isempty(parent)
                parent = uipanel('Title','FM Tone');
            end

            % Use a simple grid, similar to Tone
            gl = uigridlayout(parent, [4 2]);
            gl.RowHeight    = repmat({'fit'}, 1, 4);
            gl.ColumnWidth  = {'1x','1x'};

            % Carrier frequency
            uilabel(gl, 'Text', 'Carrier (Hz)');
            h.edCarrier = uieditfield(gl, 'numeric', ...
                'Value', obj.CarrierFrequency, ...
                'Limits', [1 80000], ...  % Hz
                'ValueDisplayFormat', '%.1f', ...
                'ValueChangedFcn', @(src,~) set(obj, 'CarrierFrequency', src.Value));

            % Modulation frequency
            uilabel(gl, 'Text', 'FM rate (Hz)');
            h.edModFreq = uieditfield(gl, 'numeric', ...
                'Value', obj.ModulationFrequency, ...
                'Limits', [0 40000], ...  % Hz
                'ValueDisplayFormat', '%.2f', ...
                'ValueChangedFcn', @(src,~) set(obj, 'ModulationFrequency', src.Value));

            % Modulation depth
            uilabel(gl, 'Text', 'FM depth (Hz)');
            h.edModDepth = uieditfield(gl, 'numeric', ...
                'Value', obj.ModulationDepth, ...
                'Limits', [0 20000], ...  % Hz deviation
                'ValueDisplayFormat', '%.1f', ...
                'ValueChangedFcn', @(src,~) set(obj, 'ModulationDepth', src.Value));

            % Onset phase
            uilabel(gl, 'Text', 'Onset phase (rad)');
            h.edPhase = uieditfield(gl, 'numeric', ...
                'Value', obj.OnsetPhase, ...
                'Limits', [-2*pi 2*pi], ...  % radians
                'ValueDisplayFormat', '%.3f', ...
                'ValueChangedFcn', @(src,~) set(obj, 'OnsetPhase', src.Value));
        end
    end
end
