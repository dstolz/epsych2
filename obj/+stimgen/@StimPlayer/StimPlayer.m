classdef StimPlayer < handle

    % obj = stimgen.StimPlayer
    % obj = stimgen.StimPlayer(HOST)
    % Standalone stimulus bank and playback peripheral.
    %
    % Developer guide: documentation/stimgen/stimgen_StimPlayer.md
    %
    % Manages a named bank of stimgen.StimPlay objects, schedules them
    % using a serial or shuffle strategy at a configurable global ISI,
    % uploads audio buffers to hardware via a stimgen.HardwareHost, and
    % triggers playback from its own timer (independent of PsychTimer).
    %
    % When a host is not provided or required hardware parameters are not
    % found, hardware playback is disabled and only speaker preview is
    % available via Play and Play All.
    %
    % Required parameter names (resolved from the host at Run time):
    %   BufferData_0, BufferData_1   - audio data buffers
    %   BufferSize_0, BufferSize_1   - buffer length in samples
    %   x_Trigger_0, x_Trigger_1    - playback trigger pulses
    %
    % Usage:
    %   sp = stimgen.StimPlayer;       % GUI only, speaker preview
    %   sp = stimgen.StimPlayer(HOST); % with host-provided hardware
    %
    % Properties (selected):
    %   StimPlayObjs  - Bank of stimgen.StimPlay objects
    %   Host          - Optional stimgen.HardwareHost for hardware playback
    %   ISI           - Global ISI range [min max] in seconds
    %   SelectionType - "Serial" or "Shuffle"

    % --- External method declarations ---
    methods
        create(obj)
        open_stim(obj, stimObj, varargin)
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
        play_all(obj, src, event)
        step_combination(obj, step)
        open_calibration_gui(obj)
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
        Host                       % stimgen.HardwareHost | [] ([] = offline preview only)
        PARAMS struct = struct()   % Cached parameter handles keyed by validName
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
        HardwareAvailable     % true if the host exposes the required buffer/trigger parameters
        timeSinceStart        % Elapsed seconds since firstTrigTime
    end

    % =====================================================================
    methods

        function obj = StimPlayer(host)
            % obj = stimgen.StimPlayer
            % obj = stimgen.StimPlayer(host)
            % Construct StimPlayer, optionally attached to a hardware host.
            %
            % Parameters:
            %   host - stimgen.HardwareHost providing protocol and hardware
            %          access (optional; omit for offline speaker preview)

            obj.create;

            if nargin > 0 && ~isempty(host)
                mustBeA(host, 'stimgen.HardwareHost');
                obj.Host = host;
            end
            obj.update_protocol_status_;

            if nargout == 0, clear obj; end
        end

        % -----------------------------------------------------------------
        function delete(obj)
            % Destructor: stop and clean up timer and listeners.
            obj.disconnect_interfaces_;
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
            if isempty(obj.Host) || obj.Host.connectionState() == "None"
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
            % resolve_params_() - Populate PARAMS from the host.
            % Called at Run time. Silently skips missing parameters.
            obj.PARAMS = struct;
            if isempty(obj.Host)
                return
            end
            names = {'BufferData_0','BufferData_1','BufferSize_0','BufferSize_1', ...
                     'x_Trigger_0','x_Trigger_1'};
            for k = 1:numel(names)
                P = obj.Host.findParameter(names{k});
                if ~isempty(P)
                    obj.PARAMS.(names{k}) = P;
                end
            end
        end

        % -----------------------------------------------------------------
        function load_protocol_(obj, protocolInput)
            % load_protocol_(obj) - Prompt for a protocol file and load it.
            % load_protocol_(obj, protocolInput) - Load a protocol object or file.
            % Protocol handling is delegated entirely to the attached host.

            if ~isempty(obj.Timer) && isvalid(obj.Timer) && strcmp(obj.Timer.Running, 'on')
                obj.show_gui_message_("Stop playback before loading a new protocol.", ...
                    "Protocol In Use", "warning");
                return
            end

            if isempty(obj.Host)
                obj.show_gui_message_("No hardware host is attached; speaker preview only.", ...
                    "No Hardware Host", "warning");
                return
            end

            if nargin < 2 || isempty(protocolInput)
                [fn, pn] = uigetfile({'*.eprot;*.prot;*.json', 'Protocol files (*.eprot,*.prot,*.json)'}, ...
                    'Load Protocol', obj.DataPath);
                if isequal(fn, 0)
                    return
                end
                protocolInput = fullfile(pn, fn);
            end

            obj.disconnect_interfaces_;

            try
                obj.Host.loadProtocol(protocolInput);

                % Track the containing folder so later file dialogs open there.
                if (ischar(protocolInput) || isstring(protocolInput)) && isfile(protocolInput)
                    obj.DataPath = string(fileparts(char(protocolInput)));
                end

                obj.set_status_("Protocol loaded.");
            catch ME
                obj.report_gui_error_(ME, "Load Protocol Error", ...
                    "StimPlayer could not load the selected protocol.");
            end

            obj.update_protocol_status_;
        end

        % -----------------------------------------------------------------
        function initialize_runtime_from_protocol_(obj)
            % initialize_runtime_from_protocol_() - Connect host hardware for playback.

            obj.disconnect_interfaces_;

            if isempty(obj.Host) || ~obj.Host.hasProtocol()
                return
            end

            obj.Host.connect();
            obj.Host.setMode("Preview");
        end

        % -----------------------------------------------------------------
        function disconnect_interfaces_(obj)
            % disconnect_interfaces_() - Return hardware to Idle and clear parameter cache.

            obj.PARAMS = struct();

            if isempty(obj.Host) || obj.Host.connectionState() == "None"
                return
            end

            try
                obj.Host.setMode("Idle");
            catch ME
                stimgen.util.vprintf(0, 1, 'StimPlayer: failed to return interface mode to Idle.');
                stimgen.util.vprintf(0, 1, ME);
            end

            obj.Host.release();
        end

        % -----------------------------------------------------------------
        function lock_bank_controls_(obj, lockState)
            % lock_bank_controls_(obj, lockState) - Enable/disable bank-editing controls.

            h = obj.handles;
            targetState = 'on';
            if lockState
                targetState = 'off';
            end

            fields = {'AddBtn','RemoveBtn','TypeDropdown','BankList','RepsField', ...
                'ISIField','OrderDD','ComboPrevBtn','ComboNextBtn','LoadProtocolMenu', ...
                'LoadBankMenu','SaveBankMenu','CalibrationMenu','CalibrationGuiMenu'};
            for i = 1:numel(fields)
                f = fields{i};
                if isfield(h, f) && ~isempty(h.(f)) && isvalid(h.(f))
                    h.(f).Enable = targetState;
                end
            end

            if isfield(h, 'ParamPanel') && ~isempty(h.ParamPanel) && isvalid(h.ParamPanel)
                children = findall(h.ParamPanel);
                for i = 1:numel(children)
                    if isprop(children(i), 'Enable')
                        children(i).Enable = targetState;
                    end
                end
            end
        end

        % -----------------------------------------------------------------
        function update_protocol_status_(obj)
            % update_protocol_status_() - Refresh protocol/hardware status label.

            h = obj.handles;
            if ~isfield(h, 'ProtocolStatusLabel') || isempty(h.ProtocolStatusLabel) || ~isvalid(h.ProtocolStatusLabel)
                return
            end

            if isempty(obj.Host) || ~obj.Host.hasProtocol()
                h.ProtocolStatusLabel.Text = 'Protocol: none | HW: speaker preview only';
                return
            end

            switch obj.Host.connectionState()
                case "Ready",    hwState = "Ready";
                case "Partial",  hwState = "Partial";
                otherwise,       hwState = "Not Connected";
            end

            h.ProtocolStatusLabel.Text = sprintf('Protocol: %s | HW: %s', ...
                obj.Host.protocolName(), hwState);
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

        % -----------------------------------------------------------------
        function refresh_combo_controls_(obj)
            % refresh_combo_controls_() - Update combo-step button state and label.
            h = obj.handles;
            required = {'ComboPrevBtn','ComboNextBtn','ComboStatusLbl','BankList'};
            if ~all(isfield(h, required))
                return
            end
            if ~isvalid(h.ComboPrevBtn) || ~isvalid(h.ComboNextBtn) || ...
                    ~isvalid(h.ComboStatusLbl) || ~isvalid(h.BankList)
                return
            end

            idx = [];
            if ~isempty(h.BankList.Value) && h.BankList.Value >= 1 && h.BankList.Value <= numel(obj.StimPlayObjs)
                idx = h.BankList.Value;
            end

            if isempty(idx)
                h.ComboPrevBtn.Enable = 'off';
                h.ComboNextBtn.Enable = 'off';
                h.ComboStatusLbl.Text = 'Combo: - / -';
                return
            end

            stimObj = obj.StimPlayObjs(idx).CurrentStimObj;
            info = stimObj.get_variant_info();

            h.ComboStatusLbl.Text = sprintf('Combo: %d / %d', info.ActiveIndex, info.NumCombinations);
            if info.NumCombinations > 1
                h.ComboPrevBtn.Enable = 'on';
                h.ComboNextBtn.Enable = 'on';
            else
                h.ComboPrevBtn.Enable = 'off';
                h.ComboNextBtn.Enable = 'off';
            end
        end

        % -----------------------------------------------------------------
        function initialize_variants_(obj)
            % initialize_variants_() - Reset all bank items to combination #1.
            for i = 1:numel(obj.StimPlayObjs)
                stimObj = obj.StimPlayObjs(i).CurrentStimObj;
                stimObj.set_variant_index(1);
            end
        end

        % -----------------------------------------------------------------
        function advance_variant_(obj, bankIdx)
            % advance_variant_(obj, bankIdx) - Advance one bank item's variant by +1.
            if bankIdx < 1 || bankIdx > numel(obj.StimPlayObjs)
                return
            end
            stimObj = obj.StimPlayObjs(bankIdx).CurrentStimObj;
            stimObj.step_variant(1);
        end

        % -----------------------------------------------------------------
        function report_gui_error_(obj, ME, titleText, userMessage)
            % report_gui_error_() - Log an exception and show a user-facing alert.
            arguments
                obj (1,1) stimgen.StimPlayer
                ME (1,1) MException
                titleText (1,1) string = "StimPlayer Error"
                userMessage (1,1) string = "An unexpected error occurred."
            end

            stimgen.util.vprintf(0, 1, '%s: %s', char(titleText), ME.message);
            stimgen.util.vprintf(0, 1, ME);

            detailedMessage = obj.format_gui_error_message_(ME, userMessage);
            obj.set_status_(titleText + ": " + detailedMessage, isError=true);

            if isempty(obj.hFig) || ~isvalid(obj.hFig)
                return
            end

            try
                uialert(obj.hFig, char(detailedMessage), ...
                    char(titleText), 'Icon', 'error');
            catch
                % Avoid cascading GUI failures while reporting an error.
            end
        end

        % -----------------------------------------------------------------
        function show_gui_message_(obj, messageText, titleText, iconName)
            % show_gui_message_() - Best-effort wrapper around uialert.
            arguments
                obj (1,1) stimgen.StimPlayer
                messageText (1,1) string
                titleText (1,1) string = "StimPlayer"
                iconName (1,1) string = "info"
            end

            if isempty(obj.hFig) || ~isvalid(obj.hFig)
                return
            end

            obj.set_status_(titleText + ": " + messageText, isError=iconName == "error");

            try
                if any(iconName == ["error", "success"])
                    uialert(obj.hFig, char(messageText), char(titleText), 'Icon', char(iconName));
                end
            catch
                % Ignore alert failures if the figure is closing.
            end
        end

        % -----------------------------------------------------------------
        function set_status_(obj, messageText, options)
            % set_status_() - Update the non-modal status label in the GUI.
            arguments
                obj (1,1) stimgen.StimPlayer
                messageText (1,1) string
                options.isError (1,1) logical = false
            end

            h = obj.handles;
            if ~isfield(h, 'StatusLabel') || isempty(h.StatusLabel) || ~isvalid(h.StatusLabel)
                return
            end

            h.StatusLabel.Text = char(messageText);
            if options.isError
                h.StatusLabel.FontColor = [0.75 0.15 0.15];
            else
                h.StatusLabel.FontColor = [0.35 0.35 0.35];
            end
        end

        % -----------------------------------------------------------------
        function messageText = format_gui_error_message_(obj, ME, fallbackText)
            % format_gui_error_message_() - Convert common errors into user-facing guidance.
            arguments
                obj (1,1) stimgen.StimPlayer
                ME (1,1) MException
                fallbackText (1,1) string
            end

            if isempty(obj)
                messageText = fallbackText + newline + newline + string(ME.message);
                return
            end

            messageText = fallbackText + newline + newline + string(ME.message);

            switch string(ME.identifier)
                case "StimPlayer:InvalidISI"
                    messageText = "Enter either one positive ISI value, such as 1, or a two-value range such as [0.5 1.5].";
                case "StimPlayer:InvalidCalibrationFile"
                    messageText = "The selected calibration file did not contain a usable calibration object.";
                case "stimgen:StimType:NonVectorizableProperty"
                    messageText = "This property must stay scalar in StimPlayer. Use a single value rather than a vector or expression that expands to multiple values.";
                case "stimgen:StimType:PairwiseLengthMismatch"
                    messageText = [ ...
                        "Variant lengths do not match the selected combination mode." + newline + ...
                        "Use equal-length vectors for PairwiseStrict, or use scalar-or-max-length vectors for PairwiseScalarExpand." ...
                    ];
                case "stimgen:StimType:MissingSelectorClass"
                    messageText = "Variant Selection is set to CustomSelector, but no selector class was provided.";
                case "stimgen:StimType:SelectorClassNotFound"
                    messageText = "StimPlayer could not find the requested variant selector class on the MATLAB path.";
                case "stimgen:StimType:SelectorClassType"
                    messageText = "The selected variant selector must define both initialize() and selectNext() methods.";
                case "stimgen:StimType:InvalidSelectorIndex"
                    messageText = "The custom selector returned an invalid variant index for the available combinations.";
                case "stimgen:StimType:InvalidCombinationMode"
                    messageText = "The selected variant combination mode is not recognized.";
                case "stimgen:StimType:InvalidSelectionMode"
                    messageText = "The selected variant selection mode is not recognized.";
                otherwise
                    rawMessage = string(ME.message);
                    if contains(rawMessage, "Expression cannot be empty.")
                        messageText = "Enter a numeric value or MATLAB expression, such as 4000 or 500*2.^(0:3).";
                    elseif contains(rawMessage, "Assignments are not allowed in expressions.")
                        messageText = "Use expressions only. Do not include assignments like Frequency = ....";
                    elseif contains(rawMessage, "Only a single expression is allowed.")
                        messageText = "Enter one expression only. Separate values with spaces or MATLAB vector syntax rather than semicolons.";
                    elseif contains(rawMessage, "must evaluate to a numeric or logical value.")
                        messageText = "That expression did not resolve to numeric values. Try a numeric vector such as [1000 2000 4000] or an expression like 500*2.^(0:3).";
                    elseif contains(rawMessage, "must evaluate to finite numeric values.")
                        messageText = "The expression must evaluate to finite numbers only. Remove NaN, Inf, or divisions by zero.";
                    end
            end
        end

    end % methods (public)

end
