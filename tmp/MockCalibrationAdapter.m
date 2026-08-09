classdef MockCalibrationAdapter < stimgen.calibration.HwAdapter
    % MockCalibrationAdapter
    % Test double for stimgen.calibration.HwAdapter.
    %
    % Returns a scaled copy of the input signal to simulate a microphone
    % recording a speaker. The simulated mic sensitivity is 0.01 V/Pa,
    % and the simulated SPL at the reference excitation is approximately
    % proportional to the input RMS.
    %
    % This class is used exclusively for smoke testing and unit-style
    % integration tests. It must NOT be used in production.
    %
    % Example:
    %   adapter = MockCalibrationAdapter(48000);
    %   eng = stimgen.calibration.Engine(adapter);

    properties (Access = private)
        Fs_ (1,1) double
        MicSensitivity_ (1,1) double = 0.01  % simulated V/Pa
    end

    methods
        function obj = MockCalibrationAdapter(Fs)
            % obj = MockCalibrationAdapter(Fs)
            % Parameters:
            %   Fs - (1,1) double sample rate in Hz (default 48000)
            arguments
                Fs (1,1) double {mustBePositive,mustBeFinite} = 48000
            end
            obj.Fs_ = Fs;
        end

        function Fs = sample_rate(obj)
            % Fs = sample_rate(obj)
            % Return configured sample rate in Hz.
            Fs = obj.Fs_;
        end

        function response = play_and_record(obj, signal)
            % response = play_and_record(obj, signal)
            % Simulate speaker→mic path: returns signal scaled by mic sensitivity
            % with a small amount of additive Gaussian noise for realism.
            %
            % Parameters:
            %   signal   - (1,:) double excitation waveform
            %
            % Returns:
            %   response - (1,:) double simulated microphone response
            arguments
                obj
                signal (1,:) double {mustBeReal,mustBeFinite}
            end

            % Simulate: microphone captures speaker output with sensitivity scaling
            % plus −60 dB noise floor.
            noiseFloor = 1e-3 * randn(size(signal));
            response = obj.MicSensitivity_ .* signal + noiseFloor;
        end
    end
end
