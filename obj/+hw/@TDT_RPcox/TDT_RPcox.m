classdef TDT_RPcox < hw.Interface


    properties
        ExperimentInfo
    end

    properties (SetAccess = protected)
        HW (1,:) TDTRP

        Server  (1,:) char

        Module
        nModules
    end

    properties (SetObservable)
        mode
        modeStr
    end



    properties (Dependent)
        status
        statusMessage
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


        function status = get.status(obj)
        end

        function status = get.statusMessage(obj)
        end





        function set.mode(obj,mode)
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
            m = hw.DeviceState(m);
        end

        function m = get.modeStr(obj)
            switch obj.mode
                case 0
                    m = 'Not connected';
                case 1
                    m = 'Connected';
                case 2
                    m = 'Circuit loaded';
                case 3
                    m = 'Connected & Loaded';
                case 4
                    m = 'Circuit running';

                otherwise
                    m = 'Unknown mode';

            end
            % m = obj.HW.getModeStr();
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
                e = P.HW.write(P.Name,value(i));
                if e
                    vprintf(3,'Updated "%s" = %g',P.Name,value(i))
                else
                    vprintf(0,1,'Failed to write value to "%s"',P.Name)
                end
            end
        end






        
        % read current value for one or more hardware parameters
        function value = get_parameter(obj,name,options)
            arguments
                obj
                name
                options.includeInvisible (1,1) logical = false
                options.silenceParamterNotFound (1,1) logical = false
            end

            if isa(name,'hw.Parameter')
                P = name;
                name = {P.Name};
            else
                P = obj.find_parameter(name, ...
                    includeInvisible = options.includeInvisible, ...
                    silenceParamterNotFound=options.silenceParamterNotFound);
            end
            
            value = nan(size(P));
            for i = 1:length(P)
                value(i) = P.HW.read(P.Name);
            end


            % return in original order
            [~,idx] = ismember(name,{P.Name});
            value = value(idx);
        end

    end


    
end