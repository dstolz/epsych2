function smoke_test_idle_watchdog
% smoke_test_idle_watchdog
% The idle-hardware check epsych.RunExpt makes on every timer tick
% (RunExpt.hardwareIdle_), and the MATLAB behaviour it has to work around.
%
% The check was always written as
%   any(get(Interfaces,'mode') == hw.DeviceState.Idle)
% which works for ONE interface and silently does nothing for several: get()
% on a mixed interface array returns a cell of empty values and calls no
% backend's get.mode. Group 1 pins that behaviour down, since everything
% else here is a consequence of it.
%
% Verifies:
%   1) get() on a mixed interface array reaches no backend and compares false
%   2) one interface: Idle stops the session, as it always has
%   3) several interfaces, default: an Idle interface does NOT stop the session
%   4) several interfaces, StopOnIdleHardware on: it does, a RunOffline
%      interface is passed over, and the device is asked at most 4 times a second
%
% No hardware, no windows.
%
%   matlab -batch "run('tmp/smoke_test_idle_watchdog.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);

fprintf('\n=== smoke_test_idle_watchdog ===\n');

% --- 1. the MATLAB behaviour ------------------------------------------------
P = epsych.Protocol(Info = 'idle watchdog');
dev = CountingProbeInterface();
P.addInterface(dev);
I = P.Interfaces;
assert(numel(I) == 2, 'expected the software interface plus the probe');

dev.mode = hw.DeviceState.Idle;
dev.resetCounts();
g = get(I, 'mode');
assert(iscell(g) && all(cellfun(@isempty, g)), ...
    'get() on a mixed interface array was expected to return empty values');
assert(dev.Counts.Status == 0, 'get() on a mixed array reached get.mode after all');
assert(~any(g == hw.DeviceState.Idle), 'the old comparison was expected to be false');
assert(isequal(dev.mode, hw.DeviceState.Idle), 'scalar access must still read the mode');
fprintf('PASS: 1 get() on a mixed interface array reaches no backend\n');

% --- a RunExpt-shaped object to call the private check on --------------------
rx = epsych.RunExpt;
cleanup = onCleanup(@() localClose(rx));
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;

% --- 2. one interface --------------------------------------------------------
solo = CountingProbeInterface();
rt.Interfaces = solo;
rx.RUNTIME = rt;
solo.mode = hw.DeviceState.Preview;
assert(~localIdle(rx), 'a running single interface must not read as idle');
solo.mode = hw.DeviceState.Idle;
assert(localIdle(rx), 'an Idle single interface must stop the session');
fprintf('PASS: 2 one interface: Idle stops the session\n');

% --- 3. several interfaces, default -----------------------------------------
rt2 = epsych.Runtime;
rt2.isTest = true;
rt2.EVENTS = epsych.EventHub;
rt2.Interfaces = I;
rx.RUNTIME = rt2;
rx.StopOnIdleHardware = false;
dev.mode = hw.DeviceState.Idle;
dev.resetCounts();
assert(~localIdle(rx), 'by default an Idle interface among several must not stop the session');
assert(dev.Counts.Status == 0, 'by default the device must not be asked its mode');
fprintf('PASS: 3 several interfaces, default: unchanged\n');

% --- 4. several interfaces, opted in ----------------------------------------
rx.StopOnIdleHardware = true;
set(I, 'mode', hw.DeviceState.Preview);
assert(~localIdle(rx), 'running interfaces must not read as idle');
pause(0.3);                       % past the 0.25 s rate limit
dev.mode = hw.DeviceState.Idle;
assert(localIdle(rx), 'with StopOnIdleHardware an Idle interface must stop the session');

pause(0.3);
dev.RunOffline = true;
assert(~localIdle(rx), 'a RunOffline interface must be passed over');
dev.RunOffline = false;

set(I, 'mode', hw.DeviceState.Preview);
pause(0.3);
dev.resetCounts();
t0 = tic;
n = 0;
while toc(t0) < 1
    localIdle(rx);
    n = n + 1;
end
assert(n > 100, 'the check itself should be cheap enough to call hundreds of times a second');
assert(dev.Counts.Status <= 5, ...
    'the device was asked its mode %d times in one second; expected at most 5', dev.Counts.Status);
fprintf('PASS: 4 opted in: stops on Idle, skips RunOffline, %d device queries for %d checks\n', ...
    dev.Counts.Status, n);

fprintf('=== smoke_test_idle_watchdog: ALL PASS ===\n');
end


function tf = localIdle(rx)
tf = rx.hardwareIdle();
end

function localClose(rx)
try
    if isvalid(rx)
        delete(rx);
    end
catch
end
delete(findall(groot, 'Type', 'figure'));
end
