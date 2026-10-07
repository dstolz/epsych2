function file = writeScript(self, file, options)
% file = writeScript(self, file, Scope = "selected")
% Write a plain MATLAB script that reproduces an analysis shown here,
% through behavior.ScriptWriter: the settings in force, each session's
% trial window, the very analysis call the window makes, and a check that
% the numbers come out as they were when the script was written.
%
% Parameters:
%   file  - the .m file to write ("" asks, when the window is shown)
%   Scope - "session"  the session on the Session tab
%           "selected" the checked sessions, with the Compare view's
%                      facets (default)
%           "study"    every visible session
%
% Returns:
%   file - the file written ("" when nothing was)
%
% See also: behavior.ScriptWriter.session, behavior.ScriptWriter.compare
arguments
    self
    file (1,1) string = ""
    options.Scope (1,1) string {mustBeMember(options.Scope, ["session" "selected" "study"])} = "selected"
end

if isempty(self.Study)
    file = "";
    return
end

switch options.Scope
    case "session"
        keys = self.Views.Session.Key;
        if keys == ""
            self.alert_('Show a session on the Session tab first.', 'Generate Script', 'info');
            file = "";
            return
        end
        [~, stem] = fileparts(keys);
        stem = "replicate_" + string(stem);
    case "selected"
        keys = self.analysedKeys();
        stem = "replicate_checked_sessions";
    case "study"
        keys = self.Study.visibleKeys();
        stem = "replicate_study";
end
if isempty(keys)
    self.alert_('There are no sessions to write a script for: check some in the browser first.', ...
        'Generate Script', 'info');
    file = "";
    return
end

if file == ""
    if ~self.isVisible_()
        return
    end
    folder = string(self.getPref_('ExportFolder', pwd));
    [n, p] = uiputfile({'*.m', 'MATLAB script (*.m)'}, 'Generate Script', ...
        char(fullfile(folder, matlab.lang.makeValidName(stem) + ".m")));
    figure(self.H.figure);
    if isequal(n, 0)
        file = "";
        return
    end
    file = string(fullfile(p, n));
    self.setPref_('ExportFolder', char(p));
end

if options.Scope == "session"
    code = behavior.ScriptWriter.session(self.Study, keys);
else
    code = behavior.ScriptWriter.compare(self.Study, keys);
end
file = string(behavior.ScriptWriter.write(file, code));
self.setStatus_(sprintf("Wrote %s (%d session(s)).", file, numel(keys)));

end
