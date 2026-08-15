function LaunchUtility(self, target)
% LaunchUtility(self, target)
% Open one of the standalone EPsych tools listed in the Utilities menu.
%
% Parameters:
%	target	- Tool to open: "ProtocolDesigner", "TrialDesigner",
%			  "StimPlayer", "StimInspector", "Calibration", or
%			  "VideoConverter".
%
% Each tool owns its own window and lifecycle; RunExpt only launches it and
% keeps no handle. Always-on-top is cleared first so the new window does not
% open behind the session figure, and a launch failure is logged and reported
% on the status bar rather than thrown: a missing optional component (an
% unpopulated stimgen submodule, an absent peripheral package) must not
% disturb a loaded or running session.
%
% See also: epsych.ProtocolDesigner, teensy.TrialDesigner, stimgen.StimPlayer,
%           stimgen.StimInspector, epsych.calibrate, util.VideoConverter
arguments
    self
    target (1,1) string {mustBeMember(target, ...
        ["ProtocolDesigner","TrialDesigner","StimPlayer","StimInspector", ...
         "Calibration","VideoConverter"])}
end

switch target
    case "ProtocolDesigner", label = 'Protocol Designer';
    case "TrialDesigner",    label = 'Teensy Trial Designer';
    case "StimPlayer",       label = 'Stimulus Player';
    case "StimInspector",    label = 'Stimulus Inspector';
    case "Calibration",      label = 'Calibration GUI';
    case "VideoConverter",   label = 'Batch Video Converter';
end

self.AlwaysOnTop(false);

try
    switch target
        case "ProtocolDesigner"
            epsych.ProtocolDesigner;
        case "TrialDesigner"
            teensy.TrialDesigner;
        case "StimPlayer"
            % Seeded with a bare host, like epsych.calibrate does for the
            % calibration GUI: the player's File > Load Protocol menu and
            % calibrated-hardware output only work through an attached
            % stimgen.HardwareHost; without one it is speaker-preview only.
            stimgen.StimPlayer(stimbridge.RuntimeHost);
        case "StimInspector"
            stimgen.StimInspector;
        case "Calibration"
            epsych.calibrate;
        case "VideoConverter"
            % Seeded for the recorder's output -- the session's video root
            % (project, else the rig preference, else the data path) and the .ts the
            % recorder writes. Both are editable in the GUI. The setup GUI
            % holds the converter, so RunExpt does not have to.
            c = util.VideoConverter( ...
                RootFolder = string(videoConverterRoot_(self)), ...
                FilePattern = "(?i)\.ts$");
            c.setupGUI;
    end
catch ME
    vprintf(0,1,ME);
    self.setStatus(sprintf('Failed to open %s: %s',label,ME.message), ...
        'see Help > Open Current Error Log.');
    return
end

vprintf(1,'Opened %s from the Utilities menu.',label);
self.setStatus(sprintf('Opened %s.',label));

end

function root = videoConverterRoot_(self)
% Where StartVideoRecording_ writes, so the converter opens on the folder
% the recordings are actually in. Empty when neither is set, which the GUI
% shows as an unset root rather than an error.
root = strtrim(char(self.PATHS.VideoRootDir));
if isempty(root)
    root = char(self.DefaultDataPath);
end
if ~isfolder(root), root = ''; end
end
