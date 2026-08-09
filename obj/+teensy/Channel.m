classdef Channel
    % obj = teensy.Channel()
    % obj = teensy.Channel(name, Direction=..., Kind=..., Pin=..., ...)
    % Logical binding between a name used in a trial program and a board pin.
    %
    % A Channel is the only place a pin number appears in a teensy.Program.
    % States, conditions and actions refer to channels by Name, so re-wiring a
    % box is a single edit here and nothing else in the program changes.
    %
    % Properties
    %   Name              - Logical name; a MATLAB identifier of at most 23 chars.
    %   Direction         - "Input" or "Output".
    %   Kind              - "Digital" or "Analog".
    %   Pin               - Board pin; -1 means unassigned.
    %   ActiveHigh        - Digital polarity. False means an active-low switch.
    %   DebounceMs        - Digital input debounce window.
    %   PullMode          - "None", "PullUp" or "PullDown"; digital input only.
    %   ThresholdHigh     - Analog input trip level, in Units.
    %   ThresholdLow      - Analog input release level (hysteresis floor).
    %   Units             - Engineering unit label for an analog input.
    %   Scale, Offset     - Counts to units: units = counts*Scale + Offset.
    %   SampleRateHz      - Analog input sample rate.
    %   Oversample        - Analog input samples averaged per reported value.
    %   IdleState         - Digital output level held outside a trial (0 or 1).
    %   AnalogOutMode     - "PWM", "MQS" or "SPI_DAC"; Teensy 4.x has no DAC.
    %   PwmFrequencyHz    - PWM carrier frequency.
    %   PwmResolutionBits - PWM duty resolution.
    %   Notes             - Free text shown in the channel table.
    %
    % Methods
    %   describe    - One-line human summary.
    %   validate    - Check the channel against a board profile.
    %   toStruct    - Serialize to a plain struct.
    %   digitalIn   - (static) Build a debounced digital input.
    %   digitalOut  - (static) Build a digital output.
    %   analogIn    - (static) Build a thresholded analog input.
    %   analogOut   - (static) Build a PWM/MQS/SPI_DAC analog output.
    %   defaultSet  - (static) Starter channel set for an operant box.
    %   fromStruct  - (static) Rebuild from a struct written by toStruct.
    %
    % Example
    %   ch = teensy.Channel.digitalIn("Poke", 2, PullMode="PullUp", ActiveHigh=false);
    %   iss = ch.validate(teensy.BoardProfile.teensy41());
    %
    % See also: teensy.BoardProfile, teensy.Condition, teensy.Action

    properties
        Name (1,1) string = ""

        Direction (1,1) string {mustBeMember(Direction, ["Input","Output"])} = "Input"

        Kind (1,1) string {mustBeMember(Kind, ["Digital","Analog"])} = "Digital"

        % -1 marks an unassigned pin; 0 is a real Teensy pin, so it cannot be
        % used as the sentinel.
        Pin (1,1) double = -1

        ActiveHigh (1,1) logical = true

        DebounceMs (1,1) double {mustBeNonnegative} = 5

        PullMode (1,1) string {mustBeMember(PullMode, ["None","PullUp","PullDown"])} = "None"

        ThresholdHigh (1,1) double = 2.5

        ThresholdLow (1,1) double = 2.0

        Units (1,1) string = "V"

        Scale (1,1) double = 1

        Offset (1,1) double = 0

        SampleRateHz (1,1) double = 1000

        Oversample (1,1) double = 1

        IdleState (1,1) double {mustBeMember(IdleState, [0 1])} = 0

        AnalogOutMode (1,1) string {mustBeMember(AnalogOutMode, ["PWM","MQS","SPI_DAC"])} = "PWM"

        PwmFrequencyHz (1,1) double {mustBePositive} = 1000

        PwmResolutionBits (1,1) double {mustBeInteger, mustBePositive} = 12

        Notes (1,1) string = ""
    end

    methods
        function obj = Channel(name, options)
            % obj = teensy.Channel(name, Name=Value)
            % Construct a channel. Every argument is optional so the class works
            % as an array element and as ClassName.empty.
            %
            % Parameters
            %   name    - Logical channel name.
            %   Name=Value - Any property may be set by name.
            %
            % Returns
            %   obj - Configured teensy.Channel.
            arguments
                name (1,1) string = ""
                options.Direction (1,1) string {mustBeMember(options.Direction, ["Input","Output"])}
                options.Kind (1,1) string {mustBeMember(options.Kind, ["Digital","Analog"])}
                options.Pin (1,1) double
                options.ActiveHigh (1,1) logical
                options.DebounceMs (1,1) double {mustBeNonnegative}
                options.PullMode (1,1) string {mustBeMember(options.PullMode, ["None","PullUp","PullDown"])}
                options.ThresholdHigh (1,1) double
                options.ThresholdLow (1,1) double
                options.Units (1,1) string
                options.Scale (1,1) double
                options.Offset (1,1) double
                options.SampleRateHz (1,1) double
                options.Oversample (1,1) double
                options.IdleState (1,1) double {mustBeMember(options.IdleState, [0 1])}
                options.AnalogOutMode (1,1) string {mustBeMember(options.AnalogOutMode, ["PWM","MQS","SPI_DAC"])}
                options.PwmFrequencyHz (1,1) double {mustBePositive}
                options.PwmResolutionBits (1,1) double {mustBeInteger, mustBePositive}
                options.Notes (1,1) string
            end

            obj.Name = name;

            fn = fieldnames(options);
            for i = 1:numel(fn)
                obj.(fn{i}) = options.(fn{i});
            end
        end

        function s = describe(obj)
            % s = obj.describe()
            % Return a one-line summary for the channel table or a tooltip.
            %
            % Returns
            %   s - Scalar string, e.g.
            %       "Poke: digital in on pin 2 (active low, pull-up, 5 ms debounce)".
            arguments
                obj (1,1) teensy.Channel
            end

            if obj.Pin < 0
                pinText = "unassigned pin";
            else
                pinText = "pin " + string(obj.Pin);
            end

            switch obj.Kind + "/" + obj.Direction
                case "Digital/Input"
                    detail = polarityWord_(obj.ActiveHigh);
                    if obj.PullMode ~= "None"
                        detail = detail + ", " + pullWord_(obj.PullMode);
                    end
                    if obj.DebounceMs > 0
                        detail = detail + sprintf(", %g ms debounce", obj.DebounceMs);
                    end
                    s = sprintf("%s: digital in on %s (%s)", obj.Name, pinText, detail);

                case "Digital/Output"
                    s = sprintf("%s: digital out on %s (%s, idle %s)", obj.Name, pinText, ...
                        polarityWord_(obj.ActiveHigh), levelWord_(obj.IdleState));

                case "Analog/Input"
                    label = "";
                    if obj.Pin >= 0
                        label = teensy.BoardProfile().analogLabel(obj.Pin);
                    end
                    if strlength(label) > 0
                        pinText = pinText + " (" + label + ")";
                    end
                    s = sprintf("%s: analog in on %s, trip %g/%g %s at %g Hz", ...
                        obj.Name, pinText, obj.ThresholdHigh, obj.ThresholdLow, ...
                        obj.Units, obj.SampleRateHz);

                otherwise
                    if obj.AnalogOutMode == "PWM"
                        mode = sprintf("PWM %g Hz, %d bits", obj.PwmFrequencyHz, obj.PwmResolutionBits);
                    else
                        mode = obj.AnalogOutMode;
                    end
                    s = sprintf("%s: analog out on %s (%s)", obj.Name, pinText, mode);
            end
        end

        function iss = validate(obj, context, options)
            % iss = obj.validate()
            % iss = obj.validate(boardProfile)
            % iss = obj.validate(program, Where=where)
            % Check this channel against a board's pin capabilities.
            %
            % Parameters
            %   context - A teensy.BoardProfile, or a teensy.Program whose Board
            %       is used. Defaults to the Teensy 4.1 profile.
            %   Where   - Location text carried into every issue. Defaults to
            %       "Channel '<Name>'".
            %
            % Returns
            %   iss - 1xN issue struct array; see teensy.issue.
            arguments
                obj (1,1) teensy.Channel
                context = teensy.BoardProfile()
                options.Where (1,1) string = ""
            end

            board = resolveBoard_(context);

            where = options.Where;
            if strlength(where) == 0
                where = sprintf("Channel '%s'", obj.Name);
            end

            iss = teensy.issue();

            % --- name -------------------------------------------------------
            if strlength(obj.Name) == 0
                iss(end+1) = teensy.issue("error", "Name", ...
                    "Channel has no name.", Where = where, ...
                    Remedy = "Give the channel a short name such as Poke or Reward.");
            elseif ~isvarname(char(obj.Name))
                iss(end+1) = teensy.issue("error", "Name", ...
                    sprintf("'%s' is not a valid name.", obj.Name), Where = where, ...
                    Remedy = "Use a letter followed by letters, digits or underscores.");
            elseif strlength(obj.Name) > 23
                iss(end+1) = teensy.issue("error", "Name", ...
                    sprintf("'%s' is longer than the 23 character wire limit.", obj.Name), ...
                    Where = where, Remedy = "Shorten the name.");
            end

            % --- pin --------------------------------------------------------
            if obj.Pin < 0
                iss(end+1) = teensy.issue("error", "Pin", ...
                    "No pin assigned.", Where = where, ...
                    Remedy = sprintf("Pick a pin from the %s pinout.", board.Name));
            elseif ~isfinite(obj.Pin) || obj.Pin ~= floor(obj.Pin)
                iss(end+1) = teensy.issue("error", "Pin", ...
                    sprintf("Pin %g is not a whole pin number.", obj.Pin), Where = where, ...
                    Remedy = "Enter an integer pin number.");
            elseif obj.Pin >= board.NumPins
                iss(end+1) = teensy.issue("error", "Pin", ...
                    sprintf("Pin %d does not exist on the %s (0-%d).", ...
                        obj.Pin, board.Name, board.NumPins - 1), Where = where, ...
                    Remedy = "Pick a pin that exists on this board.");
            else
                iss = [iss, obj.validateCapability_(board, where)];

                if board.isReserved(obj.Pin)
                    iss(end+1) = teensy.issue("warning", "Pin", ...
                        sprintf("Pin %d already has an on-board function.", obj.Pin), ...
                        Where = where, ...
                        Remedy = "It still works, but prefer a free pin if one is available.");
                end
            end

            % --- per-kind settings ------------------------------------------
            iss = [iss, obj.validateSettings_(where)];
        end

        function S = toStruct(obj)
            % S = obj.toStruct()
            % Serialize channels to a plain struct array for saving or undo.
            %
            % Returns
            %   S - Struct array shaped like obj with one field per property.
            arguments
                obj teensy.Channel
            end

            S = repmat(templateStruct_(), size(obj));
            for k = 1:numel(obj)
                S(k).Name = obj(k).Name;
                S(k).Direction = obj(k).Direction;
                S(k).Kind = obj(k).Kind;
                S(k).Pin = obj(k).Pin;
                S(k).ActiveHigh = obj(k).ActiveHigh;
                S(k).DebounceMs = obj(k).DebounceMs;
                S(k).PullMode = obj(k).PullMode;
                S(k).ThresholdHigh = obj(k).ThresholdHigh;
                S(k).ThresholdLow = obj(k).ThresholdLow;
                S(k).Units = obj(k).Units;
                S(k).Scale = obj(k).Scale;
                S(k).Offset = obj(k).Offset;
                S(k).SampleRateHz = obj(k).SampleRateHz;
                S(k).Oversample = obj(k).Oversample;
                S(k).IdleState = obj(k).IdleState;
                S(k).AnalogOutMode = obj(k).AnalogOutMode;
                S(k).PwmFrequencyHz = obj(k).PwmFrequencyHz;
                S(k).PwmResolutionBits = obj(k).PwmResolutionBits;
                S(k).Notes = obj(k).Notes;
            end
        end
    end

    methods (Access = private)
        function iss = validateCapability_(obj, board, where)
            % iss = obj.validateCapability_(board, where)
            % Check the assigned pin against the capability the channel needs.
            iss = teensy.issue();

            if obj.Kind == "Digital"
                if ~board.supports("digital", obj.Pin)
                    iss(end+1) = teensy.issue("error", "Pin", ...
                        sprintf("Pin %d cannot be used as a digital pin.", obj.Pin), ...
                        Where = where, Remedy = "Pick a digital-capable pin.");
                end
                return
            end

            if obj.Direction == "Input"
                if ~board.supports("analogIn", obj.Pin)
                    iss(end+1) = teensy.issue("error", "Pin", ...
                        sprintf("Pin %d is not an analog input on the %s.", obj.Pin, board.Name), ...
                        Where = where, ...
                        Remedy = sprintf("Use one of pins %s.", ...
                            strjoin(string(board.AnalogInPins), ", ")));
                end
                return
            end

            switch obj.AnalogOutMode
                case "PWM"
                    if ~board.supports("pwm", obj.Pin)
                        iss(end+1) = teensy.issue("error", "Pin", ...
                            sprintf("Pin %d has no PWM timer on the %s.", obj.Pin, board.Name), ...
                            Where = where, ...
                            Remedy = "Pick a PWM pin, or switch AnalogOutMode to SPI_DAC.");
                    end
                case "MQS"
                    if ~board.supports("mqs", obj.Pin)
                        iss(end+1) = teensy.issue("error", "Pin", ...
                            sprintf("MQS output is only available on pins %s.", ...
                                strjoin(string(board.MqsPins), " and ")), ...
                            Where = where, Remedy = "Move the channel to an MQS pin.");
                    else
                        iss(end+1) = teensy.issue("info", "Analog Out", ...
                            "MQS is a sigma-delta audio output and needs an RC filter.", ...
                            Where = where, ...
                            Remedy = "Filter the pin before it reaches the load.");
                    end
                case "SPI_DAC"
                    iss(end+1) = teensy.issue("info", "Analog Out", ...
                        sprintf("Pin %d is treated as the chip select for an external SPI DAC.", obj.Pin), ...
                        Where = where, ...
                        Remedy = "Confirm the DAC shares the board SPI bus.");
            end
        end

        function iss = validateSettings_(obj, where)
            % iss = obj.validateSettings_(where)
            % Check the settings that only matter for one Kind/Direction pair.
            iss = teensy.issue();

            if obj.Kind == "Digital" && obj.Direction == "Input"
                if obj.DebounceMs > 100
                    iss(end+1) = teensy.issue("warning", "Timing", ...
                        sprintf("A %g ms debounce will hide fast responses.", obj.DebounceMs), ...
                        Where = where, Remedy = "Values of 1-20 ms suit most switches and beams.");
                end
                if obj.ActiveHigh && obj.PullMode == "PullUp"
                    iss(end+1) = teensy.issue("info", "Polarity", ...
                        "An active-high input with a pull-up idles high.", ...
                        Where = where, ...
                        Remedy = "Switches to ground are usually ActiveHigh=false with PullUp.");
                end
            end

            if obj.Kind == "Digital" && obj.Direction == "Output" && obj.PullMode ~= "None"
                iss(end+1) = teensy.issue("info", "Pull", ...
                    "PullMode is ignored on an output.", Where = where, ...
                    Remedy = "Set PullMode to None to avoid confusion.");
            end

            if obj.Kind == "Analog" && obj.Direction == "Input"
                if obj.ThresholdLow > obj.ThresholdHigh
                    iss(end+1) = teensy.issue("error", "Threshold", ...
                        sprintf("ThresholdLow (%g) is above ThresholdHigh (%g).", ...
                            obj.ThresholdLow, obj.ThresholdHigh), Where = where, ...
                        Remedy = "The low threshold is the hysteresis release level.");
                elseif obj.ThresholdLow == obj.ThresholdHigh
                    iss(end+1) = teensy.issue("warning", "Threshold", ...
                        "Equal thresholds leave no hysteresis, so a noisy signal will chatter.", ...
                        Where = where, Remedy = "Separate them by a few percent of full scale.");
                end

                if obj.SampleRateHz <= 0
                    iss(end+1) = teensy.issue("error", "Sampling", ...
                        "SampleRateHz must be positive.", Where = where, ...
                        Remedy = "1000 Hz suits most behavioural sensors.");
                elseif obj.SampleRateHz > 50000
                    iss(end+1) = teensy.issue("warning", "Sampling", ...
                        sprintf("%g Hz on top of the state machine may starve the main loop.", ...
                            obj.SampleRateHz), Where = where, ...
                        Remedy = "Sample no faster than the behaviour requires.");
                end

                if obj.Oversample < 1 || obj.Oversample ~= floor(obj.Oversample)
                    iss(end+1) = teensy.issue("error", "Sampling", ...
                        "Oversample must be a whole number of samples, at least 1.", ...
                        Where = where, Remedy = "Use 1 for no averaging.");
                end

                if obj.Scale == 0
                    iss(end+1) = teensy.issue("warning", "Scaling", ...
                        "A zero Scale makes the channel read a constant.", Where = where, ...
                        Remedy = "Set Scale so that counts*Scale + Offset gives engineering units.");
                end
            end

            if obj.Kind == "Analog" && obj.Direction == "Output" && obj.AnalogOutMode == "PWM"
                if obj.PwmResolutionBits > 16
                    iss(end+1) = teensy.issue("error", "PWM", ...
                        "PWM resolution above 16 bits is not supported.", Where = where, ...
                        Remedy = "Use 8-12 bits.");
                elseif 2^obj.PwmResolutionBits * obj.PwmFrequencyHz > 150e6
                    iss(end+1) = teensy.issue("warning", "PWM", ...
                        sprintf("%d bits at %g Hz exceeds the timer clock, so resolution will be reduced.", ...
                            obj.PwmResolutionBits, obj.PwmFrequencyHz), Where = where, ...
                        Remedy = "Lower the frequency or the resolution.");
                end
            end
        end
    end

    methods (Static)
        function obj = digitalIn(name, pin, options)
            % obj = teensy.Channel.digitalIn(name, pin, Name=Value)
            % Build a debounced digital input channel.
            %
            % Parameters
            %   name - Logical channel name.
            %   pin  - Board pin.
            %   ActiveHigh, DebounceMs, PullMode, Notes - Optional overrides.
            %
            % Returns
            %   obj - teensy.Channel with Direction "Input" and Kind "Digital".
            arguments
                name (1,1) string = ""
                pin (1,1) double = -1
                options.ActiveHigh (1,1) logical = true
                options.DebounceMs (1,1) double {mustBeNonnegative} = 5
                options.PullMode (1,1) string {mustBeMember(options.PullMode, ["None","PullUp","PullDown"])} = "None"
                options.Notes (1,1) string = ""
            end

            obj = teensy.Channel(name, Direction = "Input", Kind = "Digital", Pin = pin, ...
                ActiveHigh = options.ActiveHigh, DebounceMs = options.DebounceMs, ...
                PullMode = options.PullMode, Notes = options.Notes);
        end

        function obj = digitalOut(name, pin, options)
            % obj = teensy.Channel.digitalOut(name, pin, Name=Value)
            % Build a digital output channel.
            %
            % Parameters
            %   name - Logical channel name.
            %   pin  - Board pin.
            %   ActiveHigh, IdleState, Notes - Optional overrides.
            %
            % Returns
            %   obj - teensy.Channel with Direction "Output" and Kind "Digital".
            arguments
                name (1,1) string = ""
                pin (1,1) double = -1
                options.ActiveHigh (1,1) logical = true
                options.IdleState (1,1) double {mustBeMember(options.IdleState, [0 1])} = 0
                options.Notes (1,1) string = ""
            end

            obj = teensy.Channel(name, Direction = "Output", Kind = "Digital", Pin = pin, ...
                ActiveHigh = options.ActiveHigh, IdleState = options.IdleState, ...
                Notes = options.Notes);
        end

        function obj = analogIn(name, pin, options)
            % obj = teensy.Channel.analogIn(name, pin, Name=Value)
            % Build a thresholded analog input channel.
            %
            % Parameters
            %   name - Logical channel name.
            %   pin  - Board pin; must be an analog input on the target board.
            %   ThresholdHigh, ThresholdLow, Units, Scale, Offset, SampleRateHz,
            %   Oversample, Notes - Optional overrides.
            %
            % Returns
            %   obj - teensy.Channel with Direction "Input" and Kind "Analog".
            arguments
                name (1,1) string = ""
                pin (1,1) double = -1
                options.ThresholdHigh (1,1) double = 2.5
                options.ThresholdLow (1,1) double = 2.0
                options.Units (1,1) string = "V"
                options.Scale (1,1) double = 1
                options.Offset (1,1) double = 0
                options.SampleRateHz (1,1) double = 1000
                options.Oversample (1,1) double = 1
                options.Notes (1,1) string = ""
            end

            obj = teensy.Channel(name, Direction = "Input", Kind = "Analog", Pin = pin, ...
                ThresholdHigh = options.ThresholdHigh, ThresholdLow = options.ThresholdLow, ...
                Units = options.Units, Scale = options.Scale, Offset = options.Offset, ...
                SampleRateHz = options.SampleRateHz, Oversample = options.Oversample, ...
                Notes = options.Notes);
        end

        function obj = analogOut(name, pin, options)
            % obj = teensy.Channel.analogOut(name, pin, Name=Value)
            % Build an analog output channel.
            %
            % Teensy 4.x has no true DAC, so AnalogOutMode selects between PWM,
            % the MQS sigma-delta output and an external SPI DAC.
            %
            % Parameters
            %   name - Logical channel name.
            %   pin  - Board pin, or the chip select for AnalogOutMode "SPI_DAC".
            %   AnalogOutMode, PwmFrequencyHz, PwmResolutionBits, Units, Notes -
            %       Optional overrides.
            %
            % Returns
            %   obj - teensy.Channel with Direction "Output" and Kind "Analog".
            arguments
                name (1,1) string = ""
                pin (1,1) double = -1
                options.AnalogOutMode (1,1) string {mustBeMember(options.AnalogOutMode, ["PWM","MQS","SPI_DAC"])} = "PWM"
                options.PwmFrequencyHz (1,1) double {mustBePositive} = 1000
                options.PwmResolutionBits (1,1) double {mustBeInteger, mustBePositive} = 12
                options.Units (1,1) string = "V"
                options.Notes (1,1) string = ""
            end

            obj = teensy.Channel(name, Direction = "Output", Kind = "Analog", Pin = pin, ...
                AnalogOutMode = options.AnalogOutMode, ...
                PwmFrequencyHz = options.PwmFrequencyHz, ...
                PwmResolutionBits = options.PwmResolutionBits, ...
                Units = options.Units, Notes = options.Notes);
        end

        function C = defaultSet()
            % C = teensy.Channel.defaultSet()
            % Return a starter channel set for a single operant box.
            %
            % Pins are valid on both the Teensy 4.0 and the Teensy 4.1, so the
            % set loads cleanly whichever board profile a program selects.
            %
            % Returns
            %   C - 1x6 teensy.Channel: Poke, Lick, Reward, HouseLight, Sync, Piezo.
            C = teensy.Channel.empty(1, 0);

            C(end+1) = teensy.Channel.digitalIn("Poke", 2, ...
                ActiveHigh = false, PullMode = "PullUp", DebounceMs = 5, ...
                Notes = "Nose-poke IR beam; the detector pulls the pin low while the beam is broken.");

            C(end+1) = teensy.Channel.digitalIn("Lick", 3, ...
                ActiveHigh = false, PullMode = "PullUp", DebounceMs = 2, ...
                Notes = "Lick spout contact sensor, switched to ground.");

            C(end+1) = teensy.Channel.digitalOut("Reward", 4, ...
                ActiveHigh = true, IdleState = 0, ...
                Notes = "Solenoid reward valve driven through a transistor.");

            C(end+1) = teensy.Channel.digitalOut("HouseLight", 5, ...
                ActiveHigh = true, IdleState = 1, ...
                Notes = "House light; on between trials and extinguished as a time-out.");

            C(end+1) = teensy.Channel.digitalOut("Sync", 6, ...
                ActiveHigh = true, IdleState = 0, ...
                Notes = "TTL sync pulse to the acquisition system.");

            C(end+1) = teensy.Channel.analogIn("Piezo", 14, ...
                ThresholdHigh = 2.5, ThresholdLow = 2.0, Units = "V", ...
                Scale = 3.3/4095, Offset = 0, SampleRateHz = 2000, Oversample = 4, ...
                Notes = "Piezo lick/contact sensor on A0; Scale converts 12-bit counts to volts.");
        end

        function obj = fromStruct(S)
            % obj = teensy.Channel.fromStruct(S)
            % Rebuild channels from structs written by toStruct.
            %
            % Fields missing from an older save fall back to the current
            % defaults, and an unrecognised enumeration value is replaced by the
            % default rather than raising an error.
            %
            % Parameters
            %   S - Struct array from toStruct, or a teensy.Channel array.
            %
            % Returns
            %   obj - 1xN teensy.Channel.
            if isa(S, 'teensy.Channel')
                obj = reshape(S, 1, []);
                return
            end

            if ~isstruct(S) || isempty(S)
                obj = teensy.Channel.empty(1, 0);
                return
            end

            d = teensy.Channel();
            obj = teensy.Channel.empty(1, 0);

            for k = 1:numel(S)
                c = teensy.Channel(string(teensy.getFieldOr(S(k), 'Name', d.Name)));
                c.Direction = pickMember_(teensy.getFieldOr(S(k), 'Direction', d.Direction), ...
                    ["Input","Output"], d.Direction);
                c.Kind = pickMember_(teensy.getFieldOr(S(k), 'Kind', d.Kind), ...
                    ["Digital","Analog"], d.Kind);
                c.Pin = double(teensy.getFieldOr(S(k), 'Pin', d.Pin));
                c.ActiveHigh = logical(teensy.getFieldOr(S(k), 'ActiveHigh', d.ActiveHigh));
                c.DebounceMs = max(0, double(teensy.getFieldOr(S(k), 'DebounceMs', d.DebounceMs)));
                c.PullMode = pickMember_(teensy.getFieldOr(S(k), 'PullMode', d.PullMode), ...
                    ["None","PullUp","PullDown"], d.PullMode);
                c.ThresholdHigh = double(teensy.getFieldOr(S(k), 'ThresholdHigh', d.ThresholdHigh));
                c.ThresholdLow = double(teensy.getFieldOr(S(k), 'ThresholdLow', d.ThresholdLow));
                c.Units = string(teensy.getFieldOr(S(k), 'Units', d.Units));
                c.Scale = double(teensy.getFieldOr(S(k), 'Scale', d.Scale));
                c.Offset = double(teensy.getFieldOr(S(k), 'Offset', d.Offset));
                c.SampleRateHz = double(teensy.getFieldOr(S(k), 'SampleRateHz', d.SampleRateHz));
                c.Oversample = double(teensy.getFieldOr(S(k), 'Oversample', d.Oversample));
                c.IdleState = pickLevel_(teensy.getFieldOr(S(k), 'IdleState', d.IdleState), d.IdleState);
                c.AnalogOutMode = pickMember_(teensy.getFieldOr(S(k), 'AnalogOutMode', d.AnalogOutMode), ...
                    ["PWM","MQS","SPI_DAC"], d.AnalogOutMode);
                c.PwmFrequencyHz = pickPositive_(teensy.getFieldOr(S(k), 'PwmFrequencyHz', d.PwmFrequencyHz), ...
                    d.PwmFrequencyHz);
                c.PwmResolutionBits = pickPositive_(round(double( ...
                    teensy.getFieldOr(S(k), 'PwmResolutionBits', d.PwmResolutionBits))), ...
                    d.PwmResolutionBits);
                c.Notes = string(teensy.getFieldOr(S(k), 'Notes', d.Notes));
                obj(end+1) = c;
            end
        end
    end
