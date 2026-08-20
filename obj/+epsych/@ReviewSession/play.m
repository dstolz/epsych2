function play(obj, rate)
% play(obj, rate)
% Advance through the trials on a timer, for watching a session back.
%
% Playback is by trial, not by wall clock: a session with a 20 s inter-trial
% interval would otherwise take as long to watch as it took to run. rate is
% trials per second, and the timer drops ticks rather than queuing them, so a
% paradigm with an expensive redraw plays slower instead of falling behind.
%
% Starting from the last trial rewinds first -- pressing play at the end is a
% request to watch it again, not a no-op.
%
% Parameters:
%   obj  - epsych.ReviewSession.
%   rate - Trials per second. Default 4.
%
% See also: epsych.ReviewSession.pause, epsych.ReviewSession.seek

arguments
    obj
    rate (1,1) double {mustBePositive,mustBeFinite} = 4
end

obj.pause();

if obj.Position >= obj.NumTrials
    obj.seek(0);
end

if isempty(obj.PlayTimer_) || ~isvalid(obj.PlayTimer_)
    obj.PlayTimer_ = timer( ...
        'Name',          sprintf('ReviewSession_%s', matlab.lang.makeValidName(obj.DataFile)), ...
        'ExecutionMode', 'fixedSpacing', ...
        'BusyMode',      'drop', ...
        'TimerFcn',      @(~,~) localTick(obj));
end

obj.PlayTimer_.Period = round(1/rate, 3);
start(obj.PlayTimer_);

vprintf(1, 'epsych.ReviewSession: playing from trial %d at %g trials/s', obj.Position, rate)

end




function localTick(obj)
% localTick(obj)
%
% One trial forward, stopping at the end. Guarded on the review still existing:
% a timer callback can outlive the object by one tick when the window is closed
% mid-playback.

if ~isvalid(obj)
    return
end

if obj.Position >= obj.NumTrials
    obj.pause();
    vprintf(1, 'epsych.ReviewSession: playback reached the last trial')
    return
end

try
    obj.step(1);
catch ME
    obj.pause();
    vprintf(0, 1, ME)
    vprintf(0, 1, 'epsych.ReviewSession: playback stopped at trial %d', obj.Position)
end

end
