classdef TDT_RPcox < hw.Interface


    properties
        HW % RPco.x
    end


    properties (SetObservable = true)
        % hardware setup config. Abort updating if hardware connection is
        % already established.

        ModuleType      (1,1) string {mustBeMember(ModuleType,["RP2","RA16","RL2","RV8","RM1","RM2", ...
            "RX5","RX6","RX7","RX8","RZ2","RZ5","RZ6"])} = "RZ6"
        ModuleID        (1,1) int16 {mustBeGreaterThan(ModuleID,0)} = 1
        ConnectionType  (1,1) string {mustBeMember(ConnectionType,["GB","USB"])} = "GB"
        RPfilename      (1,1) string = ""
        SamplingRate    (1,1) double {mustBeGreaterThanOrEqual(SamplingRate,-1),mustBeFinite,mustBeNonNan,mustBeNonempty} = -1 % -1 indicates use sampling rate specified in RPfilename
    end

    properties (Dependent)
        hw_status
        hw_statusMessage
    end


    properties (SetAccess = private, GetAccess = private)
        hTDTfig
    end


    properties (Constant)
        Type = "TDT_RPcox"
    end


    methods % INHERITED FROM ABSTRACT CLASS hw.Interface
        % setup hardware interface. CONFIG is platform dependent
        setup_interface(obj)


        function close_interface(obj)
            obj.HW.Halt;
            try
                delete(obj.HW)
            end
            close(obj.hTDTfig)
        end

        % trigger a hardware event
        function t = trigger(obj,name)
            e = obj.HW.SetTagVal(name,1);
            % t = hat;
            t = datetime('now');
            if ~e, throwerrormsg(name); end
            pause(0.001)
            e = obj.HW.SetTagVal(name,0);
            if ~e
                beep
                errordlg(sprintf('UNABLE TO TRIGGER "%s"',name),'RP TRIGGER ERROR','modal')
                error('UNABLE TO TRIGGER "%s"',name)
            end

        end

        % set new value to one or more hardware parameters
        % returns TRUE if successful, FALSE otherwise
        function result = set_parameter(obj,param,value)


            if isscalar(value) && isstruct(value) && ~isfield(value,'buffer')
                % file buffer (usually WAV file) that needs to be loaded
                wfn = fullfile(value.path,value.file);
                value.buffer = audioread(wfn);
                obj.HW.SetTagVal(['~' param '_Size'],value.nsamps);
                result = obj.HW.WriteTagV(param,0,value.buffer(:)');

            elseif isstruct(value) && isfield(value,'buffer')
                % preloaded file buffer
                result = obj.HW.WriteTagV(param,0,value.buffer(:)');

            elseif isscalar(value)
                % set value
                result = obj.HW.SetTagVal(param,value);


            elseif ~ischar(value) && ismatrix(value) && ~isstruct(value)
                % write buffer
                result = obj.HW.WriteTagV(param,0,reshape(value,1,numel(value)));

            end

            %         if ~e
            %             vprintf(0,1,'** WARNING: Unable to update the parameter: ''%s'' **',param)
            %         end

        end

        % read current value for one or more hardware parameters
        function value  = get_parameter(obj,name)
            value = nan;
            datatype = obj.HW.GetTagType;
            switch datatype
                case {'I','S','L','A'}
                    value = obj.HW.GetTagVal(name);

                case 'D' % Data Buffer
                    bufsze = obj.HW.GetTagSize(name);
                    value = obj.HW.ReadTagV(name,0,bufsze);
                    obj.HW.ZeroTag(name); % clear out buffer after reading

                    % case 'P' % Coefficient buffer

                otherwise
                    fprintf(2,'WARNING: The parameter "%s" has an unrecognized datatype (''%s''). Data not collected.',name,RUNTIME.COMPILED.datatype)
            end
        end



        function status = get.hw_status(obj)
            s = double(obj.hw.GetStatus);

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
        function set.RPfilename(obj,fn)
            fn = string(fn);

            mustBeFile(fn)
            [~,~,ext] = fileparts(fn);

            assert(isequal(upper(ext),".RCX"), ...
                "RPfilename must have the file extention '.RCX'")

            obj.RPfilename = fn;
        end

    end


end