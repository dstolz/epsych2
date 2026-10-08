function F = fit(~, S, settings)
% F = fit(sess, S, settings)
% The psychometric fit of a staircase's trials, in the common fit schema
% (behavior.fit.Builtin): the same fields whichever engine made it.
%
% Settings.Fit.Engine "builtin" fits with
% psychophysics.Staircase.fitPsychometric(settings.fitArgs()). "psignifit"
% fits the same trials -- psychophysics.Staircase.psychometricCounts, the
% counts fitPsychometric itself fits -- with behavior.fit.Psignifit, under
% settings.psignifitOptions(). Neither throws for a session: a fit that
% cannot be made (psignifit not installed, data it refuses) carries the
% counts and the reason in Message. With Settings.Fit.Enabled false nothing
% is fitted and Message says so.
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

if settings.Fit.Engine == "builtin"
    F = behavior.fit.Builtin.fromStaircase(S, settings.fitArgs());
    return
end

C = S.psychometricCounts(IncludeAborts = settings.IncludeAborts);
[o, info] = settings.psignifitOptions(CatchFalseAlarmRate = C.CatchFalseAlarmRate);
try
    if C.Message ~= ""
        error('behavior:Session:NoCounts', '%s', C.Message);
    end
    F = behavior.fit.Psignifit.fromCounts(C.Levels, C.NumYes, C.NumTotal, o, info);
catch ME
    F = behavior.fit.Builtin.empty();
    F.Engine = "psignifit";
    F.Shape = string(info.Sigmoid);
    for f = ["Levels" "NumYes" "NumTotal" "Proportion"]
        F.(f) = C.(f);
    end
    F.Message = string(ME.message);
    vprintf(2, 'behavior.Session: %s', F.Message)
end

end
