classdef (Abstract) HwAdapter < handle
    % stimgen.calibration.HwAdapter
    % Abstract hardware adapter for calibration I/O.
    %
    % Concrete subclasses supply the sample rate and implement play_and_record()
    % to send an excitation waveform to hardware and return the microphone
    % response. Implementations are expected to validate their required
    % capabilities at construction time and error immediately if anything is
    % absent (fail-fast).
    %
    % See also: stimgen.calibration.WindowsSoundCardAdapter, stimgen.calibration.Engine,
    %           documentation/stimgen/stimgen_calibration.md

    methods (Abstract)
        % Fs = sample_rate(obj)
        % Return the hardware sample rate in Hz.
        Fs = sample_rate(obj)

        % response = play_and_record(obj, signal)
        % Play signal (1-D double, unit-amplitude, already scaled by
        % ExcitationVoltage) through the hardware output and simultaneously
        % record the microphone response.
        %
        % Parameters:
        %   signal   - (1,:) double output waveform
        %
        % Returns:
        %   response - (1,:) double recorded microphone signal
        response = play_and_record(obj, signal)
    end
end
