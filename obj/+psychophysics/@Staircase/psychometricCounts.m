function C = psychometricCounts(obj, options)
% C = S.psychometricCounts()
% C = S.psychometricCounts(IncludeAborts=true, LevelTolerance=0.01)
% The staircase's trials as per-level counts: how many STIMULUS trials ran
% at each level and how many of them were a "yes".
%
% This is what any psychometric fit consumes -- fitPsychometric fits it by
% maximum likelihood, and [C.Levels' C.NumYes' C.NumTotal'] is exactly the
% data matrix psignifit takes -- so it is its own method rather than the
% first half of one fit. It fits nothing and stores nothing.
%
% The scoring is fitPsychometric's: STIMULUS trials as StimulusTrialType
% selects them, ExcludedTrials removed; a "yes" carries Hit, a "no" carries
% Miss; an abort is left out unless IncludeAborts counts it as a failure to
% respond; a code carrying both Hit and Miss, or neither, is unscored; a
% trial with no recorded level is dropped and counted. The CATCH trials are
% counted alongside, since a fit may take its guess rate from them.
%
% Parameters:
%   IncludeAborts  - Count aborted stimulus trials as failures to respond
%                    (default false), and aborted catch trials in the
%                    false-alarm denominator.
%   LevelTolerance - Merge levels within this ABSOLUTE distance of one
%                    another (default 0: exactly equal levels only); the
%                    merged level is the mean of the values it stands for.
%
% Returns:
%   C - struct with fields
%       Levels, NumYes, NumTotal, Proportion - per-level counts (1,:), levels
%                             ascending; empty when nothing could be scored
%       ParameterName       - the tracked parameter
%       NumScored, NumAborted, NumUnscored, NumUndefinedLevel - where the
%                             stimulus trials went
%       CatchFalseAlarms, CatchCorrectRejects, CatchAborts - catch-trial counts
%       CatchFalseAlarmRate - false alarms over the catch trials
%                             (psychophysics.Metrics.rateDenominator's rule
%                             for aborts); NaN with no scored catch trial
%       Message             - why there are no counts ("" when there are)
%
% Example:
%   C = S.psychometricCounts();
%   data = [C.Levels' C.NumYes' C.NumTotal'];     % psignifit's data matrix
%
% See also psychophysics.Staircase.fitPsychometric,
% psychophysics.Staircase.fitProportions, psychophysics.Metrics.rateDenominator

arguments
    obj
    options.IncludeAborts (1,1) logical = false
    options.LevelTolerance (1,1) double {mustBeNonnegative} = 0
end

C = struct( ...
    'Levels',              zeros(1, 0), ...
    'NumYes',              zeros(1, 0), ...
    'NumTotal',            zeros(1, 0), ...
    'Proportion',          zeros(1, 0), ...
    'ParameterName',       obj.ParameterName, ...
    'NumScored',           0, ...
    'NumAborted',          0, ...
    'NumUnscored',         0, ...
    'NumUndefinedLevel',   0, ...
    'CatchFalseAlarms',    0, ...
    'CatchCorrectRejects', 0, ...
    'CatchAborts',         0, ...
    'CatchFalseAlarmRate', NaN, ...
    'Message',             "");

if isempty(obj.DATA)
    C.Message = "The staircase holds no trials to fit.";
    return
end

s = obj.sessionVectors_();

if isempty(s.decoded)
    C.Message = "DATA carries no response codes, so no trial can be scored.";
    return
end

% ---- Score the stimulus trials ------------------------------------------
% A code carrying both Hit and Miss says two contradictory things about one
% trial; it is counted as unscored rather than resolved in either direction.
isHit   = reshape(s.decoded.Hit,   1, []);
isMiss  = reshape(s.decoded.Miss,  1, []);
isAbort = reshape(s.decoded.Abort, 1, []);

yes = isHit & ~isMiss;
no  = isMiss & ~isHit;

stim = s.stimMask;                            % exclusions already applied

% One level per trial, or nothing can be paired. A tracked parameter with no
% value on some trials produces a short vector, and pairing it with the trial
% masks would be arithmetic on two different sessions.
if numel(s.stimValues) ~= numel(stim)
    C.Message = "The tracked parameter has no value on every trial, so levels and responses cannot be paired.";
    return
end

scored = stim & (yes | no);
if options.IncludeAborts
    scored = scored | (stim & isAbort & ~yes & ~no);
end

C.NumAborted  = sum(stim & isAbort & ~yes & ~no);
C.NumScored   = sum(scored);
C.NumUnscored = sum(stim) - C.NumScored;

% ---- Catch trials --------------------------------------------------------
isFA = reshape(s.decoded.FalseAlarm,    1, []);
isCR = reshape(s.decoded.CorrectReject, 1, []);
ctch = s.catchMask;

C.CatchFalseAlarms    = sum(ctch & isFA & ~isCR);
C.CatchCorrectRejects = sum(ctch & isCR & ~isFA);
C.CatchAborts         = sum(ctch & isAbort);
den = psychophysics.Metrics.rateDenominator(C.CatchFalseAlarms + C.CatchCorrectRejects, ...
    C.CatchAborts, options.IncludeAborts);
C.CatchFalseAlarmRate = psychophysics.Metrics.rate(C.CatchFalseAlarms, den);

lv    = s.stimValues(scored);
isYes = yes(scored);

% A level of NaN (a trial whose value was not recorded) is dropped and
% counted, never treated as zero.
usable = isfinite(lv);
C.NumUndefinedLevel = sum(~usable);
lv    = lv(usable);
isYes = isYes(usable);

if isempty(lv)
    C.Message = "No stimulus trial could be scored at a defined stimulus level.";
    return
end

% ---- Counts per level ----------------------------------------------------
if options.LevelTolerance > 0
    % DataScale 1 makes the tolerance absolute; uniquetol's default scales it
    % by the largest value, which is not what "within 0.01 dB" means.
    [~, ~, ic] = uniquetol(lv, options.LevelTolerance, 'DataScale', 1);
else
    [~, ~, ic] = unique(lv);
end
ic = ic(:);

C.Levels     = accumarray(ic, lv(:), [], @mean)';
C.NumTotal   = accumarray(ic, 1)';
C.NumYes     = accumarray(ic, double(isYes(:)))';
C.Proportion = C.NumYes ./ C.NumTotal;
end
