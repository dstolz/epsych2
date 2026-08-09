function configureIntanRecorder_(self, interfaces)
% configureIntanRecorder_(self, interfaces)
% Seed every hw.Intan_RHX in the given interface array before the interfaces
% connect. The settings file is loaded inside setup_interface (during
% connect), so per-machine values must be on the object first — this is
% called just before RUNTIME.Interfaces is assigned in ExptDispatch, whose
% setter connects.
%
% This keeps getpref out of obj/+hw/ (the hardware layer is pref-free),
% mirroring how getVlcRecorder_ seeds the webcam recorder.
%
% Precedence:
%   RecordingRootDir is per-machine and always comes from the
%   'ep_RunExpt_Intan' preference group (or the default data path).
%   SettingsFile is now protocol-level (see hw.Intan_RHX.getCreationSpec):
%   the value carried by the .eprot wins, and the machine pref is used only
%   as a fallback when the protocol left it unset. SamplingRate and
%   ControllerType are protocol-level and are left untouched here.
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

    % Honor a protocol-configured settings file; fall back to the per-machine
    % pref only when the protocol did not specify one.
    if isempty(strtrim(p.SettingsFile))
        p.SettingsFile = strtrim(char(getpref('ep_RunExpt_Intan', 'SettingsFile', '')));
    end
end
