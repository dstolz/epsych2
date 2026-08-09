function ok = waitUntilDone(obj, timeoutSec)
% ok = obj.waitUntilDone()
% ok = obj.waitUntilDone(timeoutSec)
% Cooperatively block (via pause, so the scheduler timer can still fire)
% until the batch finishes or timeoutSec elapses. Returns true if the
% batch is not running when this returns (false on timeout).
arguments
    obj (1,1) util.VideoConverter
    timeoutSec (1,1) double {mustBePositive} = 3600
end

t0 = tic;
while obj.IsRunning && toc(t0) < timeoutSec
    pause(0.1);
end
ok = ~obj.IsRunning;
end
