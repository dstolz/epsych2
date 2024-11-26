classdef TDT_Synapse < hw.Interface


    properties
        ExperimentInfo

    end


    properties (SetObservable)
        mode
        modeStr
    end


    properties (SetAccess = protected)
        HW (1,1) % handle to Synapse API

        Server  (1,:) char

        nModules
        Module
    end

    properties (Dependent)
        status
        statusMessage
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




    methods % INHERITED FROM ABSTRACT CLASS hw.Interface
        setup_interface(obj)



        function close_interface(obj)
            if obj.HW.Mode > 0
                obj.HW.setMode(0);
            end

            try %#ok<TRYNC>
                delete(obj.HW)
            end
        end
















        function status = get.status(obj)
        end

        function status = get.statusMessage(obj)
        end





        function set_mode(obj,mode)
            if ischar(mode)
                if isequal(mode,'Run'), mode = 'Record'; end % translate
                
                if ~isequal(obj.modeStr,mode)
                    obj.HW.setModeStr(mode);
                end
            else
                if obj.mode ~= mode
                    obj.HW.setMode(mode);
                end
            end
        end


        function m = get.mode(obj)
            m = obj.HW.getMode();
        end

        function m = get.modeStr(obj)
            m = obj.HW.getModeStr();
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

            e = obj.HW.setParameterValue(P.Parent.Label,P.Name,1);
            
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

            e = arrayfun(@(p,v) obj.HW.setParameterValue(p.Parent.Label,p.Name,v), ...
                P,value);
        end






        
        % read current value for one or more hardware parameters
        function value = get_parameter(obj,name)

            if isa(name,'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name);
            end

            
            value = arrayfun(@(p) obj.HW.getParameterValue(p.Parent.Label,p.Name),P);
        end


    end


    
end