function gui = calibrate(protocolInput)
% gui = epsych.calibrate()
% gui = epsych.calibrate(protocolInput)
%
% Launch the stimgen calibration GUI wired to EPsych hardware.
%
% Creates the stimbridge.RuntimeHost seam and the calibration engine so the
% caller does not have to. Without a protocol the GUI opens with the host
% attached but no hardware: use File > Initialize Runtime From Protocol... to
% connect, or Hardware > Attach Adapter to borrow a live session's RUNTIME.
% With a protocol the runtime is loaded, connected, and placed in Preview
% before the window appears.
%
% Parameters:
%   protocolInput - epsych.Protocol object or protocol filepath (optional)
%
% Returns:
%   gui - stimgen.calibration.CalibrationGui handle
%
% Example:
%   epsych.calibrate
%   epsych.calibrate('MyExperiment.eprot')
%
% See also: stimbridge.RuntimeHost, stimgen.calibration.CalibrationGui,
%           stimgen.StimPlayer

host = stimbridge.RuntimeHost;

if nargin > 0 && ~isempty(protocolInput)
    % A failed connect must not swallow the window; the GUI's runtime menu
    % is the natural place to retry.
    try
        host.loadProtocol(protocolInput);
        host.connect;
        host.setMode("Preview");
    catch ME
        vprintf(0, 1, 'epsych.calibrate: could not initialize runtime from protocol.');
        vprintf(0, 1, ME);
    end
end

gui = stimgen.calibration.CalibrationGui(stimgen.calibration.Engine(),host);

if host.connectionState == "Ready"
    try
        gui.set_adapter(host.calibrationAdapter);
    catch ME
        vprintf(0, 1, 'epsych.calibrate: connected, but no interface could supply a calibration adapter.');
        vprintf(0, 1, ME);
    end
end

if nargout == 0
    clear gui
end
