classdef cl_AppetitiveDetection_BoxGUI < cl_AppetitiveDetection_BehaviorGUI
    %CL_APPETITIVEDETECTION_BOXGUI Deprecated alias, kept for saved sessions.
    %   A project's behavior GUI is stored in the roster BY NAME, so a .esub or
    %   .ecfg written before the class was renamed still says
    %   "cl_AppetitiveDetection_BoxGUI". Nothing migrates a stored value, so
    %   this subclass is what keeps those sessions opening.
    %
    %   Constructing it is harmless: it is the same GUI, under the old figure
    %   Tag, so the saved window position follows the old name too. Edit the
    %   project (Subjects & Projects > Edit Project > Session Defaults) to name
    %   cl_AppetitiveDetection_BehaviorGUI instead, then delete this file.
    %
    %   Remove after 2027-02.
    %
    % See also cl_AppetitiveDetection_BehaviorGUI

    methods
        function obj = cl_AppetitiveDetection_BoxGUI(RUNTIME)
            % obj = cl_AppetitiveDetection_BoxGUI(RUNTIME)
            obj@cl_AppetitiveDetection_BehaviorGUI(RUNTIME);
            vprintf(1, ['This project names cl_AppetitiveDetection_BoxGUI, which ' ...
                'is deprecated; point it at cl_AppetitiveDetection_BehaviorGUI.'])
            if nargout == 0, clear obj; end
        end
    end
end
