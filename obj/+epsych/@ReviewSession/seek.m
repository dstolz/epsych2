function seek(obj, k)
% seek(obj, k)
% Show trial k, firing the events a live session would have fired there.
%
% This is the whole player, and it is short for one reason: every consumer
% takes the WHOLE DATA array out of the payload and recomputes from scratch
% (psychophysics.Psych.update_data assigns obj.DATA = event.Data.DATA;
% gui.ParameterScatter, gui.History and gui.SessionPerformance do the
% equivalent). So one notify carrying Data(1:k) is worth k notifies, and
% winding BACK costs exactly what going forward costs. There is no
% replay-from-the-start and no per-component reset to maintain.
%
% Three steps:
%   1. position the replay backends, so every hw.Parameter read -- a
%      gui.Parameter_Monitor poll, gui.ParameterDebugger's Read, a paradigm
%      hook -- reports what the rig held on trial k;
%   2. build the TRIALS struct for that trial;
%   3. notify NewData then NewTrial, in that order, because that is the order
%      ep_TimerFcn_RunTime uses and a paradigm hook may depend on it.
%
% The two notifies carry deliberately different trials, matching the live
% meanings: NewData describes the trial that just COMPLETED (TrialIndex == k,
% numel(DATA) == k), while NewTrial describes the one that would run NEXT, so
% gui.NextTrial shows the trial that actually followed rather than repeating
% the one being looked at. At the last trial there is no next, so NewTrial
% repeats trial k rather than inventing one.
%
% Parameters:
%   obj - epsych.ReviewSession.
%   k   - Trial to show, clamped to 0:NumTrials. 0 is before the first trial:
%         no data, first trial pending, which is what the session looked like
%         the moment the behavior GUI opened.
%
% See also: epsych.TrialsData, runtime/timerfcns/ep_TimerFcn_RunTime.m

arguments
    obj
    k (1,1) double {mustBeInteger}
end

k = max(0, min(k, obj.NumTrials));
obj.Position = k;

% 1. Position the hardware side.
for p = obj.Interfaces(:).'
    p.Position = k;
end

if isempty(obj.RUNTIME) || ~isvalid(obj.RUNTIME) ...
        || isempty(obj.RUNTIME.EVENTS) || ~isvalid(obj.RUNTIME.EVENTS)
    return
end

% 2. The completed-trial view.
T = obj.TrialsTemplate_;
if k >= 1
    T.DATA        = obj.Data(1:k);
    T.TrialIndex  = k;
    T.NextTrialID = localTrialID(obj.Data, k);
else
    T.DATA        = struct.empty(1,0);
    T.TrialIndex  = 1;
    T.NextTrialID = localTrialID(obj.Data, 1);
end

% Keep the runtime in step with what was broadcast, for the components that
% read RUNTIME.TRIALS directly rather than the payload (gui.NextTrial seeds
% itself that way, and paradigm GUIs written in the "GUI plays the rig" style
% read it on every trial). ReviewMode makes this assignment inert beyond
% storing the struct.
obj.RUNTIME.TRIALS = T;

if k >= 1
    localNotify(obj, 'NewData', T);
end

% 3. The upcoming-trial view.
if k >= 1 && k < obj.NumTrials
    T.TrialIndex  = k + 1;
    T.NextTrialID = localTrialID(obj.Data, k + 1);
    obj.RUNTIME.TRIALS = T;
end

localNotify(obj, 'NewTrial', T);

% Last, so the scrubber never shows a trial the displays have not caught up to.
% Done here rather than by the transport's own listener because a seek can come
% from code or from playback as well as from the slider.
try
    if ~isempty(obj.Transport) && isvalid(obj.Transport)
        obj.Transport.refresh();
    end
catch ME
    vprintf(2, 'epsych.ReviewSession: could not update the transport (%s)', ME.message)
end

end




function id = localTrialID(Data, k)
% id = localTrialID(Data, k)
%
% The condition-list row presented on trial k. DATA.TrialID is a condition
% label, not a position -- the presentation order is the array index -- so it
% is read from the record rather than assumed to equal k. A record that never
% carried one falls back to the index, which at least indexes the trial table
% in range.

id = k;
if k >= 1 && k <= numel(Data) && isfield(Data, 'TrialID') && ~isempty(Data(k).TrialID)
    id = Data(k).TrialID;
end

end




function localNotify(obj, eventName, T)
% localNotify(obj, eventName, T)
%
% Fire one runtime event. Wrapped because a listener that throws must not stop
% the seek: the remaining components still have to be updated, and a display
% bug in one paradigm hook should not strand the review on a half-drawn trial.

try
    obj.RUNTIME.EVENTS.notify(eventName, epsych.TrialsData(T));
catch ME
    vprintf(0, 1, ME)
    vprintf(0, 1, 'epsych.ReviewSession: a %s listener failed at trial %d', eventName, obj.Position)
end

end