end


function S = templateStruct_()
% S = templateStruct_()
% Return the 1x1 serialization struct with the canonical field order.
S = struct( ...
    'Name', "", ...
    'Direction', "", ...
    'Kind', "", ...
    'Pin', -1, ...
    'ActiveHigh', true, ...
    'DebounceMs', 0, ...
    'PullMode', "", ...
    'ThresholdHigh', 0, ...
    'ThresholdLow', 0, ...
    'Units', "", ...
    'Scale', 1, ...
    'Offset', 0, ...
    'SampleRateHz', 0, ...
    'Oversample', 1, ...
    'IdleState', 0, ...
    'AnalogOutMode', "", ...
    'PwmFrequencyHz', 0, ...
    'PwmResolutionBits', 0, ...
    'Notes', "");
end


function board = resolveBoard_(context)
% board = resolveBoard_(context)
% Accept either a BoardProfile or a Program and return the profile to check.
if isa(context, 'teensy.BoardProfile')
    board = context;
elseif isa(context, 'teensy.Program')
    board = context.Board;
else
    board = teensy.BoardProfile();
end
end


function v = pickMember_(value, allowed, default)
% v = pickMember_(value, allowed, default)
% Coerce a stored enumeration value, falling back when it is unrecognised.
v = default;
if ~(ischar(value) || isstring(value))
    return
