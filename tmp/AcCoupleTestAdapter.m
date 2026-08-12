classdef AcCoupleTestAdapter < stimgen.calibration.HwAdapter
    % Deterministic microphone for AC-coupling tests: a steady tone riding on
    % a DC offset and a slow baseline drift, with no noise at all so two
    % acquisitions of the same length return bit-identical records.

    properties
        Fs        (1,1) double = 48000
        ToneFreq  (1,1) double = 2000    % Hz, the "signal" that must survive
        ToneAmp   (1,1) double = 0.2     % V
        DriftFreq (1,1) double = 3       % Hz, below the coupling corner
        DriftAmp  (1,1) double = 0.05    % V
        DcOffset  (1,1) double = 0.08    % V
    end

    methods
        function obj = AcCoupleTestAdapter(fs)
            if nargin > 0, obj.Fs = fs; end
        end

        function fs = sample_rate(obj)
            fs = obj.Fs;
        end

        function response = play_and_record(obj, signal)
            n = numel(signal);
            t = (0:n-1) / obj.Fs;
            response = obj.ToneAmp  .* sin(2*pi*obj.ToneFreq  .* t) ...
                     + obj.DriftAmp .* sin(2*pi*obj.DriftFreq .* t) ...
                     + obj.DcOffset;
        end
    end
end
