function report = smoke_test_calibration_notes()
% report = smoke_test_calibration_notes()
% Smoke test: the CalibrationGui Notes box and File > Print Calibration
% Summary, and the Engine.Notes/Engine.describe they stand on.
%
% What this covers, and why each part is worth a test:
%
%   1. The box exists at the bottom of the controls column, in its own
%      Notes section, and starts empty on a fresh engine.
%   2. Typing into it reaches the Engine -- the box is a view of
%      Engine.Notes, not a place text sits until someone saves.
%   3. A save/load round trip brings the text back, which is the entire
%      point: a note about Tuesday's calibration is worthless if it does
%      not come back with Tuesday's tables.
%   4. Reset Calibration leaves the text alone. It is the operator's
%      words, and discarding measurements does not make them wrong.
%   5. Notes are NOT remembered as a window preference: a note must not
%      follow the window onto the next rig's calibration.
%   6. File > Print Calibration Summary prints Engine.describe, and
%      describe returns the same text when an output is taken.
%
% Only figures created by this test are closed.
%
% Run under the MATLAB MCP server or matlab -batch:
%
%   matlab -batch "cd('tmp'); smoke_test_calibration_notes"

thisDir = fileparts(mfilename('fullpath'));
run(fullfile(thisDir, '..', 'epsych_startup.m'));

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
restorePrefs = onCleanup(@() restore_prefs_(groupName, hadPrefs, savedPrefs));

ffn = fullfile(tempdir, 'smoke_test_calibration_notes.esgc');
cleanFile = onCleanup(@() delete_quietly_(ffn));

noteText = {'Rig B, ES1 at 10 cm on axis.'; 'Mic 4939, grid off.'};

[gui, fig, closeFig] = open_gui_();
cleanupGui = onCleanup(@() cleanup_(gui, closeFig));

% Step 1: the box is there, in its own section, and starts empty.
stepName = 'boxPresent';
try
    area = notes_area_(fig);
    panel = ancestor(area, 'uipanel');
    assert(strcmp(panel.Title, 'Notes'), ...
        'Notes box is not in a section titled Notes (found "%s")', panel.Title);
    assert(strcmp(strjoin(area.Value, ''), ''), 'Notes box did not start empty');
    assert(~isempty(area.Tooltip), 'Notes box has no tooltip');

    report.steps.(stepName) = struct('passed', true, 'detail', ...
        'Notes box present in its own section and empty on a fresh engine.');
catch ME
    report.steps.(stepName) = fail_(ME);
end

% Step 2: what is typed reaches the engine.
stepName = 'reachesEngine';
try
    area = notes_area_(fig);
    set_notes_(area, noteText);
    assert(gui.Engine.Notes == string(strjoin(noteText, newline)), ...
        'Typed notes did not reach the engine');

    report.steps.(stepName) = struct('passed', true, 'detail', ...
        'Editing the box writes Engine.Notes.');
catch ME
    report.steps.(stepName) = fail_(ME);
end

% Step 3: the notes travel in the .esgc and come back in the box.
stepName = 'roundTrip';
try
    % A save needs something saveable, so give the engine a minimal table.
    gui.Engine.restore(struct( ...
        'CalibrationData', fake_calibration_data_(), ...
        'CalibrationTimestamp', datetime('now')));
    gui.Engine.save(ffn);

    loaded = stimgen.calibration.Engine.load(ffn);
    assert(loaded.Notes == gui.Engine.Notes, 'Notes did not survive save/load');

    [gui2, fig2, closeFig2] = open_gui_(loaded);
    area2 = notes_area_(fig2);
    assert(isequal(area2.Value(:), noteText), ...
        'A loaded calibration did not put its notes back in the box');
    closeFig2();
    delete(gui2);

    report.steps.(stepName) = struct('passed', true, 'detail', ...
        'Notes survive the .esgc and are shown by a window opened on it.');
catch ME
    report.steps.(stepName) = fail_(ME);
end

% Step 4: a reset discards measurements, not words.
stepName = 'resetKeepsNotes';
try
    gui.Engine.reset_calibration();
    assert(~gui.Engine.IsCalibrated, 'Reset did not clear the calibration data');
    assert(gui.Engine.Notes == string(strjoin(noteText, newline)), ...
        'Reset cleared the notes');

    report.steps.(stepName) = struct('passed', true, 'detail', ...
        'reset_calibration leaves Notes in place.');
