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

            
            obj.apply_gate;
            
            obj.apply_normalization;
            
            obj.apply_calibration;
        end

        function h = create_gui(obj, src, evnt)



            % Use a simple grid, similar to Tone
            g = uigridlayout(src, [4 2]);
            g.RowHeight    = repmat({'fit'}, 1, 8);
            g.ColumnWidth  = {'1x','1x'};

            % Carrier frequency
            uilabel(g, 'Text', 'Carrier (Hz)');
            h.CarrierFrequency = uieditfield(g, 'numeric', ...
                'Tag','CarrierFrequency', ...
                'Value', obj.CarrierFrequency, ...
                'Limits', [1 80000], ...  % Hz
                'ValueDisplayFormat', '%.1f');

            % Modulation frequency
            uilabel(g, 'Text', 'FM rate (Hz)');
            h.ModulationFrequency = uieditfield(g, 'numeric', ...
                'Tag','ModulationFrequency', ...
                'Value', obj.ModulationFrequency, ...
                'Limits', [0 40000], ...  % Hz
                'ValueDisplayFormat', '%.2f');

            % Modulation depth
            uilabel(g, 'Text', 'FM depth (Hz)');
            h.ModulationDepth = uieditfield(g, 'numeric', ...
                'Tag','ModulationDepth', ...
                'Value', obj.ModulationDepth, ...
                'Limits', [0 20000], ...  % Hz deviation
                'ValueDisplayFormat', '%.1f');

            % Onset phase
            uilabel(g, 'Text', 'Onset phase (rad)');
            h.OnsetPhase = uieditfield(g, 'numeric', ...
                'Tag','OnsetPhase', ...
                'Value', obj.OnsetPhase, ...
                'Limits', [-2*pi 2*pi], ...  % radians
                'ValueDisplayFormat', '%.3f');


            
            x = uilabel(g,'Text','Duration:');
            x.HorizontalAlignment = 'right';
            
            x = uieditfield(g,'numeric','Tag','Duration');
            x.Limits = [0.001 10];
            x.ValueDisplayFormat = '%.3f s';
            x.Value = obj.Duration;
            h.Duration = x;


            structfun(@(a) set(a,'ValueChangedFcn',@obj.interpret_gui),h);
            
            obj.GUIHandles = h;
            
                        
        end
        
    end


    methods (Access = protected)
        function interpret_gui(obj,src,event)
            try
                obj.(src.Tag) = event.Value;
            catch
                obj.(src.Tag) = event.PreviousValue;
            end
            
            if isequal(src.Tag,'WindowMethod')
                switch src.Value
                    case 'Proportional'
                        fmt = '%.2f%%';
                    case 'Duration'
                        fmt = '%.4f s';
                    case '#Periods'
                        fmt = '%.1f periods';
                end
                obj.GUIHandles.WindowDuration.ValueDisplayFormat = fmt;
            end

            obj.update_signal;
        end
        
    end
end
