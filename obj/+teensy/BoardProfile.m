classdef BoardProfile
    % obj = teensy.BoardProfile()
    % obj = teensy.BoardProfile(Name=name, DigitalPins=pins, ...)
    % Pin capability table for a Teensy board.
    %
    % A BoardProfile is the design-time authority on what a pin can do. It is
    % pure data plus one query, supports(), which teensy.Channel.validate uses to
    % reject a channel bound to a pin the silicon cannot drive. Default
    % construction yields the Teensy 4.1 profile.
    %
    % Teensy 4.x boards have no true DAC. Analog output is one of PWM
    % (analogWrite), MQS on pins 10 and 12, or an external SPI DAC, which is why
    % teensy.Channel carries an AnalogOutMode rather than assuming a DAC exists.
    %
    % Properties
    %   Name          - Board name, e.g. "Teensy 4.1".
    %   NumPins       - Number of addressable pins; valid pins are 0..NumPins-1.
    %   DigitalPins   - Pins usable for digital input or output.
    %   AnalogInPins  - Pins wired to the ADC, in A0..An order.
    %   PwmPins       - Pins that analogWrite can drive.
    %   MqsPins       - Pins carrying the medium quality sound sigma-delta output.
    %   ReservedPins  - Pins with an on-board function; usable but advisory.
    %   Notes         - Board facts worth showing in the pin picker.
    %
    % Methods
    %   supports      - Test a pin against a capability.
    %   isReserved    - Test whether a pin has an on-board function.
    %   analogLabel   - "A0".."A17" label for an analog input pin.
    %   describe      - One-line human summary.
    %   toStruct      - Serialize to a plain struct.
    %   fromStruct    - (static) Rebuild from a struct written by toStruct.
    %   teensy40      - (static) Teensy 4.0 profile.
    %   teensy41      - (static) Teensy 4.1 profile.
    %   list          - (static) All known profiles.
    %   byName        - (static) Look a profile up by name.
    %
    % Example
    %   B = teensy.BoardProfile.teensy41();
    %   B.supports("analogIn", 14)    % true  (A0)
    %   B.supports("mqs", 10)         % true
    %   B.supports("analogIn", 2)     % false
    %
    % See also: teensy.Channel, teensy.Program, documentation/teensy/

    properties
        Name (1,1) string = "Teensy 4.1"

        NumPins (1,1) double {mustBeInteger, mustBeNonnegative} = 55

        DigitalPins (1,:) double = 0:54

        % A0-A13 on pins 14-27, A14-A17 on pins 38-41.
        AnalogInPins (1,:) double = [14:27, 38:41]

        PwmPins (1,:) double = [0:15, 18, 19, 22:25, 28, 29, 33:39, 42:47, 51, 54]

        % Medium Quality Sound sigma-delta outputs; need an RC filter.
        MqsPins (1,:) double = [10, 12]

        % Pin 13 drives the on-board LED; 42-47 are wired to the SD socket.
        ReservedPins (1,:) double = [13, 42:47]

        Notes (1,1) string = teensy.BoardProfile.notes41()
    end

    methods
        function obj = BoardProfile(options)
            % obj = teensy.BoardProfile(Name=name, ...)
            % Construct a board profile, defaulting to the Teensy 4.1 facts.
            %
            % Parameters
            %   Name, NumPins, DigitalPins, AnalogInPins, PwmPins, MqsPins,
            %   ReservedPins, Notes - Optional overrides for the matching
            %       properties.
            %
            % Returns
            %   obj - Configured teensy.BoardProfile.
            arguments
                options.Name (1,1) string
                options.NumPins (1,1) double {mustBeInteger, mustBeNonnegative}
                options.DigitalPins (1,:) double
                options.AnalogInPins (1,:) double
                options.PwmPins (1,:) double
                options.MqsPins (1,:) double
                options.ReservedPins (1,:) double
                options.Notes (1,1) string
            end

            fn = fieldnames(options);
            for i = 1:numel(fn)
                obj.(fn{i}) = options.(fn{i});
            end
        end

        function tf = supports(obj, capability, pin)
            % tf = obj.supports(capability, pin)
            % Test whether a pin can provide a capability on this board.
            %
            % Parameters
            %   capability - "digital", "analogIn", "pwm" or "mqs".
            %   pin        - Pin number, or a vector of pin numbers.
            %
            % Returns
            %   tf - Logical of the same size as pin. False for pins outside
            %       0..NumPins-1, for non-integers and for NaN.
            arguments
                obj (1,1) teensy.BoardProfile
                capability (1,1) string {mustBeMember(capability, ["digital","analogIn","pwm","mqs"])}
                pin (1,:) double
            end

            switch capability
                case "digital"
                    allowed = obj.DigitalPins;
                case "analogIn"
                    allowed = obj.AnalogInPins;
                case "pwm"
                    allowed = obj.PwmPins;
                case "mqs"
                    allowed = obj.MqsPins;
            end

            tf = ismember(pin, allowed) & pin >= 0 & pin < obj.NumPins & pin == floor(pin);
        end

        function tf = isReserved(obj, pin)
            % tf = obj.isReserved(pin)
            % Test whether a pin already has an on-board function.
            %
            % Reserved pins remain electrically usable, so callers should warn
            % rather than reject.
            %
            % Parameters
            %   pin - Pin number, or a vector of pin numbers.
            %
            % Returns
            %   tf - Logical of the same size as pin.
            arguments
                obj (1,1) teensy.BoardProfile
                pin (1,:) double
            end

            tf = ismember(pin, obj.ReservedPins);
        end

        function label = analogLabel(obj, pin)
            % label = obj.analogLabel(pin)
            % Return the "A<n>" label the Teensy pinout card prints for a pin.
            %
            % Parameters
            %   pin - Pin number.
            %
            % Returns
            %   label - "A0".."A17", or "" when the pin is not an analog input.
            arguments
                obj (1,1) teensy.BoardProfile
                pin (1,1) double
            end

            idx = find(obj.AnalogInPins == pin, 1);
            if isempty(idx)
                label = "";
            else
                label = "A" + string(idx - 1);
            end
        end

        function s = describe(obj)
            % s = obj.describe()
            % Return a one-line summary for a status bar or a picker list.
            %
            % Returns
            %   s - Scalar string.
            arguments
                obj (1,1) teensy.BoardProfile
            end

            s = sprintf("%s: %d pins, %d analog in, %d PWM, MQS on %s", ...
                obj.Name, obj.NumPins, numel(obj.AnalogInPins), numel(obj.PwmPins), ...
                strjoin(string(obj.MqsPins), "/"));
        end

        function S = toStruct(obj)
            % S = obj.toStruct()
            % Serialize this profile to a plain struct for saving or undo.
            %
            % Returns
            %   S - Struct array shaped like obj with one field per property.
            arguments
                obj teensy.BoardProfile
            end

            S = repmat(templateStruct_(), size(obj));
            for k = 1:numel(obj)
                S(k).Name = obj(k).Name;
                S(k).NumPins = obj(k).NumPins;
                S(k).DigitalPins = obj(k).DigitalPins;
                S(k).AnalogInPins = obj(k).AnalogInPins;
                S(k).PwmPins = obj(k).PwmPins;
                S(k).MqsPins = obj(k).MqsPins;
                S(k).ReservedPins = obj(k).ReservedPins;
                S(k).Notes = obj(k).Notes;
            end
        end
    end

    methods (Static)
        function obj = fromStruct(S)
            % obj = teensy.BoardProfile.fromStruct(S)
            % Rebuild profiles from structs written by toStruct.
            %
            % Missing fields fall back to the Teensy 4.1 defaults, so a profile
            % saved before a field existed still loads.
            %
            % Parameters
            %   S - Struct array from toStruct, or a teensy.BoardProfile.
            %
            % Returns
            %   obj - 1xN teensy.BoardProfile.
            if isa(S, 'teensy.BoardProfile')
                obj = reshape(S, 1, []);
                return
            end

            if ~isstruct(S) || isempty(S)
                obj = teensy.BoardProfile.empty(1, 0);
                return
            end

            d = teensy.BoardProfile();
            obj = teensy.BoardProfile.empty(1, 0);
            for k = 1:numel(S)
                b = teensy.BoardProfile();
                b.Name = string(teensy.getFieldOr(S(k), 'Name', d.Name));
                b.NumPins = double(teensy.getFieldOr(S(k), 'NumPins', d.NumPins));
                b.DigitalPins = pinList_(teensy.getFieldOr(S(k), 'DigitalPins', d.DigitalPins));
                b.AnalogInPins = pinList_(teensy.getFieldOr(S(k), 'AnalogInPins', d.AnalogInPins));
                b.PwmPins = pinList_(teensy.getFieldOr(S(k), 'PwmPins', d.PwmPins));
                b.MqsPins = pinList_(teensy.getFieldOr(S(k), 'MqsPins', d.MqsPins));
                b.ReservedPins = pinList_(teensy.getFieldOr(S(k), 'ReservedPins', d.ReservedPins));
                b.Notes = string(teensy.getFieldOr(S(k), 'Notes', d.Notes));
                obj(end+1) = b;
            end
        end

        function obj = teensy40()
            % obj = teensy.BoardProfile.teensy40()
            % Return the Teensy 4.0 pin capability table.
            %
            % 40 pins (0-39). Analog inputs A0-A13 on pins 14-27. No DAC.
            %
            % Returns
            %   obj - teensy.BoardProfile for the Teensy 4.0.
            obj = teensy.BoardProfile( ...
                Name = "Teensy 4.0", ...
                NumPins = 40, ...
                DigitalPins = 0:39, ...
                AnalogInPins = 14:27, ...
                PwmPins = [0:15, 18, 19, 22:25, 28, 29, 33:39], ...
                MqsPins = [10, 12], ...
                ReservedPins = 13, ...
                Notes = teensy.BoardProfile.notes40());
        end

        function obj = teensy41()
            % obj = teensy.BoardProfile.teensy41()
            % Return the Teensy 4.1 pin capability table.
            %
            % 55 pins (0-54). Analog inputs A0-A13 on pins 14-27 and A14-A17 on
            % pins 38-41. No DAC.
            %
            % Returns
            %   obj - teensy.BoardProfile for the Teensy 4.1.
            obj = teensy.BoardProfile();
        end

        function B = list()
            % B = teensy.BoardProfile.list()
            % Return every board profile the designer knows about.
            %
            % With no output argument the profiles are printed instead.
            %
            % Returns
            %   B - 1xN teensy.BoardProfile.
            B = [teensy.BoardProfile.teensy40(), teensy.BoardProfile.teensy41()];

            if nargout == 0
                for i = 1:numel(B)
                    vprintf(1, '%s', B(i).describe());
                end
                clear B
            end
        end

        function obj = byName(name)
            % obj = teensy.BoardProfile.byName(name)
            % Look up a board profile by name.
            %
            % Matching ignores case, spaces and punctuation, so "Teensy 4.1",
            % "teensy41" and "4.1" all select the same profile.
            %
            % Parameters
            %   name - Board name.
            %
            % Returns
            %   obj - Matching teensy.BoardProfile.
            arguments
                name (1,1) string
            end

            key = lower(regexprep(char(name), '[^0-9A-Za-z]', ''));

            switch key
                case {'teensy40', '40', 't40', 'teensy4'}
                    obj = teensy.BoardProfile.teensy40();
                case {'teensy41', '41', 't41'}
                    obj = teensy.BoardProfile.teensy41();
                otherwise
                    known = teensy.BoardProfile.list();
                    error('teensy:BoardProfile:UnknownBoard', ...
                        'Unknown board "%s". Known boards: %s.', ...
                        name, strjoin([known.Name], ', '));
            end
        end

        function s = notes40()
            % s = teensy.BoardProfile.notes40()
            % Return the Teensy 4.0 board notes shown in the pin picker.
            %
            % Returns
            %   s - Scalar string.
            s = "Teensy 4.0 (i.MX RT1062): 40 pins, 0-39. Analog inputs A0-A13 " + ...
                "on pins 14-27. There is no true DAC on any Teensy 4.x board: " + ...
                "analog output is PWM via analogWrite, MQS sigma-delta audio on " + ...
                "pins 10 and 12 (needs an RC filter), or an external SPI DAC. " + ...
                "Pin 13 drives the on-board LED. Logic is 3.3 V and is NOT 5 V " + ...
                "tolerant.";
        end

        function s = notes41()
            % s = teensy.BoardProfile.notes41()
            % Return the Teensy 4.1 board notes shown in the pin picker.
            %
            % Returns
            %   s - Scalar string.
            s = "Teensy 4.1 (i.MX RT1062): 55 pins, 0-54. Analog inputs A0-A13 " + ...
                "on pins 14-27 and A14-A17 on pins 38-41. There is no true DAC " + ...
                "on any Teensy 4.x board: analog output is PWM via analogWrite, " + ...
                "MQS sigma-delta audio on pins 10 and 12 (needs an RC filter), or " + ...
                "an external SPI DAC. Pin 13 drives the on-board LED and pins " + ...
                "42-47 are wired to the on-board SD socket. Logic is 3.3 V and is " + ...
                "NOT 5 V tolerant.";
        end
    end
end


function S = templateStruct_()
% S = templateStruct_()
% Return the 1x1 serialization struct with the canonical field order.
S = struct( ...
    'Name', "", ...
    'NumPins', 0, ...
    'DigitalPins', [], ...
    'AnalogInPins', [], ...
    'PwmPins', [], ...
    'MqsPins', [], ...
    'ReservedPins', [], ...
    'Notes', "");
end


function pins = pinList_(value)
% pins = pinList_(value)
% Coerce a stored pin list to the 1xN double a pin property requires.
if isempty(value)
    pins = zeros(1, 0);
    return
end
pins = reshape(double(value), 1, []);
end
