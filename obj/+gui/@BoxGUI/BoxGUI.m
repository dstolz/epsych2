classdef (Abstract) BoxGUI < gui.BehaviorGUI
    %BOXGUI Deprecated alias for gui.BehaviorGUI.
    %   Kept so a lab's own "classdef MyGUI < gui.BoxGUI" outside this
    %   repository keeps loading, and so gui.BoxGUI.saveFigurePosition and the
    %   other statics still resolve, through one release.
    %
    %   The class was renamed because the GUI is launched once per session
    %   against RUNTIME, never once per box: it never had a BoxID, and "box"
    %   already means a physical box everywhere else in the toolbox.
    %
    %   To migrate, change the superclass and the constructor's call to it:
    %       classdef MyGUI < gui.BehaviorGUI
    %           ...
    %           obj@gui.BehaviorGUI(RUNTIME, Name='My Task');
    %
    %   Remove after 2027-02.
    %
    % See also gui.BehaviorGUI

    methods
        function obj = BoxGUI(varargin)
            % obj = BoxGUI(RUNTIME, ...)
            % Forward everything to gui.BehaviorGUI and say so once.
            obj@gui.BehaviorGUI(varargin{:});
            vprintf(1, ['%s subclasses gui.BoxGUI, which is deprecated; ' ...
                'subclass gui.BehaviorGUI instead.'], class(obj))
        end
    end
end
