function report = smoke_test_calibration_settings_close()
% report = smoke_test_calibration_settings_close()
% Smoke test: each stimgen.calibration.CalibrationGui settings window carries
% a Close button, and dismissing one keeps the values it applied.
%
% Verifies, for Excitation Settings, Hardware and Analysis Settings, and
% Conduction Delay Settings:
%   0) The window is modal, so the Close button is the way back to the GUI.
%   1) The window opens with exactly one Close button, in the last grid row.
%   2) A value typed into the window still reaches the engine (apply-on-
%      change is what the button does NOT replace).
%   3) Pressing Close deletes the window, leaves the applied value in place,
%      and lets the menu reopen it with that value shown.
%   4) Escape closes the window the same way.
%
% Only figures created by this test are closed.

report = struct();
report.timestamp = datetime('now');
report.steps = struct();

% The GUI snapshots its controls into StimCalibrationGui preferences when it
% closes, so this test would otherwise leave its own values remembered.
groupName = 'StimCalibrationGui';
hadPrefs = ispref(groupName);
savedPrefs = struct();
if hadPrefs
    savedPrefs = getpref(groupName);
end
restorePrefs = onCleanup(@() restore_prefs_(groupName, hadPrefs, savedPrefs)); %#ok<NASGU>

[gui, fig, closeFig] = open_gui_();
cleanupGui = onCleanup(@() cleanup_(gui, closeFig)); %#ok<NASGU>

% Step 1: Excitation Settings -- button present, value applied, Close works
stepName = 'excitationClose';
try
    dlg = open_settings_(fig, 'Excitation Settings...', 'Excitation Settings');
    assert(strcmp(dlg.WindowStyle, 'modal'), 'Window is not modal');
    btn = close_button_(dlg);
    assert(btn.Layout.Row == 3, 'Close button is not on the last row');

    fld = numeric_field_(dlg, 'Excitation Voltage (V)');
    set_field_(fld, 3.5);
    assert(abs(gui.Engine.ExcitationVoltage - 3.5) < 1e-9, ...
        'Excitation voltage did not reach the engine');

    press_(btn);
    assert(~isvalid(dlg), 'Close button did not dismiss the window');
    assert(abs(gui.Engine.ExcitationVoltage - 3.5) < 1e-9, ...
        'Close discarded the applied excitation voltage');

    dlg = open_settings_(fig, 'Excitation Settings...', 'Excitation Settings');
    fld = numeric_field_(dlg, 'Excitation Voltage (V)');
    assert(abs(fld.Value - 3.5) < 1e-9, 'Reopened window did not show the applied value');
    press_(close_button_(dlg));

    report.steps.(stepName) = struct('passed', true, 'detail', ...
        'Excitation Settings closes on its button and keeps the applied voltage.');
catch ME
    report.steps.(stepName) = fail_(ME);
end

% Step 2: Hardware and Analysis Settings
stepName = 'hardwareClose';
try
    dlg = open_settings_(fig, 'Hardware and Analysis Settings...', ...
        'Hardware and Analysis Settings');
    assert(strcmp(dlg.WindowStyle, 'modal'), 'Window is not modal');
    btn = close_button_(dlg);
    assert(btn.Layout.Row == 8, 'Close button is not on the last row');

    fld = numeric_field_(dlg, 'Max Output Voltage (V)');
    set_field_(fld, 7.5);
    assert(abs(gui.Engine.MaxOutputVoltage - 7.5) < 1e-9, ...
        'Max output voltage did not reach the engine');

    press_(btn);
    assert(~isvalid(dlg), 'Close button did not dismiss the window');
    assert(abs(gui.Engine.MaxOutputVoltage - 7.5) < 1e-9, ...
        'Close discarded the applied max output voltage');

    report.steps.(stepName) = struct('passed', true, 'detail', ...
        'Hardware and Analysis Settings closes on its button and keeps its value.');
catch ME
    report.steps.(stepName) = fail_(ME);
end

