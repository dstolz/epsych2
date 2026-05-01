classdef StimPlayer < handle

    % obj = stimgen.StimPlayer
    % obj = stimgen.StimPlayer(RUNTIME)
    % Standalone stimulus bank and playback peripheral for EPsych.
    %
    % Manages a named bank of stimgen.StimPlay objects, schedules them
    % using a serial or shuffle strategy at a configurable global ISI,
    % uploads audio buffers to hardware via epsych.Runtime, and triggers
    % playback from its own timer (independent of PsychTimer).
    %
    % When RUNTIME is not provided or the required hardware parameters are
    % not found, hardware playback is disabled and only speaker preview is
    % available via Play Stim.
    %
    % Required hw.Parameter names (resolved from RUNTIME at Run time):
    %   BufferData_0, BufferData_1   - audio data buffers
    %   BufferSize_0, BufferSize_1   - buffer length in samples
    %   x_Trigger_0, x_Trigger_1    - playback trigger pulses
    %
    % Usage:
    %   sp = stimgen.StimPlayer;           % GUI only, speaker preview
    %   sp = stimgen.StimPlayer(RUNTIME);  % with hardware
    %   sp.RUNTIME = RUNTIME;              % attach later
    %
    % Properties (selected):
    %   StimPlayObjs  - Bank of stimgen.StimPlay objects
    %   RUNTIME       - Optional epsych.Runtime for hardware access
    %   ISI           - Global ISI range [min max] in seconds
    %   SelectionType - "Serial" or "Shuffle"

    % --- External method declarations ---
    methods
        create(obj)
        add_stim(obj, src, event)
        remove_stim(obj, src, event)
        on_bank_selection_changed(obj, src, event)
        update_signal_plot(obj)
        playback_control(obj, src, event)
        timer_startfcn(obj, src, event)
        timer_runtimefcn(obj, src, event)
        timer_stopfcn(obj, src, event)
        update_buffer(obj)
        trigger_stim_playback(obj)
        play_preview(obj, src, event)
        save_bank(obj, ffn)
        load_bank(obj, ffn)
    end

    % --- Public properties ---
    properties
        StimPlayObjs (:,1) stimgen.StimPlay   % Bank of stimulus playback objects

        ISI (1,2) double {mustBePositive,mustBeFinite} = [1.0 1.0] % Global ISI range [min max] in seconds

        SelectionType (1,1) string {mustBeMember(SelectionType,["Serial","Shuffle"])} = "Shuffle" % Playback order

        DataPath (1,1) string = string(fullfile('C:\Users', getenv('USERNAME'))) % Default save path
    end

    properties (SetObservable)
        RUNTIME % Optional epsych.Runtime; attach for hardware buffer/trigger access
    end

    % --- Protected runtime state ---
    properties (SetAccess = protected, SetObservable)
        Timer                                          % MATLAB timer object
        TrigBufferID (1,1) double = 0                  % Alternates 0/1 for double-buffering
        firstTrigTime (1,1) double = 0                 % Absolute time at first trigger
        lastTrigTime (1,1) double = 0                  % Absolute time at last trigger
        currentISI (1,1) double = 1                    % Current ISI value (drawn from ISI range)
        nextSPOIdx (1,1) double = 1                    % Index of next StimPlayObj to present
        trialCount_ (1,1) double = 0                   % Internal trial counter for TrigBufferID

        StimOrder (:,1) double = double.empty(0,1)     % Presentation log: index into StimPlayObjs
        StimOrderTime (:,1) double = double.empty(0,1) % Presentation log: time since start (s)
    end

    % --- Private ---
    properties (Access = private)
        PARAMS struct = struct()   % Cached hw.Parameter handles keyed by validName
        els                        % Event listeners
        hFig                       % uifigure handle
        handles struct = struct()  % UI component handles
    end

    % --- Constants for tab grouping ---
    properties (Constant, Access = private)
        LEVEL_PROPS  = {'SoundLevel'}                              % Properties on Level tab
        TIMING_PROPS = {'Duration','WindowDuration','ApplyWindow'} % Properties on Timing tab
    end

    % --- Dependent ---
    properties (Dependent)
        CurrentSPObj          % stimgen.StimPlay currently selected for playback
        HardwareAvailable     % true if RUNTIME has the required buffer/trigger parameters
        timeSinceStart        % Elapsed seconds since firstTrigTime
    end

    % =====================================================================
    methods

        function obj = StimPlayer(RUNTIME)
            % obj = stimgen.StimPlayer
            % obj = stimgen.StimPlayer(RUNTIME)
            % Construct StimPlayer, optionally attaching an epsych.Runtime.
            %
            % Parameters:
            %   RUNTIME - epsych.Runtime instance (optional)

            if nargin > 0 && ~isempty(RUNTIME)
                obj.RUNTIME = RUNTIME;
            end

            obj.create;

            if nargout == 0, clear obj; end
        end

        % -----------------------------------------------------------------
        function delete(obj)
            % Destructor: stop and clean up timer and listeners.
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
                delete(obj.Timer);
            end
            if ~isempty(obj.els)
                delete(obj.els);
            end
        end

        % -----------------------------------------------------------------
        function sp = get.CurrentSPObj(obj)
            if isempty(obj.StimPlayObjs) || obj.nextSPOIdx < 1
                sp = [];
                return
            end
            sp = obj.StimPlayObjs(min(obj.nextSPOIdx, numel(obj.StimPlayObjs)));
        end

        % -----------------------------------------------------------------
        function tf = get.HardwareAvailable(obj)
            tf = false;
            if isempty(obj.RUNTIME) || ~isvalid(obj.RUNTIME)
                return
            end
            required = {'BufferData_0','BufferData_1','BufferSize_0','BufferSize_1', ...
                        'x_Trigger_0','x_Trigger_1'};
            tf = all(isfield(obj.PARAMS, required));
        end

        % -----------------------------------------------------------------
        function s = get.timeSinceStart(obj)
            a = (now - 719529) * 86400;
            b = (obj.firstTrigTime - 719529) * 86400;
            s = a - b;
        end

        % -----------------------------------------------------------------
        function idx = select_next_idx(obj)
            % select_next_idx() - Pick the next bank index using SerialType scheduling.
            % Returns -1 when all bank items have reached their rep target.
            %
            % Returns:
            %   idx - index into StimPlayObjs, or -1 if session complete

            if isempty(obj.StimPlayObjs)
                idx = -1;
                return
            end

            presented = arrayfun(@(sp) sp.StimPresented, obj.StimPlayObjs);
            totals    = arrayfun(@(sp) sp.StimTotal,     obj.StimPlayObjs);
            remaining = totals - presented;

            if all(remaining <= 0)
                idx = -1;
                return
            end

            candidates = find(remaining > 0);

            switch obj.SelectionType
                case "Serial"
                    idx = candidates(1);
                case "Shuffle"
                    idx = candidates(randperm(numel(candidates), 1));
            end
        end

        % -----------------------------------------------------------------
        function resolve_params_(obj)
            % resolve_params_() - Populate PARAMS from RUNTIME.find_parameter.
            % Called at Run time. Silently skips missing parameters.
            obj.PARAMS = struct;
            if isempty(obj.RUNTIME) || ~isvalid(obj.RUNTIME)
                return
            end
            names = {'BufferData_0','BufferData_1','BufferSize_0','BufferSize_1', ...
                     'x_Trigger_0','x_Trigger_1'};
            for k = 1:numel(names)
                P = obj.RUNTIME.find_parameter(names{k}, silenceParameterNotFound=true);
                if ~isempty(P)
                    obj.PARAMS.(names{k}) = P;
                end
            end
        end

        % -----------------------------------------------------------------
        function get_isi_(obj)
            % get_isi_() - Sample a scalar ISI from obj.ISI range.
            % Updates obj.currentISI.
            lo = obj.ISI(1);
            hi = obj.ISI(2);
            if hi > lo
                obj.currentISI = lo + rand * (hi - lo);
            else
                obj.currentISI = lo;
            end
        end

        % -----------------------------------------------------------------
        function update_counter_(obj)
            % update_counter_() - Refresh the stimulus counter label in the GUI.
            h = obj.handles;
            if ~isfield(h,'Counter') || ~isvalid(h.Counter)
                return
            end
            if isempty(obj.StimPlayObjs)
                h.Counter.Text = '0 / 0';
                return
            end
            presented = sum(arrayfun(@(sp) sp.StimPresented, obj.StimPlayObjs));
            total     = sum(arrayfun(@(sp) sp.StimTotal,     obj.StimPlayObjs));
            h.Counter.Text = sprintf('%d / %d', presented, total);
        end

        % -----------------------------------------------------------------
        function refresh_listbox_(obj)
            % refresh_listbox_() - Rebuild listbox items from current StimPlayObjs.
            h = obj.handles;
            if ~isfield(h,'BankList') || ~isvalid(h.BankList)
                return
            end
            if isempty(obj.StimPlayObjs)
                h.BankList.Items = {};
                h.BankList.ItemsData = {};
                return
            end
            items = arrayfun(@(sp) sprintf('%s  [%s]', char(sp.Name), sp.Type), ...
                obj.StimPlayObjs, 'uni', false);
            h.BankList.Items = items;
            h.BankList.ItemsData = num2cell(1:numel(obj.StimPlayObjs));
        end

    end % methods (public)

end
