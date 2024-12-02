classdef TDT_Synapse < hw.Interface


    properties
        ExperimentInfo (1,1) struct
    end


    properties (SetObservable,AbortSet)
        mode
    end


    properties (SetAccess = protected)
        HW (1,1) % handle to Synapse API

        Server  (1,:) char

        Module
    end

    properties (Constant)
        Type = "TDT_Synapse"
    end






    methods
        % constructor
        function obj = TDT_Synapse(Server)
            arguments
                Server (1,:) char = 'localhost';
            end

            obj.Server = Server;

            obj.setup_interface;

            obj.update_experiment_info;
        end
    end


    methods
        function update_experiment_info(obj)
            obj.ExperimentInfo.user         = obj.HW.getCurrentUser();
            obj.ExperimentInfo.subject      = obj.HW.getCurrentSubject();
            obj.ExperimentInfo.experiment   = obj.HW.getCurrentExperiment();
            obj.ExperimentInfo.tank         = obj.HW.getCurrentTank();
            obj.ExperimentInfo.block        = obj.HW.getCurrentBlock();
        end
    end




    methods (Access=protected) % INHERITED FROM ABSTRACT CLASS hw.Interface
        setup_interface(obj)



        function close_interface(obj)
            if obj.HW.Mode > hw.DeviceState.Idle
                obj.HW.mode = hw.DeviceState.Idle;
            end

            try %#ok<TRYNC>
                delete(obj.HW)
            end
        end






    end




    methods % INHERITED FROM ABSTRACT CLASS hw.Interface





        function set.mode(obj,mode)
            e.oldMode = obj.mode;
            e.mode = mode;

            % 0 (Idle), 1 (Standby), 2 (Preview), 3 (Record)
            obj.HW.setMode(double(mode));
            vprintf(2,'HW mode: %s',char(obj.mode))
        end


        function m = get.mode(obj)
            m = obj.HW.getMode();
            m = hw.DeviceState(m);
        end








        % trigger a hardware event
        function t = trigger(obj,name)
            % t = trigger(obj,name);
            % t = trigger(obj,P);
            % 
            % send trigger; that is quickly set logical parameter to high
            % and then low.
            %
            % name      name of an existing parameter
            % P         handle to a parameter object

            if isa(name,'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name);
            end

            module = P.Parent.Label;
            trig = P.Name;

            e = obj.HW.setParameterValue(module,trig,1);
            
            t = datetime('now');
            
            if ~e, throwerrormsg(module,trig); end
            pause(0.001)
            
            e = obj.HW.setParameterValue(module,trig,0);
            if ~e
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
                e = p.HW.setParameterValue(p.Parent.Label,p.Name,value(i));
                if e
                    vprintf(3,'Updated "%s" = %g',p.Name,value(i))
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
            
            value = arrayfun(@(p) obj.HW.getParameterValue(p.Parent.Label,p.Name),P);

            % return in original order
            [~,idx] = ismember(name,{P.Name});
            value = value(idx);
        end


    end


    
end