classdef InterfaceAdapter < stimgen.calibration.HwAdapter
    % stimbridge.InterfaceAdapter(hwInterface)
    % stimbridge.InterfaceAdapter(hwInterface, Fs=value)
    %
    % Concrete calibration adapter wrapping an hw.Interface instance.
    %
    % This is the EPsych side of the stimgen bridge: it implements the
    % abstract stimgen.calibration.HwAdapter contract in terms of EPsych's
    % hw.* types, which stimgen itself does not know about. It lives here
    % rather than in stimgen so the stimgen package stays hardware-agnostic
    % and usable standalone.
    %
    % Resolves the five required hw.Parameter handles at construction time and
    % errors immediately if any are absent. The hw.Interface must expose:
    %
    %   BufferSize   - Integer, Write  - number of samples to play/record
    %   BufferOut    - Buffer,  Write  - output waveform data
    %   !Trigger     - Boolean, Write  - start pulse (1 → 0); the tag may also
    %                                    be named x_Trigger (see the template)
    %   BufferIndex  - Integer, Read   - acquisition progress counter
    %   BufferIn     - Buffer,  Read   - recorded microphone signal
    %
    % The sample rate is discovered from the first hw.Module whose Fs > 0.
    % Supply the optional Fs argument to override discovery.
    %
    % Parameters:
    %   hwInterface - (1,1) hw.Interface connected to calibration hardware
    %   Fs          - (optional) double sample rate in Hz; overrides Module.Fs
    %
    % Example:
    %   adapter = stimbridge.InterfaceAdapter(RUNTIME.HW);
    %   adapter = stimbridge.InterfaceAdapter(RUNTIME.HW, Fs=97656.25);
    %
    % See also: stimbridge.RuntimeHost, stimgen.calibration.HwAdapter,
    %           stimgen.calibration.Engine,
    %           https://github.com/dstolz/stimgen/blob/main/documentation/stimgen_calibration.md

    properties (SetAccess = private)
        HW  % hw.Interface instance
    end

    properties (Access = private)
        pBufferSize_   % hw.Parameter handle
        pBufferOut_    % hw.Parameter handle
        pTrigger_      % hw.Parameter handle
        pBufferIndex_  % hw.Parameter handle
        pBufferIn_     % hw.Parameter handle
        Fs_    (1,1) double
        pollInterval_  (1,1) double = 0.01  % seconds between BufferIndex polls
    end

    properties (Constant, Access = private)
        % Buffer/index tags that must be present verbatim.
        REQUIRED_PARAMS_ = {'BufferSize','BufferOut','BufferIndex','BufferIn'}

        % Accepted names for the acquisition start trigger, in priority order.
        % '!Trigger' is the standard EPsych/RPvds SoftTrg convention (the
        % ep_MatlabTrigger macro used by examples/stimgen/StimGenCalibration.rcx);
        % 'x_Trigger'
        % is the plain-tag convention in tmp/Calibration_TDT_RPcox_Template.json.
        TRIGGER_CANDIDATES_ = {'!Trigger','x_Trigger'}
    end

    methods
        function obj = InterfaceAdapter(hwInterface, options)
            % obj = InterfaceAdapter(hwInterface)
            % obj = InterfaceAdapter(hwInterface, Fs=value)
            arguments
                hwInterface (1,1) hw.Interface
                options.Fs  (1,1) double = 0
            end
            obj.HW  = hwInterface;
            obj.Fs_ = options.Fs;
            obj.validate_capabilities_();
        end

        function Fs = sample_rate(obj)
            % Fs = obj.sample_rate()
            % Return hardware sample rate in Hz.
            Fs = obj.Fs_;
        end

        function response = play_and_record(obj, signal)
            % response = obj.play_and_record(signal)
            % Write signal to the hardware output buffer, fire the trigger,
            % wait for acquisition to complete, and return the recorded signal.
            %
            % Parameters:
            %   signal   - (1,:) double scaled excitation waveform
            %
            % Returns:
            %   response - (1,:) double microphone response, same length as signal
            nsamps = numel(signal);
            obj.pBufferSize_.Value = nsamps;
            obj.pBufferOut_.Value  = signal(:)';

            obj.pTrigger_.Value = 1;
            pause(0.001);
            obj.pTrigger_.Value = 0;

            obj.poll_until_done_(nsamps);

            raw      = obj.pBufferIn_.Value;
            response = raw(1:nsamps);
        end
    end

    methods (Access = private)
        function validate_capabilities_(obj)
            % Resolve and cache required hw.Parameter handles.
            % Errors immediately if any required parameter is missing.
            required = obj.REQUIRED_PARAMS_;
            for k = 1:numel(required)
                name = required{k};
                p = obj.HW.find_parameter(name, silenceParameterNotFound=true);
                if isempty(p)
                    error('stimbridge:InterfaceAdapter:missingParameter', ...
                        ['Required calibration parameter "%s" not found on ' ...
                        'hw.Interface "%s". Verify the hardware circuit exposes ' ...
                        'this tag and try reconnecting.'], name, class(obj.HW));
                end
            end

            obj.pBufferSize_  = obj.HW.find_parameter('BufferSize');
            obj.pBufferOut_   = obj.HW.find_parameter('BufferOut');
            obj.pBufferIndex_ = obj.HW.find_parameter('BufferIndex');
            obj.pBufferIn_    = obj.HW.find_parameter('BufferIn');
            obj.pTrigger_     = obj.resolve_trigger_();

            % Discover Fs from the first module that reports a non-zero rate.
            if obj.Fs_ == 0
                mods = obj.HW.Module;
                for i = 1:numel(mods)
                    if mods(i).Fs > 0
                        obj.Fs_ = mods(i).Fs;
                        break;
                    end
                end
            end

            if obj.Fs_ == 0
                error('stimbridge:InterfaceAdapter:noSampleRate', ...
                    ['Cannot determine sample rate from hw.Interface "%s". ' ...
                    'Ensure hw.Module.Fs is set during setup_interface, or ' ...
                    'supply the Fs argument explicitly.'], class(obj.HW));
            end
        end

        function p = resolve_trigger_(obj)
            % Return the acquisition start-trigger handle, accepting any of the
            % names in TRIGGER_CANDIDATES_ (first match wins). Errors if none
            % is present.
            candidates = obj.TRIGGER_CANDIDATES_;
            for k = 1:numel(candidates)
                p = obj.HW.find_parameter(candidates{k}, silenceParameterNotFound=true);
                if ~isempty(p)
                    return
                end
            end
            error('stimbridge:InterfaceAdapter:missingParameter', ...
                ['No acquisition trigger found on hw.Interface "%s". Expose a ' ...
                'writable trigger tag named one of: %s.'], ...
                class(obj.HW), strjoin(candidates, ', '));
        end

        function poll_until_done_(obj, nsamps)
            % Block until BufferIndex reaches nsamps or the timeout expires.
            timeout = nsamps / obj.Fs_ + 1;  % 1 s margin past expected duration
            t       = tic;
            bidx    = obj.pBufferIndex_.Value;
            while toc(t) < timeout
                if bidx >= nsamps
                    break;
                end
                pause(obj.pollInterval_);
                bidx = obj.pBufferIndex_.Value;
            end
            vprintf(3, 'InterfaceAdapter.poll_until_done_: BufferIndex=%d nsamps=%d', bidx, nsamps);
        end
    end
end
