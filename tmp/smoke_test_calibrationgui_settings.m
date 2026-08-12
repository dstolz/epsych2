function report = smoke_test_calibrationgui_settings()
% report = smoke_test_calibrationgui_settings()
% Smoke test: stimgen.calibration.CalibrationGui remembers settings across
% sessions via StimCalibrationGui preferences.
%
% Verifies:
%   1) Fresh-engine construction restores remembered engine settings and
%      display options (spectrum unit, weighting overlays, transfer log X).
%   2) A supplied engine's non-default values win over remembered ones,
%      while its still-default fields are restored from preferences.
%   3) Closing the window snapshots the current control values back to
%      preferences, and a new window restores them (full round trip).
%
% The real StimCalibrationGui preference group is saved on entry and put
% back on exit, so running this does not disturb remembered settings. Only
% figures created by this test are closed.

report = struct();
report.timestamp = datetime('now');
report.steps = struct();

groupName = 'StimCalibrationGui';
savedPrefs = struct();
hadPrefs = ispref(groupName);
if hadPrefs
    savedPrefs = getpref(groupName);
end
restorePrefs = onCleanup(@() restore_prefs_(groupName, hadPrefs, savedPrefs)); %#ok<NASGU>

% Step 1: fresh engine restores remembered settings and display options
stepName = 'restoreFreshEngine';
try
    clear_prefs_(groupName);
    setpref(groupName, 'ReferenceLevel', '114');
    setpref(groupName, 'ExcitationVoltage', '0.5');
    setpref(groupName, 'AcCoupleResponse', '1');
    setpref(groupName, 'ToneLutSource', 'swept_sine');
    setpref(groupName, 'transferLogX', '0');
    setpref(groupName, 'spectrumUnits', 'dBV');
    setpref(groupName, 'weightingOverlays', 'A,C');

    [gui, closeFig] = open_gui_();
    assert(gui.Engine.ReferenceLevel == 114, 'ReferenceLevel not restored');
    assert(gui.Engine.ExcitationVoltage == 0.5, 'ExcitationVoltage not restored');
    assert(gui.Engine.AcCoupleResponse, 'AcCoupleResponse not restored');
    assert(gui.Engine.ToneLutSource == "swept_sine", 'ToneLutSource not restored');
    assert(~gui.Monitor.LogX, 'Transfer log X not restored');
    assert(gui.Monitor.SpectrumUnits == "dBV", 'Spectrum unit not restored');
    assert(isequal(gui.Monitor.Weightings, ["A" "C"]), 'Weighting overlays not restored');
    closeFig();
    delete(gui);
    report.steps.(stepName) = struct('passed', true, 'detail', ...
        'Fresh-engine construction restored engine settings and display options.');
catch ME
    report.steps.(stepName) = fail_(ME);
end

% Step 2: supplied engine's non-default values win over remembered ones
stepName = 'suppliedEngineWins';
try
    clear_prefs_(groupName);
    setpref(groupName, 'ReferenceLevel', '114');
    setpref(groupName, 'ExcitationVoltage', '0.5');

    eng = stimgen.calibration.Engine();
    eng.set_configuration(ReferenceLevel=100);
    [gui, closeFig] = open_gui_(eng);
    assert(gui.Engine.ReferenceLevel == 100, ...
        'Remembered value overrode the supplied engine''s ReferenceLevel');
    assert(gui.Engine.ExcitationVoltage == 0.5, ...
        'Still-default ExcitationVoltage was not restored');
    closeFig();
    delete(gui);
    report.steps.(stepName) = struct('passed', true, 'detail', ...
        'Supplied engine values won; untouched fields still restored.');
catch ME
    report.steps.(stepName) = fail_(ME);
end

% Step 3: close snapshots settings; a new window restores them
stepName = 'saveOnCloseRoundTrip';
try
    clear_prefs_(groupName);
    eng = stimgen.calibration.Engine();
    eng.set_configuration(ReferenceLevel=123, MaxOutputVoltage=7);
    [gui, closeFig] = open_gui_(eng);
    closeFig();
    delete(gui);
    assert(strcmp(getpref(groupName, 'ReferenceLevel'), '123'), ...
        'ReferenceLevel not saved on close');
    assert(strcmp(getpref(groupName, 'MaxOutputVoltage'), '7'), ...
        'MaxOutputVoltage not saved on close');
    assert(ispref(groupName, 'spectrumUnits'), 'Display settings not saved on close');

    [gui, closeFig] = open_gui_();
    assert(gui.Engine.ReferenceLevel == 123, 'Round trip lost ReferenceLevel');
    assert(gui.Engine.MaxOutputVoltage == 7, 'Round trip lost MaxOutputVoltage');
    closeFig();
    delete(gui);
    report.steps.(stepName) = struct('passed', true, 'detail', ...
        'Close wrote preferences; new window restored them.');
catch ME
    report.steps.(stepName) = fail_(ME);
end

stepNames = fieldnames(report.steps);
report.passed = all(cellfun(@(s) report.steps.(s).passed, stepNames));
end

% -------------------------------------------------------------------------
function [gui, closeFig] = open_gui_(varargin)
% Construct the GUI and return a closer for the one figure it created, found
% by diffing the figure list so no pre-existing calibration window is touched.
before = findall(groot, 'Type', 'figure', 'Name', 'Stim Calibration');
gui = stimgen.calibration.CalibrationGui(varargin{:});
created = setdiff(findall(groot, 'Type', 'figure', 'Name', 'Stim Calibration'), before);
closeFig = @() close(created);
end

% -------------------------------------------------------------------------
function clear_prefs_(groupName)
if ispref(groupName)
    rmpref(groupName);
end
end

% -------------------------------------------------------------------------
function restore_prefs_(groupName, hadPrefs, savedPrefs)
if ispref(groupName)
    rmpref(groupName);
end
if hadPrefs
    for f = fieldnames(savedPrefs).'
        setpref(groupName, f{1}, savedPrefs.(f{1}));
    end
end
end

% -------------------------------------------------------------------------
function s = fail_(ME)
s = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end
