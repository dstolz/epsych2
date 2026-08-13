function smoke_test_copy_filter_coefficients()
% smoke_test_copy_filter_coefficients()
% Verify the CalibrationGui "Copy Filter Coefficients" button: it is present,
% gated on a filter existing rather than on hardware, and puts the exact taps
% on the clipboard as plain one-per-line text.
%
% Only the figures this test creates are closed, and the user's clipboard is
% restored on the way out, so it is safe to run against a live session.
%
%   matlab -batch "cd('tmp'); smoke_test_copy_filter_coefficients"

epsych_startup

CAL_FILE = 'D:\epsych_files\Calibrations\Rig3_StimGenCal_260813.esgc';

preexisting = findall(groot, 'Type', 'figure');
try
    clipBefore = clipboard('paste');
catch
    clipBefore = '';
end
cleanupObj = onCleanup(@() restore_(preexisting, clipBefore));

% --- 1. No filter: button exists and is disabled ------------------------
before = findall(groot, 'Type', 'figure');
g = stimgen.calibration.CalibrationGui();
btn = find_button_(before, 'Copy Filter Coefficients');
assert(~isempty(btn), 'Copy Filter Coefficients button not found');
assert(strcmp(btn.Enable, 'off'), 'Button enabled with no filter designed');
assert(~isempty(btn.Tooltip), 'Button has no tooltip (missing tooltips.json entry)');
fprintf('PASS: button present and disabled with no filter\n');

% Pressing it anyway must report, not throw.
btn.ButtonPushedFcn([], []);
fprintf('PASS: press with no filter is a status message, not an error\n');

% --- 2. Filter loaded from file, no adapter attached --------------------
assert(exist(CAL_FILE, 'file') == 2, 'Calibration file not found: %s', CAL_FILE);
eng = stimgen.calibration.Engine.load(CAL_FILE);
C = eng.CalibrationData;
assert(isfield(C, 'filter') && ~isempty(C.filter), ...
    'Test calibration file holds no equalization filter -- design one and re-save.');

before = findall(groot, 'Type', 'figure');
g2 = stimgen.calibration.CalibrationGui(eng);
btn2 = find_button_(before, 'Copy Filter Coefficients');
assert(strcmp(btn2.Enable, 'on'), ...
    'Button disabled with a filter loaded and no adapter -- it should not need hardware');
fprintf('PASS: enabled by a loaded filter, with no adapter attached\n');

% --- 3. Clipboard content round-trips to the exact taps -----------------
btn2.ButtonPushedFcn([], []);
txt = clipboard('paste');
assert(~isempty(txt), 'Clipboard is empty after the copy');

b = tf(C.filter);
vals = sscanf(txt, '%f');
assert(numel(vals) == numel(b), ...
    'Copied %d values, filter has %d taps', numel(vals), numel(b));
assert(isequal(vals(:), b(:)), 'Copied coefficients do not round-trip exactly');

lines = strsplit(strtrim(regexprep(txt, '\r\n?', newline)), newline);
assert(numel(lines) == numel(b), 'Expected one coefficient per line');
assert(isempty(regexp(txt, '[^0-9eE+\-.\r\n]', 'once')), ...
    'Clipboard text contains non-numeric characters -- it must paste as a bare column');
fprintf('PASS: %d taps copied, exact round-trip, numeric-only text\n', numel(b));

assert(isvalid(g) && isvalid(g2), 'A GUI died during the test');
fprintf('\nAll copy-filter-coefficients smoke tests passed\n');
end

% ------------------------------------------------------------------------
function btn = find_button_(figsBefore, labelText)
% The GUI keeps its Figure handle private, so the window just constructed is
% identified as the one that was not there a moment ago.
fig = setdiff(findall(groot, 'Type', 'figure'), figsBefore);
assert(~isempty(fig), 'No new figure was created');
btn = findall(fig, 'Type', 'uibutton', 'Text', labelText);
if numel(btn) > 1, btn = btn(1); end
end

function restore_(preexisting, clipBefore)
delete(setdiff(findall(groot, 'Type', 'figure'), preexisting));
try
    clipboard('copy', clipBefore);
catch
end
end
