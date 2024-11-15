classdef TDT_OpenDev < hw.Interface


    properties
        HW % TDevAcc.X
    end


    properties (SetObservable = true)

        Server  (1,1) string = "local";
        Tank    (1,1) string = "";

        ModuleType      (1,1) string {mustBeMember(ModuleType,["RP2","RA16","RL2","RV8","RM1","RM2", ...
            "RX5","RX6","RX7","RX8","RZ2","RZ5","RZ6"])} = "RZ6"
        ModuleID        (1,1) int16 {mustBeGreaterThan(ModuleID,0)} = 1
        ConnectionType  (1,1) string {mustBeMember(ConnectionType,["GB","USB"])} = "GB"
    end

    properties (Dependent)
        hw_status
        hw_statusMessage
        hw_mode
    end


    properties (SetAccess = private, GetAccess = private)
        hTDTfig
    end


    properties (Constant)
        Type = "TDT_OpenDev"
    end


    methods % INHERITED FROM ABSTRACT CLASS hw.Interface
        % setup hardware interface. CONFIG is platform dependent
        setup_interface(obj)


        function close_interface(obj)
            obj.HW.CloseConnection;
            try
                delete(obj.HW)
            end
            close(obj.hTDTfig)
        end

        % trigger a hardware event
        function t = trigger(obj,name)
            e = obj.HW.SetTargetVal(name,1);
            % t = hat;
            t = datetime('now'); %DJS 6/2015
            if ~e, throwerrormsg(name); end
            pause(0.001)
            e = obj.HW.SetTargetVal(name,0);
            if ~e
                beep
                errordlg(sprintf('UNABLE TO TRIGGER "%s"',name),'RP TRIGGER ERROR','modal')
                error('UNABLE TO TRIGGER "%s"',name)
            end

        end

        % set new value to one or more hardware parameters
        % returns TRUE if successful, FALSE otherwise
        function result = set_parameter(obj,param,value)


            if isstruct(value) && ~isfield(value,'buffer')
                % file buffer (usually WAV file) that needs to be loaded
                wfn = fullfile(value.path,value.file);
                value.buffer = audioread(wfn);
                obj.HW.SetTargetVal(['~' param '_Size'],value.nsamps);
                result = obj.HW.WriteTargetV(param,0,single(value.buffer(:)'));

            elseif isstruct(value)
                % preloaded file buffer
                result = obj.HW.WriteTargetV(param,0,single(value.buffer(:)'));

            elseif isscalar(value) % set value
                result = obj.HW.SetTargetVal(param,value);

            end

        end

        % read current value for one or more hardware parameters
        function value = get_parameter(obj,name)
            value = nan;
 
            datatype = obj.HW.GetTargetType(name);
            datatype = char(datatype);

            switch datatype
                case {'I','S','L','A'}
                    value = obj.HW.GetTargetVal(name);

                case 'D' % Data Buffer
                    bufsze = obj.HW.GetTargetSize(name);
                    value = obj.HW.ReadTargetV(name,0,bufsze);
                    obj.HW.ZeroTarget(name);

                    % case 'P' % Coefficient buffer

                otherwise
                    fprintf(2,'WARNING: The parameter "%s" has an unrecognized datatype (''%s''). Data not collected.',name,datatype)

            end
        end



        function status = get.hw_status(obj)
            s = double(obj.hw.GetDeviceStatus);

            status = "error"; % default
            statusMessage = "ok";

            x = bitget(s,1:3);

            if ~any(x)
                status = "idle";
            end

            if x(1)
                status = "connected";
            else
                statusMessage = "Error connecting to RP module";
            end

            if x(2)
                status = "loaded";
            else
                statusMessage = "Error loading circuit to RP module";
            end

            if x(3)
                status = "running";
            else
                statusMessage = "Error runing the circuit";
            end

            obj.hw_statusMessage = statusMessage;

        end
    end


    methods % CHECK IF hw_status IS "IDLE" AND PARAMETER VALUES

        function m = get.hw_mode(obj)
            i = obj.hw.GetSysMode;

            lut = ["idle","standby","preview","record"];

            m = lut(i);
        end

    end



end