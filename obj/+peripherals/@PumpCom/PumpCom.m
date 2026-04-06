classdef PumpCom < handle
    % obj = peripherals.PumpCom(RUNTIME, Port, BaudRate)
    % Serial interface for a syringe pump used during reward delivery.
    %
    % This class owns the serialport connection to the pump, initializes the
    % pump into the expected infusion configuration, and mirrors selected pump
    % settings through observable MATLAB properties. Updating one of the
    % observable properties sends the corresponding serial command to the pump.
    %
    % Parameters:
    %   RUNTIME		- Runtime object whose mode listener is used to close the pump
    %   		  connection when the experiment leaves online operation.
    %   Port			- Serial port identifier for the pump, for example "COM4".
    %   BaudRate		- Serial baud rate for the device connection (default: 19200).
    %
    % Properties:
    %   PumpRate		- Infusion rate sent to the pump.
    %   PumpUnits		- Two-character rate units understood by the pump, such as
    %   		  "MM" for mL/min.
    %   PumpOperationalTrigger	- Pump trigger mode code, such as "LE".
    %   SyringeDiameter	- Inner syringe diameter in mm.
    %   VolumeDispensed	- Dependent property that queries dispensed volume.
    %   PumpFirmwareVersion	- Dependent property that queries the pump firmware.
    %
    % Methods:
    %   create_gui		- Build a compact status and rate-control UI.
    %   available_ports	- List serial ports currently visible to MATLAB.
    %
    % Example:
    %   pump = peripherals.PumpCom(RUNTIME, "COM4", 19200);
    %   pump.PumpRate = 0.5;
    %   pump.create_gui();
    %
    % See also documentation/PumpCom.md.

    properties (SetObservable = true,GetObservable = true)
        PumpRate                (1,1) double {mustBePositive} = 0.7;   % Infusion rate value sent with RAT.
        PumpUnits               (1,2) char {mustBeMember(PumpUnits,{'UM','MM','UH','MH'})} = 'MM'; % Pump rate units, for example mL/min.
        PumpOperationalTrigger  (1,2) char = 'LE'; % Pump trigger mode code.
        SyringeDiameter         (1,1) double {mustBePositive} = 21.69; % Inner syringe diameter in mm.


        hVolumeDispensed                                           % UI label that shows the last dispensed volume.
        hPumpRate                                                  % UI numeric field for updating the pump rate.
    end


    properties (Dependent)
        VolumeDispensed                                            % Volume reported by the pump's dispensed-volume query.
        PumpFirmwareVersion                                        % Firmware string returned by the pump.
    end

    properties (SetAccess = protected)
        Device                                                     % serialport object used for pump communication.
        Port                                                       % Serial port identifier assigned at construction.
        BaudRate = 19200;                                          % Serial baud rate.
        DataBits = 8                                               % Serial data bit count.
        StopBits = 1;                                              % Serial stop bit count.


    end

    properties (SetAccess = protected, Hidden)
        Codes                                                      % Mapping between property names and pump commands.
        hl event.proplistener = event.proplistener.empty; % Property listeners that sync MATLAB state to the device.
    end

    methods
        function obj = PumpCom(RUNTIME,Port,BaudRate)
            % obj = PumpCom(RUNTIME, Port, BaudRate)
            % Create and initialize the syringe pump serial controller.
            %
            % Parameters:
            %   RUNTIME		- Runtime object that provides the mode listener.
            %   Port			- Serial port identifier for the pump.
            %   BaudRate		- Serial baud rate for the connection.
            %
            % Returns:
            %   obj			- Connected PumpCom instance.

            if nargin >= 1 &&  ~isempty(Port), obj.Port = Port; end
            if nargin >= 2 && ~isempty(BaudRate), obj.BaudRate = BaudRate; end


            obj.establish_serial_com;

            obj.default_reset;

            ev = fieldnames(obj.Codes);

            obj.hl(1) = listener(obj,ev,'PostSet',@obj.prop_update);
            obj.hl(2) = listener(obj,ev,'PreGet',@obj.prop_read);
            obj.hl(3) = listener(RUNTIME,'mode','PostSet',@obj.mode_change);

        end

        function delete(obj)

            try
                delete(obj.hl);
                delete(obj.Device);
                obj.kill_gui_timer;
            catch me
                warning(me.identifier,'%s',me.message)
            end

        end


        function mode_change(obj,~,event)
            if event.AffectedObject.mode < 2 && ~isempty(obj.Device) && isvalid(obj.Device)
                vprintf(2,'Closing Pump serial port connection on "%s"',obj.Port)
                obj.kill_gui_timer;
                delete(obj.Device);
            end
        end

        function default_reset(obj)

            obj.Codes.PumpRate.cmd = 'RAT';
            obj.Codes.PumpRate.nread = 12;
            obj.Codes.PumpRate.searchchar = [5 9];
            obj.Codes.PumpUnits.cmd = 'RAT';
            obj.Codes.PumpUnits.nread = 12;
            obj.Codes.PumpUnits.searchchar = [10 11];
            obj.Codes.SyringeDiameter.cmd = 'DIA';
            obj.Codes.SyringeDiameter.nread = 10;
            obj.Codes.SyringeDiameter.searchchar = [5 9];
            obj.Codes.PumpOperationalTrigger.cmd = 'TRG';
            obj.Codes.PumpOperationalTrigger.nread = 7;
            obj.Codes.PumpOperationalTrigger.searchchar = [5 6];

        end



        function v = get.VolumeDispensed(obj)
            v = nan;

            obj.send_command('DIS');

            timeout(0.1);
            while ~timeout && obj.Device.NumBytesAvailable < 19, end
            if timeout, return; end

            r = obj.read;
            if isempty(r), return; end

            i = find(r=='I',1,'last');
            if isempty(i), return; end
            v = str2double(r(i+1:i+5));
        end


        function v = get.PumpFirmwareVersion(obj)
            v = nan;

            obj.send_command('VER');

            timeout(0.1);
            while ~timeout && obj.Device.NumBytesAvailable < 15, end
            if timeout, return; end

            r = obj.read;

            v = r(5:end-1);
        end

        function p = get.Device(obj)
            if isempty(obj.Device)
                obj.establish_serial_com;
            end

            p = obj.Device;
        end



        function send_command(obj,cmd,val)

            if nargin == 3
                if isnumeric(val)
                    s = '%0.2f';
                elseif ischar(val)
                    s = '%s';
                else
                    s = '%g';
                end
                cmd = sprintf(['%s' s],cmd,val);
            end

            obj.Device.flush; % flush any remaining input buffer

            obj.Device.writeline(cmd); drawnow

        end

        function response = read(obj)
            response = '';

            if obj.Device.NumBytesAvailable == 0, return; end

            response = obj.Device.read(obj.Device.NumBytesAvailable,'uint8');
            response = char(response);
        end

        function establish_serial_com(obj)

            p = serialportlist('available');
            if ismember(obj.Port,p) || isempty(obj.Device) || ~isvalid(obj.Device)
                x = serialportfind(Tag = 'Pump');
                if ~isempty(x), delete(x); end
                obj.Device = serialport(obj.Port,obj.BaudRate, ...
                    'Tag','Pump', ...
                    'DataBits',obj.DataBits, ...
                    'StopBits',obj.StopBits, ...
                    'Parity','none', ...
                    'FlowControl','none', ...
                    'Timeout', 0.1);

            else
                fprintf('Port "%s" is already in use. Will try using it anyway.\n',obj.Port)
            end


            configureTerminator(obj.Device,'CR');

            vprintf(0,'Syringe Diameter = %.3g',obj.SyringeDiameter)

            obj.send_command('STP');
            obj.send_command('DIA',obj.SyringeDiameter);
            obj.send_command('RAT',sprintf('%.3f%s',obj.PumpRate,obj.PumpUnits));
            obj.send_command('INF');
            obj.send_command('VOL',0);
            obj.send_command('LN','on');
            obj.send_command('TRG',obj.PumpOperationalTrigger);
            obj.send_command('CLDINF');
        end


        function prop_update(obj,hObj,~)
            obj.send_command(obj.Codes.(hObj.Name).cmd,obj.(hObj.Name));
        end

        function v = prop_read(obj,hObj,~)
            v = [];

            C = obj.Codes.(hObj.Name);

            obj.Device.flush;

            obj.send_command(C.cmd);

            timeout(0.1);
            while ~timeout && obj.Device.NumBytesAvailable < C.nread, end
            if timeout, return; end

            v = obj.read;
            if isempty(v), return; end

            v = v(C.searchchar);

            if isnumeric(obj.(hObj.Name))
                v = str2double(v);
            end
        end






        % vvvvvvvvv gui functions vvvvvvvvvvv
        function create_gui(obj,parent)
            % create_gui(obj, parent)
            % Create a compact GUI for monitoring volume and editing rate.
            %
            % Parameters:
            %   obj			- PumpCom instance.
            %   parent		- Parent graphics container; creates a uifigure when empty.

            if nargin < 2 || isempty(parent)
                parent = uifigure('CloseRequestFcn',@obj.kill_gui_timer, ...
                    'Position',[600 800 150 90]);
            end

            % gui should be concise and minimally include:
            %   VolumeDispensed - updated on a low priority ~.25 s timer
            %   PumpRate - user adjustable text field with default value

            g = uigridlayout(parent);
            g.ColumnWidth = {'1x'};
            g.RowHeight   = {25, 25};

            obj.hVolumeDispensed = obj.create_VolumeDispensed_field(g);
            obj.hPumpRate = obj.create_PumpRate_field(g);

        end

        function h = create_VolumeDispensed_field(obj,parent)
            if nargin < 2 || isempty(parent), parent = gcf; end

            h = uilabel(parent,'Text','---','HorizontalAlignment','right');
            h.Tooltip = sprintf('Syringe Inner Diameter = %.2f',obj.SyringeDiameter);

            T = timerfind('tag','PumpComTimer');
            if ~isempty(T), stop(T); delete(T); end

            T = timer(                       ...
                'BusyMode',     'drop',      ...
                'ExecutionMode','fixedSpacing', ...
                'TasksToExecute',inf, ...
                'Period',        1, ...
                'Name',         'PumpComTimer', ...
                'Tag',          'PumpComTimer', ...
                'TimerFcn',     @obj.gui_update, ...
                'UserData',     h);

            start(T);
        end

        function h = create_PumpRate_field(obj,parent)
            if nargin < 2 || isempty(parent), parent = gcf; end

