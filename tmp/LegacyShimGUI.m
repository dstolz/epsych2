classdef LegacyShimGUI < gui.BoxGUI
    % A subclass written against the DEPRECATED gui.BoxGUI name, standing in
    % for a lab's own GUI outside this repository. tmp/smoke_test_boxgui.m
    % uses it to prove the shim still constructs and still inherits the
    % statics. Delete alongside gui.BoxGUI.

    methods
        function obj = LegacyShimGUI(RUNTIME)
            obj@gui.BoxGUI(RUNTIME, Name='Legacy Shim', ...
                PreferenceTag='smokeBoxGUITest', Visible=false);
            if nargout == 0, clear obj; end
        end
    end

    methods (Access = protected)
        function build(obj, fig)
            g = uigridlayout(fig, [1 1]);
            obj.addControl(g, 'SmokeFreq');
        end
    end
end
