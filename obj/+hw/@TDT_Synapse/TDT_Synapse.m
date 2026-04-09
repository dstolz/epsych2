classdef TDT_Synapse < hw.Interface

    % obj = hw.TDT_Synapse(Server)
    % Hardware interface for TDT Synapse via the Synapse API wrapper.
    %
    % This interface implements the hw.Interface contract for reading and
    % writing Synapse parameters, reporting device mode, and issuing
    % trigger pulses through the Synapse API.
    %
    % Parameters
    %   Server - Synapse server host name. Defaults to 'localhost'.
    %
    % Properties
    %   ExperimentInfo - Current Synapse user, subject, experiment, tank,
    %       and block metadata.
    %   Module - Array of discovered hw.Module objects.
    %   mode - Current hw.DeviceState reported by Synapse.
    %
    % Methods
    %   update_experiment_info - Refresh ExperimentInfo from Synapse.
    %   trigger, set_parameter, get_parameter - Interface I/O methods.
    %
    % See also: documentation/hw/hw_Interface.md, hw.Module, hw.Parameter


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

    methods (Static)
        function spec = getCreationSpec()
            spec.type = char(hw.TDT_Synapse.Type);
            spec.label = 'TDT Synapse';
            spec.description = 'Connect to a Synapse server and discover its exposed modules and parameters.';
            spec.options = struct(...
                'name', {'server'}, ...
                'label', {'Server'}, ...
                'defaultValue', {'localhost'}, ...
                'required', {false}, ...
                'inputType', {'text'}, ...
                'choices', {{}}, ...
                'isList', {false}, ...
                'controlType', {'text'}, ...
                'getFile', {false}, ...
                'getFolder', {false}, ...
                'fileFilter', {{{'*.*', 'All Files (*.*)'}}}, ...
                'fileDialogTitle', {'Select Synapse Server Target'}, ...
                'description', {'Synapse server host name.'});
            spec.createFcn = @(opts) hw.TDT_Synapse(char(opts.server));
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
        setup_interface(obj) % Initialize Synapse connection and parameter modules.



        function close_interface(obj)
            if obj.HW.Mode > hw.DeviceState.Idle
                obj.HW.mode = hw.DeviceState.Idle;
            end

            if ~isempty(obj.HW) && isvalid(obj.HW)
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

            module = P.Module.Label;
            trig = obj.getHardwareParameterName(P);

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

            value = double(value); % must be double

            if isvector(P) && isscalar(value)
                value = repmat(value,size(P));
            end

            assert(numel(value) == numel(P));


            for i = 1:length(P)
                p = P(i);
                parameterName = obj.getHardwareParameterName(p);
                e = obj.HW.setParameterValue(p.Module.Label, parameterName, value(i));
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
                parameterName = obj.getHardwareParameterName(p);
                if p.isArray
                    value{i} = obj.HW.getParameterValues(p.Module.Label, parameterName);
                else
                    value{i} = obj.HW.getParameterValue(p.Module.Label, parameterName);
                end
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
