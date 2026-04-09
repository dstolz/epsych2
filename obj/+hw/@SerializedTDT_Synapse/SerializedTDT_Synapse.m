classdef SerializedTDT_Synapse < hw.Interface
    properties (SetAccess = protected)
        HW = []
        Server (1,:) char = ''
        Module (1,:) hw.Module = hw.Module.empty(1, 0)
    end

    properties (Constant)
        Type = "TDT_Synapse"
    end

    properties (SetObservable, AbortSet)
        mode (1,1) hw.DeviceState = hw.DeviceState.Idle
    end

    methods
        function obj = SerializedTDT_Synapse()
        end

        function result = trigger(~, ~)
            result = [];
        end

        function result = set_parameter(~, ~, ~)
            result = true;
        end

        function value = get_parameter(~, ~)
            value = [];
        end

        function setModules(obj, modules)
            obj.Module = modules;
        end
    end

    methods (Static)
        function spec = getCreationSpec()
            spec = hw.TDT_Synapse.getCreationSpec();
        end
    end

    methods (Access = protected)
        function close_interface(~)
        end

        function setup_interface(~)
        end
    end
end