function [url, trimmedLines] = issueURL(fields, opts)
% url = epsych.RunExpt.issueURL(fields)
% [url, trimmedLines] = epsych.RunExpt.issueURL(fields, MaxLength=n)
% Build the prefilled URL of the repository's bug-report issue form.
%
% GitHub's issue forms are prefilled by query parameters named for the field
% ids in .github/ISSUE_TEMPLATE/bug_report.yml, so a report travels as TEXT IN
% A URL: nothing is uploaded, no credentials are needed, and equally, no file
% can be attached this way and the whole report must fit in a request line.
% Over-long URLs are answered with 414, so the log excerpt is trimmed from its
% start -- the end of a log is the part describing the failure -- until it fits,
% and the operator is pointed at the clipboard and the file for the rest.
%
% Parameters:
%	fields	- Struct from epsych.RunExpt.issueReportFields; only .environment
%             and .logs are read, so a caller may pass edited text.
%	MaxLength	- Character budget for the whole URL (default 6000).
%                 Conservative: GitHub itself accepts more, but proxies and
%                 the shell hand-off in web() are the narrower limits.
%
% Returns:
%	url	- Full https URL to open in a browser.
%	trimmedLines	- Lines dropped from the head of the excerpt to fit; 0 when
%                     the whole excerpt survived.
%
% Both sections are wrapped in a fenced code block here rather than by the
% caller, so what the operator reviews in the preview is the text itself.
%
% See also: epsych.RunExpt.ReportIssue, epsych.RunExpt.issueReportFields

arguments
    fields (1,1) struct
    opts.MaxLength (1,1) double {mustBeInteger, mustBePositive} = 6000
end

base = [EPsychInfo.NewIssueURL '?template=bug_report.yml'];

envText = char(string(fields.environment));
logText = char(string(fields.logs));

trimmedLines = 0;
if isempty(strtrim(logText))
    url = localAssemble(base, envText, '');
    return
end

logLines = splitlines(string(logText));
url = localAssemble(base, envText, localFence(char(join(logLines, newline))));

% Drop a tenth of what remains per pass: one line at a time is thousands of
% urlencode calls on a long log, and the exact cut point does not matter.
while numel(url) > opts.MaxLength && numel(logLines) > 1
    drop = max(1, floor(numel(logLines)/10));
    logLines(1:drop) = [];
    trimmedLines = trimmedLines + drop;
    marker = sprintf('[... %d earlier line(s) omitted so the report fits in a URL ...]', trimmedLines);
    url = localAssemble(base, envText, localFence(char(join([string(marker); logLines], newline))));
end

% Nothing left to drop but still too long: the environment block alone is over
% budget, which means an operator pasted into it. Send it without the log
% rather than send a URL the server will refuse.
if numel(url) > opts.MaxLength
    trimmedLines = trimmedLines + numel(logLines);
    url = localAssemble(base, envText, '');
end
end

% -----------------------------------------------------------------------
function url = localAssemble(base, envText, fencedLog)
% Join the query parameters, omitting an empty section entirely so the form
% shows its own placeholder instead of an empty code fence.
url = base;
if ~isempty(strtrim(envText))
    url = [url '&environment=' epsych.RunExpt.encodeQueryValue(localFence(envText))];
end
if ~isempty(fencedLog)
    url = [url '&logs=' epsych.RunExpt.encodeQueryValue(fencedLog)];
end
end

% -----------------------------------------------------------------------
function s = localFence(text)
% Wrap in a plain code fence. The form's textareas are unrendered on purpose:
% a log line's backslashes and underscores would otherwise be read as markdown.
s = sprintf('```text\n%s\n```', text);
end
