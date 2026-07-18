function configureIntanRecorder_(self, interfaces)
% configureIntanRecorder_(self, interfaces)
% Seed every hw.Intan_RHX in the given interface array from the
% 'ep_RunExpt_Intan' preference group before the interfaces connect. The
% settings file is loaded inside setup_interface (during connect), so the
% preferences must be on the object first — this is called just before
% RUNTIME.Interfaces is assigned in ExptDispatch, whose setter connects.
%
% This keeps getpref out of obj/+hw/ (the hardware layer is pref-free),
% mirroring how getVlcRecorder_ seeds the webcam recorder. The Intan settings
% are per-machine, so they live in preferences rather than the portable
% .eprot.
%
% Parameters
%   self       - epsych.RunExpt instance (for dfltDataPath).
%   interfaces - hw.Interface array from the loaded protocol.
arguments
    self
    interfaces
end

for p = interfaces(:).'
    if ~isa(p, 'hw.Intan_RHX')
        continue
    end

    root = strtrim(char(getpref('ep_RunExpt_Intan', 'RecordingRootDir', '')));
    if isempty(root)
        root = char(self.dfltDataPath);
        vprintf(0, ['No Intan Recording Path set (Customize > Paths); recording ' ...
            'under Data Save Path "%s"'], root)
    end

    % Setters normalize slashes and reject embedded spaces, so a bad path
    % fails here (before connect/timer) rather than mid-run.
    p.RecordingRootDir = root;
    p.SettingsFile = strtrim(char(getpref('ep_RunExpt_Intan', 'SettingsFile', '')));
end
