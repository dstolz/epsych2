classdef JitterLoopbackAdapter < stimgen.calibration.HwAdapter
    % Simulated rig whose acquisition latency changes on every
    % play_and_record call -- the regime observed on real TDT hardware,
    % where the latency of a short probe record did not carry over to a
    % long tone-train record. Exercises the per-acquisition embedded click
    % probe: only a delay measured from the same record it segments can
    % place the analysis windows correctly here.

    properties
        Fs (1,1) double = 44100
        Delays (1,:) double = [100 180 260]   % cycled per call, in samples
        Gain (1,1) double = 0.05
        NoiseRms (1,1) double = 1e-5
        CallCount (1,1) double = 0
        DelayLog (1,:) double = []   % delay actually applied to each call
    end

    methods
        function obj = JitterLoopbackAdapter(fs)
            if nargin > 0, obj.Fs = fs; end
        end

        function Fs = sample_rate(obj)
            Fs = obj.Fs;
        end

        function response = play_and_record(obj, signal)
            obj.CallCount = obj.CallCount + 1;
            d = obj.Delays(mod(obj.CallCount - 1, numel(obj.Delays)) + 1);
            obj.DelayLog(end+1) = d;
            n = numel(signal);
            response = [zeros(1, d), obj.Gain .* signal(1:n-d)] ...
                + obj.NoiseRms .* randn(1, n);
        end
    end
end
