classdef FakeSpeakerAdapter < stimgen.calibration.HwAdapter
    % Simulated rig for headless testing: the "speaker" is a fixed FIR
    % coloration plus a small delay and additive noise.

    properties
        Fs (1,1) double = 44100
        Coloration (1,:) double   % FIR the response is convolved with
        DelaySamples (1,1) double = 20
        NoiseRms (1,1) double = 1e-5
    end

    methods
        function obj = FakeSpeakerAdapter(fs)
            if nargin > 0, obj.Fs = fs; end
            % Non-flat but smooth magnitude: a lowpass-ish tilt plus a mid dip.
            n = 128;
            t = (0:n-1);
            h = exp(-t/18) .* cos(2*pi*t/34);
            obj.Coloration = h ./ max(abs(h));
        end

        function Fs = sample_rate(obj)
            Fs = obj.Fs;
        end

        function response = play_and_record(obj, signal)
            y = conv(signal, obj.Coloration);
            y = [zeros(1, obj.DelaySamples), y];
            y = y(1:numel(signal));
            response = 0.05 .* y + obj.NoiseRms .* randn(1, numel(signal));
        end
    end
end
