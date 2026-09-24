function smoke_test_sessionclock_stop()
% smoke_test_sessionclock_stop()
% Exercise gui.components.SessionClock against the run-mode broadcasts a
% session makes: a stop holds every readout, computer time included, at the
% instant the session ended and stops the refresh timer, a pause does not,
% and a run releases the hold. Also checks that the host's
% own stop() outranks the run mode.
%
% Uses an invisible uifigure and a bare epsych.EventHub; no hardware.
%
%   matlab -batch "run('tmp/smoke_test_sessionclock_stop.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

PREF = 'smokeSessionClockStop';
if ispref(PREF), rmpref(PREF); end
cleanupPref = onCleanup(@() clearPref(PREF));

fig = uifigure('Visible','off');
cleanupFig = onCleanup(@() delete(fig));

% Identify this test's own timer, so the ticking assertions below cannot be
% confused by a clock some other window on this MATLAB session is running.
before = timerfindall('Tag','EPsychSessionClock');

rt = makeRuntime();
c  = gui.components.SessionClock(fig, PreferenceTag=PREF, UpdatePeriod=0.25);
cleanupClock = onCleanup(@() delete(c));
c.attachRuntime(rt);
c.start();

after = timerfindall('Tag','EPsychSessionClock');
T = after(arrayfun(@(t) ~any(t == before), after));
assert(isscalar(T), 'expected exactly one new SessionClock timer (found %d)', numel(T));


% 1. A running session counts ---------------------------------------------
notify(rt.EVENTS, 'NewTrial');
assert(~c.IsStopped, 'a clock over a running session should not be held');
assert(strcmp(T.Running,'on'), 'a started clock should be ticking');

assertAdvances(c, 'SessionDuration', 'session duration should advance while the session runs');
fprintf('PASS: the elapsed readouts count while the session runs\n');


% 2. Stop holds every elapsed readout at the stop instant ------------------
% RunExpt broadcasts Stop the moment the operator presses it; ep_TimerFcn_Stop
% follows with Idle. The first one is the end of the session.
setMode(rt, hw.DeviceState.Stop);
assert(c.IsStopped, 'Stop should hold the elapsed readouts');

held = elapsedLines(c);
pause(1.3)
assert(isequal(held, elapsedLines(c)), ...
    'a stopped session must not keep counting ("%s" became "%s")', ...
    strjoin(held,' | '), strjoin(elapsedLines(c),' | '));

% The trailing Idle is the same stop, not a second one: the held values must
% not jump forward to it.
setMode(rt, hw.DeviceState.Idle);
assert(isequal(held, elapsedLines(c)), ...
    'the Idle that follows a Stop must not re-stamp the hold');
fprintf('PASS: a stop holds the elapsed readouts at the end of the session\n');


% 3. The computer time stops too ------------------------------------------
% It reads when the session ended, so nothing on the widget moves and the
% refresh timer has nothing left to do -- whether or not the line is shown.
assert(strcmp(T.Running,'off'), 'a stopped session should stop the refresh timer');
clockHeld = lineText(c, 'ClockTime');
pause(1.3)
assert(strcmp(clockHeld, lineText(c,'ClockTime')), ...
    'the computer time should hold at the stop instant');
c.ShowClockTime = false;
c.refresh();
c.ShowClockTime = true;
c.refresh();
assert(strcmp(T.Running,'off'), 'toggling the computer time must not restart a stopped clock');
assert(strcmp(clockHeld, lineText(c,'ClockTime')), ...
    'a redraw after the stop must still show the stop instant');
fprintf('PASS: the computer time holds at the stop and the timer stops\n');


% 4. A trial arriving after the stop is ignored ---------------------------
lastHeld = lineText(c, 'LastTrial');
notify(rt.EVENTS, 'NewTrial');
assert(strcmp(lineText(c,'LastTrial'), lastHeld), ...
    'a trial after the stop must not re-stamp the held display');
fprintf('PASS: a trial arriving after the stop leaves the hold alone\n');


% 5. A run releases the hold ----------------------------------------------
setMode(rt, hw.DeviceState.Record);
assert(~c.IsStopped, 'Record should release the hold');
assertAdvances(c, 'SessionDuration', 'a resumed clock should count again');

setMode(rt, hw.DeviceState.Preview);
assert(~c.IsStopped, 'a preview run is a run');
fprintf('PASS: Record and Preview release the hold\n');


% 6. A pause is not a stop ------------------------------------------------
% Wall time passes during a pause, and the operator is told to press Stop to
% end the session.
setMode(rt, hw.DeviceState.Pause);
assert(~c.IsStopped, 'Pause must not hold the readouts');
assertAdvances(c, 'SessionDuration', 'a paused session should keep counting wall time');
fprintf('PASS: a pause is not a stop\n');


% 7. attachRuntime releases a hold ----------------------------------------
% Attaching a runtime is what says this clock is timing a new session.
setMode(rt, hw.DeviceState.Stop);
assert(c.IsStopped, 'Stop should hold again');
rt2 = makeRuntime();
c.attachRuntime(rt2);
assert(~c.IsStopped, 'attaching a new runtime should release the hold');
assert(strcmp(T.Running,'on'), 'a released clock should be ticking again');

% The old runtime's broadcasts are nothing to do with this clock any more.
setMode(rt, hw.DeviceState.Stop);
assert(~c.IsStopped, 'the replaced runtime must no longer be able to stop the clock');
fprintf('PASS: attachRuntime releases the hold and replaces the listener\n');


% 8. The host's stop() outranks the run mode ------------------------------
c.stop();
assert(strcmp(T.Running,'off'), 'stop() should stop the refresh timer');
setMode(rt2, hw.DeviceState.Stop);
setMode(rt2, hw.DeviceState.Record);
assert(strcmp(T.Running,'off'), ...
    'a run mode must not start a clock the host stopped');
c.start();
assert(strcmp(T.Running,'on'), 'start() should start it again');
fprintf('PASS: start()/stop() stay the host''s decision\n');


% 9. Teardown -------------------------------------------------------------
delete(c);
assert(~isvalid(T), 'deleting the clock should take its timer with it');
fprintf('PASS: the clock deletes its timer\n');

fprintf('\nALL SESSIONCLOCK STOP TESTS PASSED\n');
end


function rt = makeRuntime()
% A runtime is only ever an event source here: the clock reads StartTime and
% then listens.
rt = epsych.Runtime;
rt.EVENTS = epsych.EventHub;
rt.StartTime = datetime('now');
end


function setMode(rt, mode)
notify(rt.EVENTS, 'ModeChange', epsych.eventModeChange(mode));
drawnow limitrate
end


function s = lineText(c, key)
s = c.LabelH.(key).Text;
end


function assertAdvances(c, key, msg)
% Wait for a line to be redrawn with a new value. Polling rather than one
% fixed pause: the readouts have one-second resolution, so a tick that lands
% a fraction early would fail an unlucky single comparison on a busy machine.
t0 = lineText(c, key);
w  = tic;
while toc(w) < 5
    pause(0.2)
    if ~strcmp(lineText(c,key), t0), return; end
end
error('%s (stuck at "%s" for %.0f s)', msg, t0, toc(w));
end


function s = elapsedLines(c)
% The three readouts a stop is supposed to hold.
keys = {'LastTrial','FirstTrial','SessionDuration'};
s = string(cellfun(@(k) lineText(c,k), keys, 'UniformOutput', false));
end


function clearPref(group)
try
    if ispref(group), rmpref(group); end
catch
end
end
