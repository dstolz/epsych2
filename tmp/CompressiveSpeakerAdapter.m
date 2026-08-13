classdef CompressiveSpeakerAdapter < stimgen.calibration.HwAdapter
    % Simulated rig whose output compresses: response is
    % Gain * sign(x) .* |x|^Exponent, delayed and lightly noisy. The
    % compression is what iterative refinement exists to correct -- output
    % level no longer scales as 20*log10 of drive voltage, so a LUT built at
    % the excitation voltage mispredicts the drive the normative level needs
    % by (Exponent-1) * (normative - excitation-level) dB.
    %
    % FailAfterNCalls simulates a hardware fault partway through a run:
    % play_and_record errors once the call count exceeds it.

    properties
        Fs (1,1) double = 48000
        Gain (1,1) double = 0.1
        Exponent (1,1) double = 0.8
        DelaySamples (1,1) double = 100
        NoiseRms (1,1) double = 1e-5
        FailAfterNCalls (1,1) double = inf
        NCalls (1,1) double = 0
    end

    methods
        function obj = CompressiveSpeakerAdapter(fs)
            if nargin > 0, obj.Fs = fs; end
        end

        function Fs = sample_rate(obj)
            Fs = obj.Fs;
        end

        function response = play_and_record(obj, signal)
            obj.NCalls = obj.NCalls + 1;
            if obj.NCalls > obj.FailAfterNCalls
                error('tmp:CompressiveSpeakerAdapter:failed', ...
                    'Simulated hardware fault on acquisition %d.', obj.NCalls);
            end
            y = obj.Gain .* sign(signal) .* abs(signal) .^ obj.Exponent;
            y = [zeros(1, obj.DelaySamples), y];
            y = y(1:numel(signal));
            response = y + obj.NoiseRms .* randn(1, numel(signal));
        end
    end
end
