classdef WindowsSoundCardAdapter < stimgen.calibration.HwAdapter
    % adapter = stimgen.calibration.WindowsSoundCardAdapter()
    % adapter = stimgen.calibration.WindowsSoundCardAdapter(Name=Value)
    % Audio Toolbox-backed calibration adapter for Windows sound devices.
    %
    % Provides blocking duplex playback/recording using audioPlayerRecorder,
    % returning a mono microphone response sized to match the requested
    % excitation vector.
    %
    % Parameters (Name=Value):
    %   SampleRate      - (1,1) double sample rate in Hz.
    %   Device          - (1,1) string device name. Empty uses system default.
    %   SamplesPerFrame - (1,1) double frame size for streaming I/O.
    %   InputChannel    - (1,1) double channel index to extract from recording.
    %
    % Example:
    %   a = stimgen.calibration.WindowsSoundCardAdapter(SampleRate=48000);
    %   eng = stimgen.calibration.Engine(a);
    %
    % See also: audioPlayerRecorder, stimgen.calibration.HwAdapter,
    %           stimgen.calibration.Engine

    properties (Access = private)
        Fs_ (1,1) double
        Device_ (1,1) string
        SamplesPerFrame_ (1,1) double
        InputChannel_ (1,1) double
        Apr_
    end

    methods
        function obj = WindowsSoundCardAdapter(options)
            % obj = stimgen.calibration.WindowsSoundCardAdapter()
            % obj = stimgen.calibration.WindowsSoundCardAdapter(Name=Value)
            % Construct adapter and validate duplex audio capability.
            arguments
                options.SampleRate (1,1) double {mustBePositive,mustBeFinite} = 48000
                options.Device (1,1) string = ""
                options.SamplesPerFrame (1,1) double {mustBeInteger,mustBePositive,mustBeFinite} = 1024
                options.InputChannel (1,1) double {mustBeInteger,mustBePositive,mustBeFinite} = 1
            end

            obj.Fs_ = options.SampleRate;
            obj.Device_ = options.Device;
            obj.SamplesPerFrame_ = options.SamplesPerFrame;
            obj.InputChannel_ = options.InputChannel;

            obj.Apr_ = obj.create_device_();
            obj.validate_stream_();
        end

        function delete(obj)
            % delete(obj)
            % Release audio resources.
            if isempty(obj.Apr_)
                return
            end
            try
                release(obj.Apr_);
            catch
                % Ignore release failures during object teardown.
            end
        end

        function Fs = sample_rate(obj)
            % Fs = sample_rate(obj)
            % Return the configured sound-card sample rate in Hz.
            Fs = obj.Fs_;
        end

        function response = play_and_record(obj, signal)
            % response = play_and_record(obj, signal)
            % Play a mono excitation waveform and record the microphone response.
            %
            % Parameters:
            %   signal   - (1,:) double excitation waveform.
            %
            % Returns:
            %   response - (1,:) double microphone signal.
            arguments
                obj
                signal (1,:) double {mustBeReal,mustBeFinite}
            end

            if isempty(signal)
                response = signal;
                return
            end

            playSignal = max(min(signal(:), 1), -1);
            nsamps = numel(playSignal);
            rec = zeros(nsamps, 1);

            k = 1;
            while k <= nsamps
                i2 = min(k + obj.SamplesPerFrame_ - 1, nsamps);
                frameLen = i2 - k + 1;

                outFrame = zeros(obj.SamplesPerFrame_, 1);
                outFrame(1:frameLen) = playSignal(k:i2);

                try
                    inFrame = obj.Apr_(outFrame);
                catch ME
                    error('stimgen:calibration:WindowsSoundCardAdapter:streamFailure', ...
                        'Audio stream failed during play_and_record: %s', ME.message);
                end

                if size(inFrame, 2) < obj.InputChannel_
                    error('stimgen:calibration:WindowsSoundCardAdapter:badInputChannel', ...
                        'Configured InputChannel (%d) exceeds available input channels (%d).', ...
                        obj.InputChannel_, size(inFrame, 2));
                end

                rec(k:i2) = inFrame(1:frameLen, obj.InputChannel_);
                k = i2 + 1;
            end

            if any(~isfinite(rec))
                error('stimgen:calibration:WindowsSoundCardAdapter:nonFiniteData', ...
                    'Recorded response contains non-finite values. Check device configuration.');
            end

            response = rec.';
        end
    end

    methods (Access = private)
        function apr = create_device_(obj)
            % Create and return the underlying audioPlayerRecorder object.
            try
                if strlength(strtrim(obj.Device_)) == 0
                    apr = audioPlayerRecorder(SampleRate=obj.Fs_);
                else
                    apr = audioPlayerRecorder(SampleRate=obj.Fs_, Device=char(obj.Device_));
                end
            catch ME
                error('stimgen:calibration:WindowsSoundCardAdapter:initFailed', ...
                    'Could not initialize audio device: %s', ME.message);
            end

            if apr.SampleRate ~= obj.Fs_
                release(apr);
                error('stimgen:calibration:WindowsSoundCardAdapter:sampleRateMismatch', ...
                    'Requested SampleRate %.3f Hz but device reports %.3f Hz.', ...
                    obj.Fs_, apr.SampleRate);
            end
        end

        function validate_stream_(obj)
            % Run a short dry pass to verify duplex I/O and channel selection.
            testOut = zeros(obj.SamplesPerFrame_, 1);
            try
                testIn = obj.Apr_(testOut);
            catch ME
                release(obj.Apr_);
                error('stimgen:calibration:WindowsSoundCardAdapter:duplexUnavailable', ...
                    'Duplex playback/recording test failed: %s', ME.message);
            end

            if isempty(testIn)
                release(obj.Apr_);
                error('stimgen:calibration:WindowsSoundCardAdapter:noInputData', ...
                    'Audio device returned empty recorded data during validation.');
            end

            if size(testIn, 2) < obj.InputChannel_
                release(obj.Apr_);
                error('stimgen:calibration:WindowsSoundCardAdapter:badInputChannel', ...
                    'Configured InputChannel (%d) exceeds available input channels (%d).', ...
                    obj.InputChannel_, size(testIn, 2));
            end
        end
    end
end
