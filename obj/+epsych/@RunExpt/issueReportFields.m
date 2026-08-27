function fields = issueReportFields(self, opts)
% fields = obj.issueReportFields()
% fields = obj.issueReportFields(MaxLogLines=n)
% Gather the two prefilled sections of a GitHub bug report.
%
% The log excerpt is granary's -- it owns the logger, so it is the only thing
% that can flush it and find the current file. What stays here is the half a
% library cannot know: what THIS session is doing, which
% epsych.RunExpt.issueEnvironmentText_ builds and this passes in.
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
% See also: epsych.RunExpt.ReportIssue, epsych.RunExpt.issueURL,
%           granary.report.fields, EPsychInfo

arguments
    self
    opts.MaxLogLines (1,1) double {mustBeInteger, mustBePositive} = 120
end

fields = granary.report.fields( ...
    Environment = self.issueEnvironmentText_(), ...
    MaxLogLines = opts.MaxLogLines);
end
