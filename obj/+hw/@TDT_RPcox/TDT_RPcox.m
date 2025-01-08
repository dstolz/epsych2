classdef TDT_RPcox < hw.Interface


    properties
        ExperimentInfo
    end

    properties (SetAccess = protected)
        HW (1,:) TDTRP

        Server  (1,:) char

        Module
    end

    properties (SetObservable,AbortSet)
        mode
    end




    properties (Constant)
        Type = "TDT_RPcox"
    end



    methods
        % constructor
        function obj = TDT_RPcox(RPvdsFile,moduleType,moduleAlias)
            RPvdsFile = cellstr(RPvdsFile);
            moduleType = cellstr(moduleType);
            moduleAlias = cellstr(moduleAlias);

            obj.setup_interface(RPvdsFile,moduleType,moduleAlias);
        end
    end





    methods (Access = protected)% INHERITED FROM ABSTRACT CLASS hw.Interface
        setup_interface(obj,RPvdsFile,moduleType,moduleAlias)


        function close_interface(obj)
            if obj.HW.Mode > hw.DeviceState.Idle
                obj.HW.mode = hw.DeviceState.Idle;
            end

            try %#ok<TRYNC>
                delete(obj.HW)
            end
        end

    end



    methods




        function set.mode(obj,mode)
            e.oldMode = obj.mode;
            e.mode = mode;

            if mode > hw.DeviceState.Idle
                obj.HW.run;
            else
                obj.HW.halt;
            end
            vprintf(2,'HW mode: %s',char(obj.mode))
        end


        function m = get.mode(obj)
            % m = obj.HW.status();
            m = double(obj.HW.RP.GetStatus);
            switch m
                case 0
                    m = hw.DeviceState.Error; % ?
                case 1
                    m = hw.DeviceState.Idle;
                case 3
                    m = hw.DeviceState.Standby;
                case 5
                    m = hw.DeviceState.Standby; % i think this is correct
                case 7
                    m = hw.DeviceState.Record;
            end
        end






        % trigger a hardware event
        function t = trigger(obj,name)
            % t = trigger(obj,name);
            % t = trigger(obj,hw.Parameter)

            if isa(name,'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name);
            end

            e = obj.HW.write(P.Name,1);
            
            t = datetime('now');
            
            if ~e, throwerrormsg(module,trig); end
            pause(0.001)
            
            e = obj.HW.write(P.Name,0);
            if e
                vprintf(3,'Triggered "%s"',P.Name)
            else
                errordlg(sprintf('UNABLE TO TRIGGER "%s" ON MODULE "%s"',trig,module),'SYNAPSE TRIGGER ERROR','modal')
                error('UNABLE TO TRIGGER "%s" ON MODULE "%s"',trig,module)
            end
        end
        
        



        % set new value to one or more hardware parameters
        % returns TRUE if successful, FALSE otherwise
        function e = set_parameter(obj,name,value)

            if isa(name,'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name);
            end

            if isvector(P) && isscalar(value)
                value = repmat(value,size(P));
            end

            assert(numel(value) == numel(P));

            for i = 1:length(P)
                p = P(i);
                e = P.HW.write(p.Name,value(i));
                if e
                    vstr = p.ValueStr;
                    vprintf(3,'Updated parameter: %s = %s',p.Name,vstr)
                else
                    vprintf(0,1,'Failed to write value to "%s"',p.Name)
                end
            end
        end






        
        % read current value for one or more hardware parameters
        function value = get_parameter(obj,name,options)
            arguments
                obj
                name
                options.includeInvisible (1,1) logical = false
                options.silenceParameterNotFound (1,1) logical = false
            end

            
            if isa(name,'hw.Parameter')
                P = name;
                name = {P.Name};
            else
                P = obj.find_parameter(name, ...
                    includeInvisible = options.includeInvisible, ...
                    silenceParameterNotFound=options.silenceParameterNotFound);
            end
            
            value = cell(size(P));
            for i = 1:length(P)
                p = P(i);

                value{i} = p.HW.read(p.Name);
            end


            % return in original order
            [~,idx] = ismember(name,{P.Name});
            value = value(idx);

            if isscalar(value)
                value = value{1};
            end
        end

    end


    
end