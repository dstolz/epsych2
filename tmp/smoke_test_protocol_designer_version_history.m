function smoke_test_protocol_designer_version_history()
% smoke_test_protocol_designer_version_history()
% File > Version History... must be GONE by the time anything it leads to opens.
%
% The dialog is a modal uifigure answered through uiwait. Its first version used
% nested functions for its callbacks, so the figure's callback handles kept the
% enclosing workspace alive, and with it the onCleanup that deletes the window:
% pressing Restore... left Version History on screen, still modal, and the
% Restore Version uiconfirm opened in the designer BEHIND it, with no way to
% reach it. This drives the dialog the way an operator does and checks, at the
% moment each follow-on window would open, that no Version History window is left.
%
% Blocks in uiwait and is answered from timers, so run it with -batch (a
% persistent MCP session is corrupted by an aborted uiwait):
%
%   matlab -batch "cd('tmp'); smoke_test_protocol_designer_version_history"
%
% See also: epsych.ProtocolDesigner.onVersionHistory, gui.compareProtocolVersions,
%   documentation/design/ProtocolDesigner.md

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(repoRoot);
epsych_startup

root = fullfile(tempdir, 'epsych_pd_version_history_smoke');
if isfolder(root)
    rmdir(root, 's');
end
mkdir(root);
cleanupDir = onCleanup(@() localRemoveDir(root));

% A protocol with a plain parameter and no constant Expressions, so loading it
% does not mark the designer modified and Restore goes straight to its prompt.
f = fullfile(root, 'history.eprot');
P = epsych.Protocol;
P.addParameter('Software', 'Depth', 0);
P.Info = 'first content';  P.save(f);
P.Info = 'second content'; P.save(f);
P.Info = 'third content';  P.save(f);
assert(numel(epsych.Protocol.listVersions(f)) == 3, 'fixture should hold three versions');

failures = {};
pd = [];
steps = {};
stepIdx = 1;
driverError = '';
compareSeen = false;
leakedAtFollowOn = [];
cleanupPd = onCleanup(@() localForceClose(pd));

% This test puts real windows on a real screen and blocks on them. If anything
% goes wrong it must not leave one waiting for a person, so a watchdog removes
% every window the test can own, designer included, whatever state it is in.
watchdog = timer(ExecutionMode = 'singleShot', StartDelay = 120, ...
    Name = 'versionHistoryWatchdog', ...
    TimerFcn = @(~, ~) abandon());
cleanupWatchdog = onCleanup(@() delete(watchdog));
start(watchdog);

% A. Cancel leaves nothing behind -------------------------------------------
try
    pd = epsych.ProtocolDesigner(f);
    runSteps({@() answerDialog(1, 'Cancel')});
    pd.onVersionHistory();
    finish();
    assert(isempty(localFind('Version History -')), 'Cancel left the dialog on screen');
    fprintf('PASS: A. Cancel closes the dialog\n');
catch ME
    failures{end+1} = sprintf('A. %s', ME.message);
    fprintf('FAIL: A. %s\n%s\n', ME.message, getReport(ME));
end
localForceClose(pd);

% B. Open Copy returns with the dialog gone ----------------------------------
try
    pd = epsych.ProtocolDesigner(f);
    runSteps({@() answerDialog(2, 'Open Copy')});
    pd.onVersionHistory();
    finish();
    assert(isempty(localFind('Version History -')), 'Open Copy left the dialog on screen');
    s = localState(pd);
    assert(contains(s.Figure.Name, 'archived copy'), ...
        'Open Copy should have loaded the archived version, title was "%s"', s.Figure.Name);
    fprintf('PASS: B. Open Copy closes the dialog and loads the version\n');
