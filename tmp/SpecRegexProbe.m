classdef SpecRegexProbe < handle
    % SpecRegexProbe(parent, channel, options)
    %
    % A component that declares no spec and whose HEADER COMMENT contains a
    % usage example -- the norm in this toolbox. Usage: obj = SpecRegexProbe(fromHeaderComment, x)
    %
    % gui.ComponentSpec infers the constructor signature by regex over the
    % source. Before the pattern was anchored to a line starting with
    % "function", [^=]* reached from an earlier "function" keyword across
    % this comment and returned the arguments of the usage example above,
    % so the component was built with the wrong positionals. That is what
    % tmp/smoke_test_componentspec.m checks with this class.

    properties (SetAccess = private)
        PanelH
        Channel
    end

    methods
        function tf = helper(obj, x)
            % A method BEFORE the constructor whose comment also has the
            % pattern the regex could latch onto: y = SpecRegexProbe(decoy)
            tf = ~isempty(obj) && ~isempty(x);
        end

        function obj = SpecRegexProbe(parent, channel, options)
            arguments
                parent (1,1)
                channel (1,1) double = 1
                options.Color (1,:) char = 'blue'
            end
            obj.Channel = channel;
            obj.PanelH  = uipanel(parent, 'BorderType', 'none');
            uilabel(uigridlayout(obj.PanelH, [1 1]), 'Text', options.Color);
        end

        function delete(obj)
            if ~isempty(obj.PanelH) && isvalid(obj.PanelH), delete(obj.PanelH); end
        end
    end
end
