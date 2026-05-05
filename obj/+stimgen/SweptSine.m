classdef SweptSine < stimgen.StimType
    % obj = stimgen.SweptSine(Name,Value,...)
    % Log-sine swept chirp stimulus generator.
    %
    % Generates a logarithmic frequency sweep (chirp) from StartFrequency to
    % StopFrequency over Duration seconds. Optionally windowed/gated and calibrated.
    %
    % The log-sine chirp has a naturally pink spectrum and low crest factor (~4 dB),
    % making it ideal for broadband calibration measurements. Unlike MLS or filtered
    % noise, harmonic distortion products can be time-separated in the impulse
    % response, enabling distortion-free fundamental measurements.
    %
    % References:
    %   - Chan, I.H. "Swept Sine Chirps for Measuring Impulse Response"
    %     Stanford Research Systems, 2010
    %
    % Example:
    %   cs = stimgen.SweptSine('Fs', 48000, 'StartFrequency', 100, 'StopFrequency', 20000, ...
    %                          'Duration', 1);
    %   cs.update_signal();
    %   sound(cs.Signal, cs.Fs);

    properties (SetObservable, AbortSet)
        StartFrequency  (1,1) double {mustBePositive, mustBeFinite} = 100    % Hz
        StopFrequency   (1,1) double {mustBePositive, mustBeFinite} = 20000  % Hz
        ChirpType       (1,1) string {mustBeMember(ChirpType, ["log-sine", "linear"])} = "log-sine"
    end

    properties (Constant)
        IsMultiObj      = false
        CalibrationType = "swept_sine"
        Normalization   = "absmax"
    end

    methods
        function obj = SweptSine(varargin)
            obj = obj@stimgen.StimType(varargin{:});

            obj.DisplayName = 'Swept Sine';
            obj.UserProperties = ["StartFrequency", "StopFrequency", "ChirpType", ...
                                   "SoundLevel", "Duration", "WindowDuration", ...
                                   "ApplyWindow"];
        end

        function update_signal(obj)
            if ~obj.variantCycleActive_
                obj.call_update_signal_with_variant_cycle_();
                return
            end

            t       = obj.Time;
            f1      = double(obj.selected_value("StartFrequency"));
            f2      = double(obj.selected_value("StopFrequency"));
            T       = t(end);

            % Ensure f1 < f2
            if f1 >= f2
                error('stimgen:SweptSine:badFreqRange', ...
                      'StartFrequency (%.1f Hz) must be < StopFrequency (%.1f Hz)', f1, f2);
            end

            switch obj.ChirpType
                case "log-sine"
                    obj.Signal = obj.generate_log_sine_chirp_(t, f1, f2, T);
                case "linear"
                    obj.Signal = obj.generate_linear_chirp_(t, f1, f2, T);
            end

            obj.apply_normalization();
            obj.apply_calibration();
            obj.apply_gate();
        end

    end

    methods (Access = private)

        function x = generate_log_sine_chirp_(~, t, f1, f2, T)
            % x = generate_log_sine_chirp_(obj, t, f1, f2, T)
            % Generate log-sine (exponential) chirp from f1 to f2 over duration T.
            %
            % Equation: x(t) = sin((2π*f1*T / ln(f2/f1)) * (exp(ln(f2/f1)*t/T) - 1))
            % This exponentially increases frequency from f1 to f2.

            K = (2 * pi * f1 * T) / log(f2 / f1);
            exponent = log(f2 / f1) * t / T;

            % Avoid underflow for very small exponents
            exponent = max(exponent, -1e-16);

            x = sin(K * (exp(exponent) - 1));
        end

        function x = generate_linear_chirp_(~, t, f1, f2, T)
            % x = generate_linear_chirp_(obj, t, f1, f2, T)
            % Generate linear frequency sweep (for comparison/testing).
            %
            % Equation: x(t) = sin(2π * (f1*t + (f2-f1)*t²/(2T)))

            phase = 2 * pi * (f1 * t + (f2 - f1) * t.^2 / (2 * T));
            x = sin(phase);
        end

    end

    methods (Access = protected)

        function m = propMeta(obj)
            % propMeta() - Display metadata for SweptSine GUI properties.
            m = struct();
            m.StartFrequency = struct('label', 'Start Freq',  'format', '%.1f Hz', 'limits', [10 40000]);
            m.StopFrequency  = struct('label', 'Stop Freq',   'format', '%.1f Hz', 'limits', [10 40000]);
            m.ChirpType      = struct('label', 'Chirp Type', 'widget', 'dropdown', ...
                                      'items', ["log-sine", "linear"]);
            m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.StimType(obj));
        end

    end

end
