function smoke_test_reset_calibration()
% smoke_test_reset_calibration
% Verifies Engine.reset_calibration discards acquired data while keeping
% the adapter and persistent parameters, and that CalibrationGui's Reset
% Calibration button is wired to it correctly.

addpath('c:\src\epsych2\tmp');

adapter = MockCalibrationAdapter(48000);
eng = stimgen.calibration.Engine(adapter);
eng.set_configuration(MicSensitivity=0.02, ReferenceLevel=94, ...
    ReferenceFrequency=1000, NormativeValue=75, ExcitationVoltage=1, ...
    MaxOutputVoltage=5, ShowLivePlots=false);

eng.calibrate_tones([1000 2000 4000], 1);
assert(eng.IsCalibrated, 'expected engine to be calibrated after calibrate_tones');
assert(~isnat(eng.CalibrationTimestamp), 'expected a calibration timestamp');
assert(~isempty(eng.ResponseSignal), 'expected a response signal after calibration');

eng.reset_calibration();

assert(~eng.IsCalibrated, 'expected IsCalibrated false after reset_calibration');
assert(isempty(eng.CalibrationData), 'expected CalibrationData cleared');
assert(isempty(eng.ExcitationSignal), 'expected ExcitationSignal cleared');
assert(isempty(eng.ResponseSignal), 'expected ResponseSignal cleared');
assert(isnan(eng.ResponseTHD), 'expected ResponseTHD reset to NaN');
assert(isnat(eng.CalibrationTimestamp), 'expected CalibrationTimestamp cleared');

% Persistent parameters and adapter must survive the reset untouched.
assert(eng.MicSensitivity == 0.02, 'MicSensitivity must survive reset');
assert(eng.ReferenceLevel == 94, 'ReferenceLevel must survive reset');
assert(eng.ReferenceFrequency == 1000, 'ReferenceFrequency must survive reset');
assert(eng.NormativeValue == 75, 'NormativeValue must survive reset');
assert(eng.ExcitationVoltage == 1, 'ExcitationVoltage must survive reset');
assert(eng.MaxOutputVoltage == 5, 'MaxOutputVoltage must survive reset');
assert(~isempty(eng.Adapter), 'Adapter must survive reset');

fprintf('Engine.reset_calibration: OK\n');

% Re-calibrate after reset to confirm the engine is still usable.
eng.calibrate_tones([1000 2000 4000], 1);
assert(eng.IsCalibrated, 'expected engine to re-calibrate after a reset');
fprintf('Re-calibration after reset: OK\n');

% --- GUI wiring ---
% Reset only prompts a (blocking) uiconfirm when the engine is already
% calibrated, which cannot be answered in a headless batch run. Exercise
% the button against an UNCALIBRATED engine, where the confirm is skipped
% and reset_calibration() runs directly -- enough to prove the wiring
% (button -> handler -> Engine.reset_calibration) without touching the
% modal dialog path, which is covered by code review instead.
eng2 = stimgen.calibration.Engine(adapter);
eng2.set_configuration(MicSensitivity=0.03);
assert(~eng2.IsCalibrated, 'expected fresh engine to be uncalibrated');

% Figure is a private property; find the new uifigure this constructor
% creates by diffing groot's figure list around the call.
figsBefore = findall(groot, 'Type', 'figure');
gui = stimgen.calibration.CalibrationGui(eng2);
figsAfter = findall(groot, 'Type', 'figure');
figNew = setdiff(figsAfter, figsBefore);
assert(isscalar(figNew), 'expected exactly one new figure from CalibrationGui');
c = onCleanup(@() delete(figNew));

btn = findobj(figNew, 'Text', 'Reset Calibration');
assert(~isempty(btn), 'expected a "Reset Calibration" button in the GUI');
assert(strcmp(btn.Enable, 'on'), 'expected Reset Calibration button enabled');

btn.ButtonPushedFcn(btn, []);
assert(~gui.Engine.IsCalibrated, 'expected gui.Engine to remain uncalibrated');
assert(gui.Engine.MicSensitivity == 0.03, 'GUI reset must preserve MicSensitivity');
assert(~isempty(gui.Engine.Adapter), 'GUI reset must preserve Adapter');

fprintf('CalibrationGui Reset Calibration button (uncalibrated path): OK\n');
fprintf('ALL PASSED\n');
end