end
s = string(value);
if isscalar(s) && ismember(s, allowed)
    v = s;
end
end


function v = pickLevel_(value, default)
% v = pickLevel_(value, default)
% Coerce a stored 0/1 level, falling back when it is neither.
v = default;
if isnumeric(value) || islogical(value)
    d = double(value);
    if isscalar(d) && ismember(d, [0 1])
        v = d;
    end
end
end


function v = pickPositive_(value, default)
% v = pickPositive_(value, default)
% Coerce a stored positive number, falling back when it is not usable.
v = default;
if isnumeric(value) && isscalar(value) && isfinite(value) && value > 0
    v = double(value);
end
end


function w = polarityWord_(activeHigh)
% w = polarityWord_(activeHigh)
% Return the human word for a digital polarity.
if activeHigh
    w = "active high";
else
    w = "active low";
end
end


function w = levelWord_(level)
% w = levelWord_(level)
% Return the human word for a logic level.
if level >= 1
    w = "high";
else
    w = "low";
end
end


function w = pullWord_(pullMode)
% w = pullWord_(pullMode)
% Return the human word for a pull resistor setting.
switch pullMode
    case "PullUp"
        w = "pull-up";
    case "PullDown"
        w = "pull-down";
    otherwise
        w = "no pull";
end
end
