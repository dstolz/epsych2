function smoke_test_teensy_dialogs()
% smoke_test_teensy_dialogs()
% Verify that the TrialDesigner's modal editors actually go away when the user
% clicks OK or Cancel. A dialog that survives its own OK button leaves a modal
% window on screen that blocks the designer, so this checks the figure count
% before and after each editor rather than only the returned value.
%
%   matlab -batch "run('tmp/smoke_test_teensy_dialogs.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

PREF_GROUP = 'epsych2_teensy_TrialDesigner';
cleanupObj = onCleanup(@() cleanupAll(PREF_GROUP));

p = teensy.Templates.get("GoNoGoDetection");
d = teensy.TrialDesigner(p, Visible = false);

baseline = numel(findall(groot, 'Type', 'figure'));

% --- Action editor -------------------------------------------------------
out = clickAndWait_(@() d.editAction_(teensy.Action("Pulse")), 'Action', 'OK');
assert(~isempty(out), 'editAction_ should return the action when OK is clicked');
assertNoLeak_(baseline, 'editAction_ (OK)');

out = clickAndWait_(@() d.editAction_(teensy.Action("Pulse")), 'Action', 'Cancel');
assert(isempty(out), 'editAction_ should return [] when cancelled');
assertNoLeak_(baseline, 'editAction_ (Cancel)');
fprintf('PASS: action editor closes on OK and on Cancel\n');

% --- Condition builder ---------------------------------------------------
out = clickAndWait_(@() d.editCondition_(teensy.Condition.timerElapsed(), 1), ...
    'When should this transition fire?', 'OK');
assert(~isempty(out), 'editCondition_ should return the condition when OK is clicked');
assertNoLeak_(baseline, 'editCondition_ (OK)');

out = clickAndWait_(@() d.editCondition_(teensy.Condition.timerElapsed(), 1), ...
    'When should this transition fire?', 'Cancel');
assert(isempty(out), 'editCondition_ should return [] when cancelled');
assertNoLeak_(baseline, 'editCondition_ (Cancel)');
fprintf('PASS: condition builder closes on OK and on Cancel\n');

% --- Transition editor ---------------------------------------------------
t = teensy.Transition.to("Hit", teensy.Condition.timerElapsed());
out = clickAndWait_(@() d.editTransition_(t, 1), 'Transition', 'OK');
assert(~isempty(out), 'editTransition_ should return the transition when OK is clicked');
assertNoLeak_(baseline, 'editTransition_ (OK)');

out = clickAndWait_(@() d.editTransition_(t, 1), 'Transition', 'Cancel');
assert(isempty(out), 'editTransition_ should return [] when cancelled');
assertNoLeak_(baseline, 'editTransition_ (Cancel)');
fprintf('PASS: transition editor closes on OK and on Cancel\n');

delete(d);
fprintf('\nALL DIALOG SMOKE TESTS PASSED\n');
end


function out = clickAndWait_(fcn, dlgName, buttonText)
% out = clickAndWait_(fcn, dlgName, buttonText)
% Run a blocking modal editor and press one of its buttons from a timer.
t = timer(StartDelay = 1, ExecutionMode = 'singleShot', ...
    TimerFcn = @(~, ~) pressButton_(dlgName, buttonText));
start(t);
c = onCleanup(@() delete(t));
out = fcn();
end


function pressButton_(dlgName, buttonText)
% pressButton_(dlgName, buttonText)
% Find the named dialog and fire the named button's callback.
f = findall(groot, 'Type', 'figure', 'Name', dlgName);
if isempty(f)
    fprintf(2, 'FAIL: dialog "%s" never appeared\n', dlgName);
    return
end

b = findall(f(1), 'Type', 'uibutton', 'Text', buttonText);
if isempty(b)
    b = findall(f(1), '-property', 'ButtonPushedFcn');
    b = b(strcmp(get(b, 'Text'), buttonText));
end
assert(~isempty(b), 'no "%s" button in dialog "%s"', buttonText, dlgName);

fcn = b(1).ButtonPushedFcn;
fcn(b(1), []);
end


function assertNoLeak_(baseline, label)
% assertNoLeak_(baseline, label)
% Every dialog the editor opened must be gone by the time it returns.
open = findall(groot, 'Type', 'figure');
if numel(open) > baseline
    names = strjoin(string(get(open, 'Name')), ', ');
    error('smoke:dialogLeak', ...
        '%s left %d dialog(s) open: %s', label, numel(open) - baseline, names);
end
end


function cleanupAll(prefGroup)
% cleanupAll(prefGroup)
% Close everything and leave the user's preferences as they were.
delete(findall(groot, 'Type', 'figure'));
delete(timerfindall);
if ispref(prefGroup)
    rmpref(prefGroup);
end
end
