classdef DeadMicAdapter < stimgen.calibration.HwAdapter
    % Disconnected-microphone rig for headless testing: whatever is played,
    % only noise comes back. Exercises the paths that must refuse to trust a
    % measurement, e.g. Engine.measure_conduction_delay validity checking.

    properties
        Fs (1,1) double = 44100
        NoiseRms (1,1) double = 1e-4
    end

    methods
        function Fs = sample_rate(obj)
            Fs = obj.Fs;
        end

        function response = play_and_record(obj, signal)
            response = obj.NoiseRms .* randn(1, numel(signal));
        end
    end
end
