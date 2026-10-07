classdef TDT_Synapse_Mock < hw.TDT_Synapse
% TDT_Synapse_Mock - hw.TDT_Synapse over a SynapseAPI_Mock instead of a live server.
%
% Overrides ONLY the two client seams -- createApi_, where the backend
% constructs its SynapseAPI, and releaseApi_, where it disposes of one --
% so every other line runs as it would against Synapse: the Standby entry,
% module discovery and binding, the metadata translation, and the read,
% write, stimulus and trigger paths. Mirrors tmp/Bpod_Mock, which does the
% same for the serial backend at its transport seam.
%
% The one shared mock is handed back for every createApi_ (a temporary
% client for readHardwareParameters included) and never deleted, so a test
% can inspect it after the backend has let go.
%
% Usage
%   api = SynapseAPI_Mock();
%   I = TDT_Synapse_Mock(api);                % offline, like a loaded protocol
%   I.connect();
%   I = TDT_Synapse_Mock(api, Connect=true);  % discovers modules at once
%
% See also: SynapseAPI_Mock, hw.TDT_Synapse, tmp/smoke_test_synapse_legacy.m

    properties
        Api
    end

    methods
        function obj = TDT_Synapse_Mock(api, options)
            arguments
                api (1,1) SynapseAPI_Mock = SynapseAPI_Mock()
                options.Connect (1,1) logical = false
            end
            obj@hw.TDT_Synapse('mock', Connect = false);
            obj.Api = api;
            if options.Connect
                obj.connect();
            end
        end
    end

    methods (Access = protected)
        function api = createApi_(obj)
            api = obj.Api;
        end

        function releaseApi_(~, ~)
            % Kept: the test still owns it.
        end
    end
end
