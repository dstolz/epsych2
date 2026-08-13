function s = sessionVectors_(obj)
% s = sessionVectors_(obj)
% Per-trial vectors shared by the recompute and by the plot.
%
% One plot update used to walk the whole session eight times over: the
% stimulus values were extracted for the points, again for the threshold
% and again just to count trials, and the response codes were extracted
% and decoded once per trial-type mask and once per plotted series. They
% are built once here instead, and held until the trials, the trial-type
% selection, the exclusions, or the dB conversion behind them change.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%
% Returns:
%   s — struct with fields:
%       .stimValues  1xN stimulus values (dB converted when configured)
%       .respCodes   1xN uint32 response codes, empty when unavailable
%       .decoded     epsych.BitMask.decode(respCodes), [] when unavailable
%       .stimMask    1xN logical, trials counted as stimulus trials
%       .catchMask   1xN logical, trials counted as catch trials
%       .key         cache key the vectors were built for

key = {obj.trialCount, obj.ConvertToDecibels, obj.excludedTrials_, ...
    obj.StimulusTrialType, obj.CatchTrialType};

if ~isempty(obj.sessionCache_) && isequaln(obj.sessionCache_.key, key)
    s = obj.sessionCache_;
    return
end

s.key = key;
s.stimValues = obj.stimulusValues;
s.respCodes = obj.responseCodes;

if isempty(s.respCodes)
    s.decoded = [];
else
    s.decoded = epsych.BitMask.decode(s.respCodes);
end

% The decode is handed over so the masks do not pay for a second one when
% DATA carries no explicit TrialType field.
masks = obj.trialTypeMasks_([obj.StimulusTrialType obj.CatchTrialType], s.decoded);
s.stimMask = masks(1,:);
s.catchMask = masks(2,:);

obj.sessionCache_ = s;
