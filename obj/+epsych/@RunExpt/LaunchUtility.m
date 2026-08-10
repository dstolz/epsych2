function LaunchUtility(self, target)
% LaunchUtility(self, target)
% Open one of the standalone EPsych tools listed in the Utilities menu.
%
% Parameters:
%	target	- Tool to open: "ProtocolDesigner", "TrialDesigner",
%			  "StimPlayer", "StimInspector", or "Calibration".
%
% Each tool owns its own window and lifecycle; RunExpt only launches it and
% keeps no handle. Always-on-top is cleared first so the new window does not
% open behind the session figure, and a launch failure is logged and reported
% on the status bar rather than thrown: a missing optional component (an
% unpopulated stimgen submodule, an absent peripheral package) must not
% disturb a loaded or running session.
%
% See also: epsych.ProtocolDesigner, teensy.TrialDesigner, stimgen.StimPlayer,
%           stimgen.StimInspector, epsych.calibrate
arguments
    self
    target (1,1) string {mustBeMember(target, ...
        ["ProtocolDesigner","TrialDesigner","StimPlayer","StimInspector","Calibration"])}
end

switch target
    case "ProtocolDesigner", label = 'Protocol Designer';
    case "TrialDesigner",    label = 'Teensy Trial Designer';
    case "StimPlayer",       label = 'Stimulus Player';
    case "StimInspector",    label = 'Stimulus Inspector';
    case "Calibration",      label = 'Calibration GUI';
end

self.AlwaysOnTop(false);

try
    switch target
        case "ProtocolDesigner"
            epsych.ProtocolDesigner;
        case "TrialDesigner"
            teensy.TrialDesigner;
        case "StimPlayer"
            stimgen.StimPlayer;
        case "StimInspector"
            stimgen.StimInspector;
        case "Calibration"
            epsych.calibrate;
    end
catch ME
    vprintf(0,1,ME);
    self.setStatus(sprintf('Failed to open %s: %s',label,ME.message), ...
        'see Help > Open Current Error Log.');
    return
end

vprintf(1,'Opened %s from the Utilities menu.',label);
self.setStatus(sprintf('Opened %s.',label));
