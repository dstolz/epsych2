classdef CalibratorAdapter < stimgen.calibration.HwAdapter
    % CalibratorAdapter(fs, toneFreq, micSensitivity, toneOn)
    % Test double standing in for a rig with an acoustic calibrator (PCB
    % CAL150 and the like) seated on the microphone.
    %
    % Whatever it is asked to play, the recording it returns is the
    % calibrator's own 94 dB SPL tone plus a little noise -- which is exactly
    % the situation calibrate_reference has to handle. LastPlayed records the
    % waveform sent to the output so a test can assert the speaker stayed
    % silent.
    %
    % Parameters:
    %   fs             - (1,1) double sample rate, Hz
    %   toneFreq       - (1,1) double calibrator frequency, Hz
    %   micSensitivity - (1,1) double the V/Pa the fake mic is built with
    %   toneOn         - (1,1) logical false simulates a calibrator left off

    properties (SetAccess = private)
        LastPlayed (1,:) double = []   % waveform handed to the output
        PlayCount  (1,1) double = 0
    end

    properties (Access = private)
        Fs_ (1,1) double
        ToneFreq_ (1,1) double
        Sensitivity_ (1,1) double
        ToneOn_ (1,1) logical
    end

    methods
        function obj = CalibratorAdapter(fs, toneFreq, micSensitivity, toneOn)
            arguments
                fs (1,1) double
                toneFreq (1,1) double
                micSensitivity (1,1) double
                toneOn (1,1) logical = true
            end
            obj.Fs_ = fs;
            obj.ToneFreq_ = toneFreq;
            obj.Sensitivity_ = micSensitivity;
            obj.ToneOn_ = toneOn;
        end

        function Fs = sample_rate(obj)
            Fs = obj.Fs_;
        end

        function response = play_and_record(obj, signal)
            obj.LastPlayed = signal;
            obj.PlayCount = obj.PlayCount + 1;

            n = numel(signal);
            t = (0:n-1) / obj.Fs_;

            % 94 dB SPL = 1 Pa RMS, so the mic delivers Sensitivity_ V RMS.
            response = 1e-6 * randn(1, n);   % quiet electrical noise floor
            if obj.ToneOn_
                response = response + ...
                    sqrt(2) * obj.Sensitivity_ * sin(2*pi*obj.ToneFreq_*t + 0.3);
            end
        end
    end
end