% Step 3: Conduction Delay Settings, closed with Escape
stepName = 'delayEscape';
try
    dlg = open_settings_(fig, 'Conduction Delay Settings...', ...
        'Conduction Delay Settings');
    assert(strcmp(dlg.WindowStyle, 'modal'), 'Window is not modal');
    btn = close_button_(dlg);
    assert(btn.Layout.Row == 6, 'Close button is not on the last row');

    fld = numeric_field_(dlg, 'Ambient Temperature (°F)');
    set_field_(fld, 68);
    assert(abs(gui.Engine.AmbientTemperature - 20) < 1e-6, ...
        'Ambient temperature did not reach the engine in Celsius');

    escape_(dlg);
    assert(~isvalid(dlg), 'Escape did not dismiss the window');
    assert(abs(gui.Engine.AmbientTemperature - 20) < 1e-6, ...
        'Escape discarded the applied ambient temperature');

    report.steps.(stepName) = struct('passed', true, 'detail', ...
        'Conduction Delay Settings closes on Escape and keeps its value.');
catch ME
    report.steps.(stepName) = fail_(ME);
end

stepNames = fieldnames(report.steps);
report.passed = all(cellfun(@(s) report.steps.(s).passed, stepNames));
end

% -------------------------------------------------------------------------
function [gui, fig, closeFig] = open_gui_()
% Construct the GUI and return a closer for the one figure it created, found
% by diffing the figure list so no pre-existing calibration window is touched.
before = findall(groot, 'Type', 'figure', 'Name', 'Stim Calibration');
gui = stimgen.calibration.CalibrationGui();
fig = setdiff(findall(groot, 'Type', 'figure', 'Name', 'Stim Calibration'), before);
assert(isscalar(fig), 'Expected exactly one new calibration window');
closeFig = @() close(fig);
end

% -------------------------------------------------------------------------
function dlg = open_settings_(fig, menuText, figName)
% Raise a settings window the way an operator does -- through its Options
% menu item -- since the handler behind it is private.
m = findall(fig, 'Type', 'uimenu', 'Text', menuText);
assert(isscalar(m), 'Menu item "%s" not found', menuText);
m.MenuSelectedFcn([], []);
dlg = findall(groot, 'Type', 'figure', 'Name', figName);
assert(isscalar(dlg), 'Settings window "%s" not found', figName);
end

% -------------------------------------------------------------------------
function btn = close_button_(dlg)
btn = findall(dlg, 'Type', 'uibutton', 'Text', 'Close');
assert(isscalar(btn), 'Expected exactly one Close button');
end

% -------------------------------------------------------------------------
function fld = numeric_field_(dlg, labelText)
% The field beside a caption: same grid row, the column the fields live in.
lbl = findall(dlg, 'Type', 'uilabel', 'Text', labelText);
assert(isscalar(lbl), 'Caption "%s" not found', labelText);
flds = findall(dlg, 'Type', 'uinumericeditfield');
fld = flds(arrayfun(@(f) f.Layout.Row == lbl.Layout.Row, flds));
assert(isscalar(fld), 'No field beside "%s"', labelText);
end

% -------------------------------------------------------------------------
function set_field_(fld, value)
% What a typed-and-committed value does: the field takes it, then its
% ValueChangedFcn runs. Assigning Value alone does not fire the callback.
fld.Value = value;
fld.ValueChangedFcn([], []);
end

% -------------------------------------------------------------------------
function press_(btn)
btn.ButtonPushedFcn([], []);
end

% -------------------------------------------------------------------------
function escape_(dlg)
dlg.WindowKeyPressFcn([], struct('Key', 'escape'));
end

% -------------------------------------------------------------------------
function cleanup_(gui, closeFig)
% A settings window left open by a failed step would be a MODAL window with
% nothing driving it, which blocks the desktop -- so this closes any that
% survived before it closes the GUI itself.
for name = ["Excitation Settings", "Hardware and Analysis Settings", ...
            "Conduction Delay Settings"]
    delete(findall(groot, 'Type', 'figure', 'Name', name));
end
closeFig();
delete(gui);
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
