function dur_sec = estimateDuration(obj)
% dur_sec = estimateDuration(obj)
%
% Estimate total trial duration in seconds based on COMPILED trials.
%
% Returns:
%   dur_sec (double) - Estimated duration in seconds, or NaN if compilation incomplete

if isempty(obj.COMPILED.trials)
    dur_sec = nan;
    return
end

ntrials = size(obj.COMPILED.trials, 1);
trial_duration_sec = 2;  % Assume 2 sec per trial (baseline)

dur_sec = ntrials * trial_duration_sec;
