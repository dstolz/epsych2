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
        IsConnected = false
    end


    properties (SetObservable,AbortSet)
        mode
    end


    properties (SetAccess = protected)
        HW = [] % handle to Synapse API

        Server  (1,:) char

        Module
    end

    properties (Access = private)
        ModeState_ (1,1) hw.DeviceState = hw.DeviceState.Idle
    end

    properties (Constant)
        Type = "TDT_Synapse"
    end






    methods
        % constructor
        function obj = TDT_Synapse(Server, options)
            arguments
                Server (1,:) char = 'localhost'
                options.Connect (1,1) logical = true
            end

            obj.Server = Server;
            obj.Module = hw.Module.empty(1, 0);

            if options.Connect
                obj.connect();
            end
        end

        function connect(obj)
            if obj.IsConnected
                return
            end

            obj.setup_interface();
            obj.IsConnected = true;
            obj.ModeState_ = obj.mode;
            obj.update_experiment_info;
        end

        function disconnect(obj)
            if ~obj.IsConnected
                return
            end

            obj.close_interface();
        end

        function results = selfTest(obj, options)
            % results = selfTest(obj)
            % results = selfTest(obj, Invasive=true)
            % Check that the Synapse API is installed and its server is
            % listening. Only a bare TCP socket is opened in the non-invasive
            % pass: connecting for real drives Synapse into Standby (see
            % setup_interface), which must never happen behind the operator's back.
            %
            % See also: hw.Interface.selfTest
            arguments
                obj
                options.Invasive (1,1) logical = false
            end

            % SynapseAPI's HTTP port; mirrors SynapseAPI.PORT.
            SYNAPSE_PORT = 24414;

            results = hw.Interface.selfTestResult();

            if isempty(which('SynapseAPI'))
                results(end+1) = hw.Interface.selfTestResult('Synapse API', 'fail', ...
                    'SynapseAPI is not on the MATLAB path.', ...
                    Remedy = "Run epsych_startup so TDTfun/SynapseAPI is added to the path.");
            else
                results(end+1) = hw.Interface.selfTestResult('Synapse API', 'pass', ...
                    sprintf('SynapseAPI found: %s', which('SynapseAPI')));
            end

            target = sprintf('%s:%d', obj.Server, SYNAPSE_PORT);
            if obj.IsConnected
                results(end+1) = hw.Interface.selfTestResult('Synapse server reachable', 'pass', ...
                    sprintf('Already connected to %s.', target));
            else
                probe = [];
                try
                    probe = tcpclient(obj.Server, SYNAPSE_PORT, 'Timeout', 1);
                    results(end+1) = hw.Interface.selfTestResult('Synapse server reachable', 'pass', ...
                        sprintf('TCP connect to %s succeeded.', target));
                catch ME
                    results(end+1) = hw.Interface.selfTestResult('Synapse server reachable', 'fail', ...
                        sprintf('Cannot reach the Synapse server at %s.', target), ...
                        Detail = string(ME.message), ...
                        Remedy = "Start Synapse on the target machine and confirm the Server name in ProtocolDesigner.");
                end
                if ~isempty(probe)
                    clear probe
                end
            end

            if ~options.Invasive
                return
            end

            % Invasive: connecting puts Synapse in Standby, so restore whatever
            % connection state we found.
            wasConnected = obj.IsConnected;
            try
                if ~wasConnected
                    obj.connect();
                end

                info = obj.ExperimentInfo;
                detail = strings(1,0);
                if isstruct(info) && ~isempty(fieldnames(info))
                    for f = string(fieldnames(info))'
                        detail(end+1) = sprintf("%s: %s", f, string(info.(f)));
                    end
                end
                detail(end+1) = sprintf("Modules: %d", numel(obj.Module));

                results(end+1) = hw.Interface.selfTestResult('Synapse session', 'pass', ...
                    sprintf('Connected; mode: %s', string(obj.mode)), ...
                    Detail = detail);
            catch ME
                results(end+1) = hw.Interface.selfTestResult('Synapse session', 'fail', ...
                    'Reached the server but could not establish a Synapse session.', ...
                    Detail = string(ME.message), ...
                    Remedy = "Confirm a rig is loaded in Synapse and that it is not already controlled by another client.");
            end

            if ~wasConnected
                try
                    obj.disconnect();
                catch ME
                    vprintf(0, 1, ME);
                end
            end
        end

        function setModules(obj, modules)
            if obj.IsConnected
                error('hw:TDT_Synapse:ConnectedModuleEdit', ...
                    'Modules can only be reassigned while the interface is offline.');
            end

            obj.Module = modules;
        end
    end

    methods (Static)
        function spec = getCreationSpec()
            spec = hw.InterfaceSpec( ...
                char(hw.TDT_Synapse.Type), ...
                'TDT Synapse', ...
                'Connect to a Synapse server and discover its exposed modules and parameters.', ...
                hw.InterfaceSpecOption( ...
                    'name', 'server', ...
                    'label', 'Server', ...
                    'defaultValue', 'localhost', ...
                    'required', false, ...
                    'inputType', 'text', ...
                    'choices', {}, ...
                    'isList', false, ...
                    'scope', 'interface', ...
                    'allowScalarExpansion', false, ...
                    'controlType', 'text', ...
                    'getFile', false, ...
                    'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', 'Select Synapse Server Target', ...
                    'description', 'Synapse server host name.'), ...
                @(opts) hw.TDT_Synapse(char(opts.server)));
        end
    end


    methods
        function update_experiment_info(obj)
            if ~obj.IsConnected || isempty(obj.HW)
                obj.ExperimentInfo = struct();
                return
            end

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
            if isempty(obj.HW)
                obj.IsConnected = false;
                return
            end

            if obj.HW.Mode > hw.DeviceState.Idle
                obj.HW.mode = hw.DeviceState.Idle;
            end

            if ~isempty(obj.HW) && isvalid(obj.HW)
                delete(obj.HW)
            end

            obj.HW = [];
            obj.IsConnected = false;
        end






    end




    methods % INHERITED FROM ABSTRACT CLASS hw.Interface





        function set.mode(obj,mode)
            obj.applyModeState_(mode);
        end


        function m = get.mode(obj)
            m = obj.queryModeState_();
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

            if ~obj.IsConnected || isempty(obj.HW)
                t = datetime('now');
                return
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

            if ~obj.IsConnected || isempty(obj.HW)
                e = true;
                return
            end

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

            if ~obj.IsConnected || isempty(obj.HW)
                value = cell(size(P));
                for i = 1:length(P)
                    value{i} = P(i).Value;
                end

                [~,idx] = ismember(name,{P.Name});
                value = value(idx);
                if isscalar(value)
                    value = value{1};
                end
                return
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

    methods (Access = private)
        function applyModeState_(obj, mode)
            obj.ModeState_ = mode;
            if ~obj.IsConnected || isempty(obj.HW)
                return
            end

            obj.HW.setMode(double(mode));
            vprintf(2,'HW mode: %s',char(obj.queryModeState_()))
        end

        function mode = queryModeState_(obj)
            if ~obj.IsConnected || isempty(obj.HW)
                mode = obj.ModeState_;
                return
            end

            mode = hw.DeviceState(obj.HW.getMode());
            obj.ModeState_ = mode;
        end
    end


    
end
