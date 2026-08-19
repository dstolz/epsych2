function fields = issueReportFields(self, opts)
% fields = obj.issueReportFields()
% fields = obj.issueReportFields(MaxLogLines=n)
% Gather the two prefilled sections of a GitHub bug report.
%
% Parameters:
%	MaxLogLines	- Lines of the current error log to take from its end
%                 (default 120). A first pass only: epsych.RunExpt.issueURL
%                 trims further when the encoded URL would be too long.
%
% Returns:
%	fields	- Struct with fields:
%       environment  - char. Version, host, and session summary block.
%       logs         - char. Tail of the day's error log; '' when there is none.
%       logPath      - char. Full path of that log file; '' when file logging
%                      is disabled, which is what the caller tests to decide
%                      whether a log can be offered at all.
%       logLines     - Lines taken.
%       logTotalLines- Lines the file holds, so the excerpt can say what it omits.
%
% Read defensively throughout: this runs when something has already gone wrong,
% so a backend whose IsConnected getter throws must cost one line of the report
% rather than the report.
%
% See also: epsych.RunExpt.ReportIssue, epsych.RunExpt.issueURL, EPsychInfo

arguments
    self
    opts.MaxLogLines (1,1) double {mustBeInteger, mustBePositive} = 120
end

fields = struct('environment','','logs','','logPath','', ...
    'logLines',0,'logTotalLines',0);

fields.environment = self.issueEnvironmentText_();

% Flush first: the file sink buffers, so without this the excerpt ends several
% messages before the failure the operator is reporting.
L = eplog.Logger.instance();
L.flush();
logPath = char(string(L.LogFile));
if isempty(logPath) || ~isfile(logPath)
    return
end
fields.logPath = logPath;

try
    txt = fileread(logPath);
catch ME
    vprintf(0,1,ME);
    return
end

lines = splitlines(string(txt));
if strlength(lines(end)) == 0
    lines(end) = [];
end
fields.logTotalLines = numel(lines);

n = min(opts.MaxLogLines, numel(lines));
fields.logLines = n;
fields.logs = char(join(lines(end-n+1:end), newline));
end
