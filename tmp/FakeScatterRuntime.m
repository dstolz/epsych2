classdef FakeScatterRuntime < handle
    % Minimal epsych.Runtime stand-in for gui.ParameterScatter smoke tests.
    % Provides the HELPER event broadcaster, a TRIALS struct, and an
    % all_parameters method reporting one invisible parameter, one
    % array-valued parameter, one write-only parameter, and one declared
    % text (Type='String') parameter — the first three may not reach the
    % scatter's selectors, the text one should reach them as categorical.

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
                'validName', {'FreqHz','LevelDB','HiddenParam','WaveBuf','GoTrigger','TrialTypeName'}, ...
                'Visible',   {true,    true,     false,        true,     true,       true}, ...
                'isArray',   {false,   false,    false,        true,     false,      false}, ...
                'Type',      {'Float', 'Float',  'Float',      'Buffer', 'Boolean',  'String'}, ...
                'Access',    {'Read',  'Any',    'Read',       'Read',   'Write',    'Any'});
            if ~options.includeInvisible
                P = P([P.Visible]);
            end
        end
    end
end
