function F = fit(~, S, settings)
% F = fit(sess, S, settings)
% The psychometric fit of a staircase's trials, in the common fit schema
% (behavior.fit.Builtin): the same fields whichever engine made it.
%
% Settings.Fit.Engine "builtin" fits with
% psychophysics.Staircase.fitPsychometric(settings.fitArgs()). "psignifit"
% hands the same per-level counts to behavior.fit.Psignifit, which in this
% version reports why it cannot fit; the result then carries the counts and
% that reason in Message rather than throwing. With Settings.Fit.Enabled
% false nothing is fitted and Message says so.
%
% Parameters:
%   S        - psychophysics.Staircase (from staircase())
%   settings - behavior.Settings
%
% Returns:
%   F - common fit struct; read F.Threshold only when F.Converged and
%       F.Identifiable (it is NaN otherwise)
%
% See also: behavior.fit.Builtin, behavior.fit.Psignifit

arguments
    ~
    S (1,1) psychophysics.Staircase
    settings (1,1) behavior.Settings
end

if ~settings.Fit.Enabled
    F = behavior.fit.Builtin.empty();
    F.Message = "Fitting is off in these settings.";
    return
end

args = settings.fitArgs();
F = behavior.fit.Builtin.fromStaircase(S, args);
if settings.Fit.Engine == "builtin"
    return
end

counts = F;
try
    F = behavior.fit.Psignifit.fromCounts(counts.Levels, counts.NumYes, counts.NumTotal, settings.Fit);
catch ME
    F = behavior.fit.Builtin.empty();
    F.Engine = "psignifit";
    F.Shape = settings.Fit.Shape;
    for f = ["Levels" "NumYes" "NumTotal" "Proportion"]
        F.(f) = counts.(f);
    end
    F.Message = string(ME.message);
    vprintf(2, 'behavior.Session: %s', F.Message)
end

end