catch ME
    report.steps.(stepName) = fail_(ME);
end

% Step 5: describe() prints, and returns the same text on request.
stepName = 'describeAndMenu';
try
    txt = gui.Engine.describe();
    assert(isstring(txt) && isscalar(txt), 'describe did not return one string');
    assert(contains(txt, noteText{1}), 'describe left the notes out');
    assert(contains(txt, 'Stim calibration'), 'describe has no header');

    printed = evalc('gui.Engine.describe()');
    assert(contains(printed, noteText{2}), 'describe printed nothing useful');

    m = findall(fig, 'Type', 'uimenu', 'Text', 'Print Calibration Summary');
    assert(isscalar(m), 'File > Print Calibration Summary not found');
    fromMenu = evalc('m.MenuSelectedFcn([], [])');
    assert(contains(fromMenu, 'Stim calibration'), ...
        'The menu item printed no summary');

    report.steps.(stepName) = struct('passed', true, 'detail', ...
        'describe prints and returns; the File menu item prints the same thing.');
catch ME
    report.steps.(stepName) = fail_(ME);
end

% Step 6: notes are not a window preference.
stepName = 'notAPreference';
try
    closeFig();
    delete(gui);
    prefs = {};
    if ispref(groupName)
        prefs = fieldnames(getpref(groupName));
    end
    assert(~any(strcmpi(prefs, 'Notes')), ...
        'Closing the window remembered the notes as a preference');

    % Its own handles, and closed here: the cleanup above holds the window
    % this step just closed, and would leave this one open.
    [gui3, fig3, closeFig3] = open_gui_();
    area = notes_area_(fig3);
    isEmpty = strcmp(strjoin(area.Value, ''), '');
    closeFig3();
    delete(gui3);
    assert(isEmpty, 'A new window inherited the previous calibration''s notes');

    report.steps.(stepName) = struct('passed', true, 'detail', ...
        'Notes belong to the calibration, not to the window.');
catch ME
    report.steps.(stepName) = fail_(ME);
end

stepNames = fieldnames(report.steps);
report.passed = all(cellfun(@(s) report.steps.(s).passed, stepNames));

for k = 1:numel(stepNames)
    s = report.steps.(stepNames{k});
    if s.passed
        fprintf('PASS: %s -- %s\n', stepNames{k}, s.detail);
    else
        fprintf('FAIL: %s -- %s\n', stepNames{k}, s.detail);
    end
end
end

% -------------------------------------------------------------------------
function [gui, fig, closeFig] = open_gui_(eng)
% Construct the GUI and return a closer for the one figure it created, found
% by diffing the figure list so no pre-existing calibration window is touched.
arguments
    eng = stimgen.calibration.Engine()
end
before = findall(groot, 'Type', 'figure', 'Name', 'Stim Calibration');
gui = stimgen.calibration.CalibrationGui(eng);
fig = setdiff(findall(groot, 'Type', 'figure', 'Name', 'Stim Calibration'), before);
assert(isscalar(fig), 'Expected exactly one new calibration window');
closeFig = @() close(fig);
end

% -------------------------------------------------------------------------
function area = notes_area_(fig)
areas = findall(fig, 'Type', 'uitextarea');
assert(isscalar(areas), 'Expected exactly one text area in the window');
area = areas;
end

% -------------------------------------------------------------------------
function set_notes_(area, lines)
% What typing and clicking away does: the box takes the text, then its
% ValueChangedFcn runs. Assigning Value alone does not fire the callback.
area.Value = lines;
area.ValueChangedFcn([], []);
end

% -------------------------------------------------------------------------
function calData = fake_calibration_data_()
% The smallest thing Engine.save will accept: one tone point. Nothing here
% reads it back -- this test is about the notes riding alongside it.
calData = struct('filter', [], 'filterGrpDelay', 0);
calData.tone = struct('frequency', 1000, 'measurement', 0.1, ...
    'spl_db', 70, 'voltage', 0.5);
end

% -------------------------------------------------------------------------
function cleanup_(gui, closeFig)
% Tolerant of a window a step already closed: step 6 has to close the first
% GUI itself to see what it wrote to preferences.
try
    closeFig();
catch
end
if isvalid(gui)
    delete(gui);
end
end

% -------------------------------------------------------------------------
function delete_quietly_(ffn)
if isfile(ffn)
    delete(ffn);
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
