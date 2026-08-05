classdef FakeScatterRuntime < handle
    % Minimal epsych.Runtime stand-in for gui.ParameterScatter smoke tests.
    % Provides the HELPER event broadcaster, a TRIALS struct, and an
    % all_parameters method that reports one invisible parameter.

    properties
        HELPER
        TRIALS = struct([])
    end

    methods
        function obj = FakeScatterRuntime()
            obj.HELPER = epsych.Helper;
        end

        function P = all_parameters(obj, options)
            arguments
                obj
                options.includeInvisible (1,1) logical = false
                options.includeTriggers (1,1) logical = false
                options.Access (1,:) char = 'All'
            end
            P = struct( ...
                'validName', {'FreqHz','LevelDB','HiddenParam'}, ...
                'Visible',   {true,    true,     false});
            if ~options.includeInvisible
                P = P([P.Visible]);
            end
        end
    end
end
