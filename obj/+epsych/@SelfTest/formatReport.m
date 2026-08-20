function txt = formatReport(self, results)
% txt = formatReport(self, results)
% Render self-test results as plain text suitable for the clipboard, a log,
% or an email to whoever maintains the rig.
%
% Parameters:
%	self	- epsych.SelfTest instance.
%	results	- Result struct array returned by run().
%
% Returns:
%	txt	- Multi-line char array.
%
% See also: epsych.SelfTest.run, epsych.SelfTest.saveReport
arguments
    self
    results struct
end

E = EPsychInfo;
L = strings(1,0);

L(end+1) = "EPsych RunExpt Self-Test Report";
L(end+1) = string(repmat('=', 1, 60));
L(end+1) = sprintf('Generated : %s', datetime('now', Format='yyyy-MM-dd HH:mm:ss'));
L(end+1) = sprintf('EPsych    : %s', string(E.latestTag));
L(end+1) = sprintf('MATLAB    : %s', string(version));
L(end+1) = sprintf('Host      : %s', string(getenv('COMPUTERNAME')));
L(end+1) = sprintf('Verbosity : %d', self.Verbosity);
L(end+1) = sprintf('Opt-ins   : HardwareConnect=%d  BehaviorGUI=%d  GuiStateCycle=%d', ...
    self.IncludeHardwareConnect, self.IncludeBehaviorGUI, self.IncludeGuiStateCycle);

if isempty(self.RunExpt) || ~isvalid(self.RunExpt)
    L(end+1) = "Session   : none";
else
    L(end+1) = sprintf('Session   : state %s, %d subject(s)', ...
        string(self.RunExpt.STATE), numel(self.RunExpt.CONFIG));
end

s = epsych.SelfTest.rollup(results);
L(end+1) = "";
L(end+1) = sprintf('Summary   : %d passed, %d failed, %d warning(s), %d skipped, %d info (%d checks, %.2f s)', ...
    s.pass, s.fail, s.warn, s.skip, s.info, s.total, s.seconds);
L(end+1) = "";

if isempty(results)
    L(end+1) = "No checks were run.";
    txt = char(strjoin(L, newline));
    return
end

% Failures and warnings first: the report is read to find out what is broken.
priority = ["fail","warn"];
attention = results(ismember(string({results.status}), priority));
if ~isempty(attention)
    L(end+1) = "NEEDS ATTENTION";
    L(end+1) = string(repmat('-', 1, 60));
    for i = 1:numel(attention)
        L = [L localFormatOne(attention(i), true)];
    end
    L(end+1) = "";
end

L(end+1) = "ALL RESULTS";
L(end+1) = string(repmat('-', 1, 60));

groups = unique(string({results.group}), 'stable');
for g = groups
    inGroup = results(strcmp(string({results.group}), g));
    L(end+1) = "";
    L(end+1) = sprintf('[%s]', g);
    for i = 1:numel(inGroup)
        L = [L localFormatOne(inGroup(i), false)];
    end
end

txt = char(strjoin(L, newline));

end

% -----------------------------------------------------------------------
function L = localFormatOne(r, verbose)
% Render one result. Detail lines are included only in the attention section
% and for non-passing checks elsewhere, so a clean report stays readable.
L = strings(1,0);
L(end+1) = sprintf('  %-5s %-34s %s', upper(r.status), r.name, r.summary);

showDetail = verbose || ~strcmp(r.status, 'pass');
if showDetail
    for d = r.detail
        L(end+1) = sprintf('          %s', d);
    end
    if strlength(r.remedy) > 0
        L(end+1) = sprintf('          -> %s', r.remedy);
    end
end
end
