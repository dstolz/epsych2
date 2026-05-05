function open_calibration_gui(obj)
% open_calibration_gui(obj)
% Launch the stimgen calibration GUI from StimPlayer.
%
% Opens stimgen.calibration.CalibrationGui in a separate window. If
% StimPlayer does not currently have hardware resolved, this method also
% shows an informational message explaining how to attach hardware in the
% calibration GUI.

try
    stimgen.calibration.CalibrationGui();
    obj.show_gui_message_( ...
        "Calibration GUI opened. Initialize hardware there using File > Initialize Runtime From Protocol....", ...
        "Calibration GUI", "info");
catch ME
    obj.report_gui_error_(ME, "Calibration GUI Error", ...
        "StimPlayer could not open the calibration GUI.");
end
end
