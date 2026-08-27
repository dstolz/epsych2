function [url, trimmedLines] = issueURL(fields, opts)
% url = epsych.RunExpt.issueURL(fields)
% [url, trimmedLines] = epsych.RunExpt.issueURL(fields, MaxLength=n)
% Build the prefilled URL of the repository's bug-report issue form.
%
% Names this repository's tracker and hands the rest to granary.report.url,
% which does the fencing, the encoding, and the trimming. Kept as a method
% rather than called directly from ReportIssue so there is one place that says
% which repository and which form EPsych reports against.
%
% GitHub's issue forms are prefilled by query parameters named for the field
% ids in .github/ISSUE_TEMPLATE/bug_report.yml, so a report travels as TEXT IN
% A URL: nothing is uploaded, no credentials are needed, and equally, no file
% can be attached this way and the whole report must fit in a request line.
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
% See also: epsych.RunExpt.ReportIssue, epsych.RunExpt.issueReportFields,
%           granary.report.url, granary.report.Tracker

arguments
    fields (1,1) struct
    opts.MaxLength (1,1) double {mustBeInteger, mustBePositive} = 6000
end

tracker = granary.report.Tracker(EPsychInfo.RepositoryURL, ...
    Template = 'bug_report.yml');

[url, trimmedLines] = granary.report.url(fields, tracker, ...
    MaxLength = opts.MaxLength);
end
