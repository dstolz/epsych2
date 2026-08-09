function results = run(self, groupIds)
% results = run(self)
% results = run(self, groupIds)
% Execute the selected check groups and return one result per check.
%
% Verbosity is forced to self.Verbosity for the duration of the run and
% restored afterwards, so nested code (Protocol.compile, TrialSelector,
% hw.Interface.connect) also emits its detailed messages into the log. Every
% check additionally logs at level -1, which always reaches .error_logs
% regardless of the level the operator chose.
%
% Parameters:
%	self		- epsych.SelfTest instance.
%	groupIds	- Group ids to run (see epsych.SelfTest.catalog). Default: all.
%
% Returns:
%	results	- Struct array of results; see epsych.SelfTest.result.
%
% See also: epsych.SelfTest.catalog, epsych.SelfTest.formatReport
arguments
    self
    groupIds (1,:) string = [epsych.SelfTest.catalog().id]
end

global GVerbosity

C = epsych.SelfTest.catalog();
unknown = setdiff(groupIds, [C.id]);
if ~isempty(unknown)
    error('epsych:SelfTest:UnknownGroup', ...
        'Unknown check group(s): %s', strjoin(unknown, ', '));
end

% Force verbosity for the whole run, restoring whatever the operator had.
priorVerbosity = GVerbosity;
restoreVerbosity = onCleanup(@() localRestoreVerbosity(priorVerbosity));
GVerbosity = self.Verbosity;

banner = repmat('=', 1, 60);
vprintf(0, '%s', banner)
vprintf(0, 'EPsych self-test starting (%d group(s), verbosity %d)', numel(groupIds), self.Verbosity)
vprintf(-1, 'Self-test options: HardwareConnect=%d BoxFig=%d GuiStateCycle=%d', ...
    self.IncludeHardwareConnect, self.IncludeBoxFig, self.IncludeGuiStateCycle)

if isempty(self.RunExpt) || ~isvalid(self.RunExpt)
    vprintf(0, 1, 'No RunExpt session available; session-dependent checks will be skipped.')
else
    vprintf(-1, 'Target session state: %s, %d subject(s) configured', ...
        string(self.RunExpt.STATE), numel(self.RunExpt.CONFIG))
end

results = epsych.SelfTest.result();
runStart = tic;

for i = 1:numel(groupIds)
    g = C(strcmp([C.id], groupIds(i)));

    vprintf(1, '%s', repmat('-', 1, 60))
    vprintf(1, 'Group %d/%d: %s', i, numel(groupIds), g.label)

    groupStart = tic;
    try
        r = self.(g.method)();
    catch ME
        % A group that throws is itself a finding: report it rather than
        % aborting the remaining groups.
        vprintf(0, 1, ME);
        r = epsych.SelfTest.result(g.id + "_GroupError", g.id, g.label + " (group)", ...
            "fail", sprintf('The check group itself raised an error: %s', ME.message), ...
            Detail = string(ME.identifier), ...
            Remedy = "This is a bug in the self-test, not necessarily in the session. See the error log for the stack.");
    end
    groupSeconds = toc(groupStart);

    if isempty(r)
        vprintf(1, '  (no results)')
        continue
    end

    % Log every result at -1 so the full record lands in .error_logs even when
    % the operator picked a low verbosity, then echo headlines to the console.
    for k = 1:numel(r)
        vprintf(-1, '[%s] %s | %s | %s | %.4f s | %s', upper(r(k).status), ...
            r(k).group, r(k).id, r(k).name, r(k).seconds, r(k).summary);
        for d = r(k).detail
            vprintf(-1, '    detail: %s', d);
        end
        if strlength(r(k).remedy) > 0
            vprintf(-1, '    remedy: %s', r(k).remedy);
        end

        switch r(k).status
            case "fail"
                vprintf(0, 1, '  FAIL  %s: %s', r(k).name, r(k).summary);
                if strlength(r(k).remedy) > 0
                    vprintf(0, 1, '        remedy: %s', r(k).remedy);
                end
            case "warn"
                vprintf(1, '  WARN  %s: %s', r(k).name, r(k).summary);
            case "skip"
                vprintf(2, '  SKIP  %s: %s', r(k).name, r(k).summary);
            case "info"
                vprintf(2, '  INFO  %s: %s', r(k).name, r(k).summary);
            otherwise
                vprintf(1, '  PASS  %s: %s', r(k).name, r(k).summary);
        end
    end

    vprintf(2, '  %s completed in %.3f s', g.label, groupSeconds)
    results = [results r];
end

totalSeconds = toc(runStart);
s = epsych.SelfTest.rollup(results);

vprintf(0, '%s', banner)
vprintf(0, 'Self-test complete in %.2f s: %d passed, %d failed, %d warning(s), %d skipped, %d info', ...
    totalSeconds, s.pass, s.fail, s.warn, s.skip, s.info)
if s.fail > 0
    vprintf(0, 1, '%d check(s) failed. Review before starting a session.', s.fail)
end
vprintf(0, '%s', banner)

end

% -----------------------------------------------------------------------
function localRestoreVerbosity(level)
% Restore the global verbosity captured before the run. Declared as a local
% function because onCleanup cannot assign to a global from an anonymous handle.
global GVerbosity
GVerbosity = level;
end