catch ME
    failures{end+1} = sprintf('B. %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end
localForceClose(pd);

% C. Restore: the dialog is gone before the Restore Version prompt ------------
% This is the reported bug. The confirmation blocks, so a second step looks at
% the screen while it is up and then deletes the designer to let the call end.
try
    pd = epsych.ProtocolDesigner(f);
    leakedAtFollowOn = [];
    runSteps({@() answerDialog(2, 'Restore...'), @() inspectThenAbandon()});
    try
        pd.onVersionHistory();
    catch
        % Deleting the designer under the open uiconfirm may end the call with
        % an error; what matters is what the screen held while it was up.
    end
    finish();
    assert(~isempty(leakedAtFollowOn), 'the Restore Version prompt was never reached');
    assert(~leakedAtFollowOn, ...
        'Version History was still on screen when the Restore Version prompt opened');
    fprintf('PASS: C. Restore closes Version History before the confirmation opens\n');
catch ME
    failures{end+1} = sprintf('C. %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end
localForceClose(pd);
localDeleteLeftovers();

% D. Show Changes is still wired, and the Protocol Changes window closes cleanly
% The button is checked, not clicked: a click blocks in the comparison window's
% uiwait INSIDE the timer callback that made it, so no second timer can ever
% answer it and the window would sit there waiting for a person. The comparison
% window is opened from the main thread instead, where a timer can close it.
try
    pd = epsych.ProtocolDesigner(f);
    wiredOk = false;
    runSteps({@() checkCompareWired(), @() answerDialog(1, 'Cancel')});
    pd.onVersionHistory();
    finish();
    assert(wiredOk, 'Show Changes has no callback, or is disabled with other versions present');
    assert(isempty(localFind('Version History -')), 'dialog left on screen after Cancel');

    idx = epsych.Protocol.listVersions(f);
    compareSeen = false;
    runSteps({@() closeCompare()});
    s = localState(pd);
    gui.compareProtocolVersions(s.Figure, ...
        struct('File', f, 'Version', idx(3).Version), ...
        struct('File', f, 'Version', idx(1).Version), ...
        Name = 'Protocol Changes - history.eprot');
    finish();
    assert(compareSeen, 'the comparison window never reached a state it could be answered in');
    assert(isempty(localFind('Protocol Changes -')), 'comparison window left on screen after Close');
    fprintf('PASS: D. Show Changes is wired and the comparison window closes\n');
catch ME
    failures{end+1} = sprintf('D. %s', ME.message);
    fprintf('FAIL: D. %s\n%s\n', ME.message, getReport(ME));
end
localForceClose(pd);
localDeleteLeftovers();

if ~isempty(failures)
    error('smoke_test_protocol_designer_version_history:failed', ...
        '%d group(s) failed:\n  %s', numel(failures), strjoin(failures, newline + "  "));
end
fprintf('smoke_test_protocol_designer_version_history: all groups passed\n');

    % ----- timer driver (nested: shares the step list and flags) -------------
    function runSteps(list)
        steps = list;
        stepIdx = 1;
        driverError = '';
        driverTimer = timer(ExecutionMode = 'fixedSpacing', Period = 0.3, ...
            StartDelay = 0.3, TasksToExecute = 200, Name = 'versionHistoryDriver', ...
            TimerFcn = @(src, ~) tick(src));
        % Kept where finish() can reach it; the test is single-threaded.
        setappdata(0, 'versionHistoryDriver', driverTimer);
        start(driverTimer);
    end

    function finish()
        driverTimer = getappdata(0, 'versionHistoryDriver');
        if ~isempty(driverTimer) && isvalid(driverTimer)
            stop(driverTimer);
            delete(driverTimer);
        end
        if isappdata(0, 'versionHistoryDriver')
            rmappdata(0, 'versionHistoryDriver');
        end
        assert(isempty(driverError), 'dialog driver failed: %s', driverError);
    end

    function tick(src)
        if stepIdx > numel(steps)
            stop(src);
            return
        end
        try
            done = steps{stepIdx}();
        catch ME
            driverError = ME.message;
            stop(src);
            localDeleteLeftovers();   % never leave the test blocked in uiwait
            localForceClose(pd);
            return
        end
        if done
            stepIdx = stepIdx + 1;
        end
    end

    function done = answerDialog(row, buttonText)
        d = localFindReady('Version History -');
        done = ~isempty(d);
        if ~done, return, end
        lst = findall(d, 'Type', 'uilistbox');
        lst.Value = row;
        feval(lst.ValueChangedFcn, lst, []);
        localClick(d, buttonText);
    end

    function done = inspectThenAbandon()
        % Reached on the tick after Restore... was pressed; the call is then
        % blocked in the Restore Version uiconfirm on the designer.
        leakedAtFollowOn = ~isempty(localFind('Version History -'));
        localDeleteLeftovers();
        localForceClose(pd);
        done = true;
    end

    function abandon()
        localDeleteLeftovers();
        localForceClose(pd);
    end

    function done = checkCompareWired()
        d = localFindReady('Version History -');
        done = ~isempty(d);
        if ~done, return, end
        b = findall(d, '-isa', 'matlab.ui.control.Button', 'Text', 'Show Changes...');
        wiredOk = isscalar(b) && isa(b.ButtonPushedFcn, 'function_handle') ...
            && strcmp(char(b.Enable), 'on');
    end

    function done = closeCompare()
        c = localFindReady('Protocol Changes -');
        done = ~isempty(c);
        if ~done, return, end
        compareSeen = true;
        localClick(c, 'Close');
    end
end


function f = localFind(prefix)
figs = findall(groot, 'Type', 'figure');
if isempty(figs)
    f = [];
    return
end
f = figs(startsWith(string({figs.Name}), prefix));
if ~isempty(f), f = f(1); end
end


function f = localFindReady(prefix)
% Building a uifigure yields, so a timer can meet a window whose widgets are not
% all made and wired yet. Both dialogs replace CloseRequestFcn (a new uifigure
% carries the char 'closereq') with a function handle as the last step before
% they block, which is what "ready to be answered" means here.
f = localFind(prefix);
if ~isempty(f) && ~isa(f.CloseRequestFcn, 'function_handle')
    f = [];
end
end


function localClick(fig, text)
b = findall(fig, '-isa', 'matlab.ui.control.Button', 'Text', text);
assert(~isempty(b), 'no "%s" button in "%s"', text, fig.Name);
feval(b(1).ButtonPushedFcn, b(1), []);
end


function s = localState(pd)
warnState = warning('off', 'MATLAB:structOnObject');
s = struct(pd);
warning(warnState);
end


function localDeleteLeftovers()
for prefix = ["Version History -", "Protocol Changes -"]
    f = localFind(prefix);
    while ~isempty(f)
        f.CloseRequestFcn = '';
        delete(f);
        f = localFind(prefix);
    end
end
end


function localForceClose(pd)
if isempty(pd) || ~isvalid(pd), return, end
s = localState(pd);
figs = {s.Figure, s.InterfaceFigure, s.OptionsFigure, s.PreviewFigure, s.CheckCalcFigure};
for k = 1:numel(figs)
    if ~isempty(figs{k}) && isvalid(figs{k})
        delete(figs{k});
    end
end
end


function localRemoveDir(d)
if isfolder(d)
    rmdir(d, 's');
end
end