%             pu = obj.PumpUnits;
            m = 'mL'; t = 'min';
%             if pu(1) == 'U', m = 'µ'; end
%             if pu(2) == 'H', t = 'hour'; end

            s = [m '/' t];

            h = uieditfield(parent,'numeric', ...
                'Tag','PumpRate', ...
                'Value',obj.PumpRate, ...
                'Limits',[0 10], ...
                'LowerLimitInclusive','off', ...
                'UpperLimitInclusive','off', ...
                'ValueDisplayFormat',['%03.2f ' s], ...
                'Tooltip','Enter new value and hit "Enter" or click outside the field', ...
                'ValueChangedFcn',@obj.gui_update);

            h.Value = obj.PumpRate;
            obj.gui_update(h,[]);
        end


        function gui_update(obj,hObj,event)

            persistent VD

            switch hObj.Tag
                case 'PumpRate'
                    obj.PumpRate = hObj.Value;

                case 'PumpComTimer'
                    h = hObj.UserData;
                    switch event.Type
                        case 'TimerFcn'
                            try
                                cvd = obj.VolumeDispensed;
                            catch
                                h.Text = 'ERROR';
                                return
                            end
                            % only update field when pump value changes
                            if isempty(VD) || cvd ~= VD
                                VD = cvd;
                                h.Text = num2str(cvd,'%.3f mL');
                            end
                        case 'StopFcn'
                            return

                        case 'ErrorFcn'
                            return
                    end
            end
        end
    end

    methods (Static)
        function p = available_ports()
            % p = available_ports()
            % Return the serial ports currently available to MATLAB.
            %
            % Returns:
            %   p			- String array of available serial port names.

            p = serialportlist("available");
        end


        function kill_gui_timer(~,~)
            % kill_gui_timer(~, ~)
            % Stop and delete the timer used to refresh the pump GUI.

            t = timerfind('Tag','PumpComTimer');
            if ~isempty(t) && isvalid(t)
                stop(t)
                delete(t);
            end
        end
    end
end