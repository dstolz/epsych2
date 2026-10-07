function S = staircase(sess, settings, options)
% S = staircase(sess, settings)
% S = staircase(sess, settings, Window = "3-83")
% An offline psychophysics.Staircase over this session, configured by
% settings and nothing else.
%
% The constructor gets behavior.Settings.staircaseArgs and the trials
% behavior.Session.exclusionMask leaves out (ExcludedTrials); the analysis
% settings that are properties (staircaseProperties) are then set one by one,
% each recomputing as it is set. The plot's labels come from the session --
% Subject, BoxID, and the parameter's Unit from its snapshot -- so S.Plot(ax)
% draws a titled, labelled plot. Being DATA-sourced, the object never takes
% an analysis setting from a remembered right-click choice: these settings
% are the record.
%
% Parameters:
%   settings - behavior.Settings
%   Window   - this session's trial window; "" (default) = settings.Window
%
% Returns:
%   S - psychophysics.Staircase
%
% Errors:
%   behavior:Session:NoParameter      - no parameter named and no candidate
%   behavior:Session:MissingParameter - the session lacks the named field
%
% See also: behavior.Session.analyze, behavior.Settings.staircaseArgs

arguments
    sess (1,1) behavior.Session
    settings (1,1) behavior.Settings
    options.Window (1,1) string = ""
end

field = sess.resolveParameter(settings);
if field == ""
    error('behavior:Session:NoParameter', ...
        '%s: no parameter is named and the session has no candidate field.', sess.Key);
end
if ~ismember(field, sess.Fields)
    error('behavior:Session:MissingParameter', ...
        '%s: the trial records have no field "%s".', sess.Key, field);
end

win = options.Window;
if win == "", win = settings.Window; end
excl = behavior.Session.exclusionMask(sess.Data, Window = win, ...
    ExcludeTest = settings.ExcludeTest, ExcludeTrialTypes = settings.ExcludeTrialTypes);

args = settings.staircaseArgs();
S = psychophysics.Staircase(sess.Data, char(field), args{:}, ExcludedTrials = find(excl));

props = settings.staircaseProperties();
for f = reshape(string(fieldnames(props)), 1, [])
    if ~isequaln(S.(f), props.(f))
        S.(f) = props.(f);
    end
end

S.Subject = sess.Subject;
S.Unit = sess.parameterMeta(field).Unit;
if ~isempty(sess.Snapshot)
    box = sess.Snapshot.BoxID;
    if isnumeric(box) && isscalar(box) && isfinite(box)
        S.BoxID = double(box);
    end
end

end
