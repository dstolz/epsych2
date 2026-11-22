function smoke_test_warmup
% smoke_test_warmup
% epsych.warmUp rehearses a few trial boundaries on a software-only session so
% the first real boundaries are not the first time that code runs. It must do
% that without leaving anything behind, and only once.
%
% Verifies:
%   1) a forced rehearsal runs to the end and says so, with and without the
%      displays
%   2) it leaves no figure, no timer, no preference and no folder behind
%   3) it has then been done: a query says no, and a plain call does nothing
%   4) the rig's preference EPsych/WarmUp = false is read as "no" (and the
%      preference is put back as it was found)
%   5) the session window's priority call leaves this MATLAB at High priority
%      (Windows)
%   6) (reported) how long a rehearsal takes
%
% Opens a session window. Run headless:
%   matlab -batch "run('tmp/smoke_test_warmup.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);

fprintf('\n=== smoke_test_warmup ===\n');

figsBefore = findall(groot, 'Type', 'figure');
timersBefore = timerfindall;
groups = {'epsych2_gui_History', 'epsych2_gui_ParameterScatter', ...
    'epsych2_gui_SessionPerformance', 'epsych2_gui_NextTrial', 'epsych2_psychophysics_Staircase'};

% --- 1. it runs ---------------------------------------------------------------
t = tic;
ran = epsych.warmUp(Force = true, NumTrials = 5);
elapsed = toc(t);
assert(ran, 'a forced rehearsal should run and report that it did (the log says why not)');
t = tic;
ran = epsych.warmUp(Force = true, NumTrials = 2, Displays = true);
elapsedDisplays = toc(t);
assert(ran, 'a forced rehearsal with displays should run and report that it did (the log says why not)');
fprintf('PASS: 1 a forced rehearsal ran to the end, with and without displays\n');

% --- 2. nothing is left -------------------------------------------------------
% The shared flash timer (gui.Helper) removes itself once the controls it was
% flashing are gone; give it its two ticks.
waited = tic;
while ~isempty(timerfindall) && numel(timerfindall) > numel(timersBefore) && toc(waited) < 6
    pause(0.25);
end
drawnow
figsAfter = findall(groot, 'Type', 'figure');
assert(numel(figsAfter) == numel(figsBefore), 'the rehearsal left %d figure(s) behind', ...
    numel(figsAfter) - numel(figsBefore));
assert(numel(timerfindall) == numel(timersBefore), 'the rehearsal left a timer behind');
for g = 1:numel(groups)
    assert(~ispref(groups{g}, 'epsychWarmUp'), 'the rehearsal left a preference in %s', groups{g});
end
scratch = fullfile(tempdir, sprintf('epsych_warmup_%d', feature('getpid')));
assert(~isfolder(scratch), 'the rehearsal left its folder behind: %s', scratch);
fprintf('PASS: 2 no figure, timer, preference or folder is left\n');

% --- 3. once ------------------------------------------------------------------
assert(~epsych.warmUp(Query = true), 'after a rehearsal a query should say there is nothing to do');
t = tic;
assert(~epsych.warmUp(), 'a second plain call should do nothing');
assert(toc(t) < 0.5, 'and should return at once (took %.2f s)', toc(t));
fprintf('PASS: 3 it is done once per MATLAB session\n');

% --- 4. the preference --------------------------------------------------------
had = ispref('EPsych', 'WarmUp');
was = [];
if had, was = getpref('EPsych', 'WarmUp'); end
restore = onCleanup(@() localRestore(had, was));
setpref('EPsych', 'WarmUp', false);
assert(~epsych.warmUp(Query = true), 'EPsych/WarmUp = false must read as no');
assert(epsych.warmUp(Query = true, Force = true), 'Force outranks the preference');
clear restore
if had
    assert(isequal(getpref('EPsych', 'WarmUp'), was), 'the preference was not put back');
else
    assert(~ispref('EPsych', 'WarmUp'), 'the preference this test made was not removed');
end
fprintf('PASS: 4 the rig preference turns it off\n');

% --- 5. priority --------------------------------------------------------------
if ispc
    proc = System.Diagnostics.Process.GetCurrentProcess();
    before = proc.PriorityClass;
    putBack = onCleanup(@() localSetPriority(before));
    proc.PriorityClass = System.Diagnostics.ProcessPriorityClass.Normal;
    delete(findall(groot, 'Type', 'figure', 'Tag', 'RunExpt'));
    rx = epsych.RunExpt(ReuseExisting = false);
    closeIt = onCleanup(@() close(rx.H.figure1));
    % The call is private; a refused Run still reaches it. With no subject in
    % the session the dispatch fails on the first check after it, which is
    % all this needs.
    rx.H.ctrl_preview.ButtonPushedFcn(rx.H.ctrl_preview, []);
    proc.Refresh();
    assert(proc.PriorityClass == System.Diagnostics.ProcessPriorityClass.High, ...
        'the session did not raise this MATLAB to High priority (it is %s)', char(string(proc.PriorityClass)));
    clear closeIt putBack
    fprintf('PASS: 5 Run raises the MATLAB process to High priority\n');
else
    fprintf('SKIP: 5 process priority is Windows only\n');
end

fprintf('INFO: 6 a rehearsal of 5 boundaries took %.1f s; one of 2 with the displays, %.1f s\n', ...
    elapsed, elapsedDisplays);
fprintf('smoke_test_warmup: ALL PASS\n');
end


function localRestore(had, was)
if had
    setpref('EPsych', 'WarmUp', was);
elseif ispref('EPsych', 'WarmUp')
    rmpref('EPsych', 'WarmUp');
end
end


function localSetPriority(p)
proc = System.Diagnostics.Process.GetCurrentProcess();
proc.PriorityClass = p;
end
