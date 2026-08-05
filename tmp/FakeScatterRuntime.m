classdef FakeScatterRuntime < handle
    % Minimal epsych.Runtime stand-in for gui.ParameterScatter smoke tests.
    % Provides the HELPER event broadcaster, a TRIALS struct, and an
    % all_parameters method reporting one invisible parameter, one
    % array-valued parameter, and one write-only parameter — none of which
    % may reach the scatter's selectors.

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
                'validName', {'FreqHz','LevelDB','HiddenParam','WaveBuf','GoTrigger'}, ...
                'Visible',   {true,    true,     false,        true,     true}, ...
                'isArray',   {false,   false,    false,        true,     false}, ...
                'Type',      {'Float', 'Float',  'Float',      'Buffer', 'Boolean'}, ...
                'Access',    {'Read',  'Any',    'Read',       'Read',   'Write'});
            if ~options.includeInvisible
                P = P([P.Visible]);
            end
        end
    end
end
