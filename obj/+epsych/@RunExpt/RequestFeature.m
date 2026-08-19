function RequestFeature(self)
% obj.RequestFeature
% Open the repository's feature-request form in the default browser.
%
% Unlike epsych.RunExpt.ReportIssue there is no preview, because there is
% nothing to review: the only thing prefilled is a Version line -- EPsych
% version, commit, and MATLAB release -- and none of the session's config
% paths, subject names, or log lines go with it. Which commit a request was
% written against is worth having anyway, since the feature may already exist
% further along master.
%
% See also: epsych.RunExpt.ReportIssue, epsych.RunExpt.encodeQueryValue

E = EPsychInfo;
try
    versionText = sprintf('EPsych v%s, commit %s (%s), MATLAB %s', ...
        E.Version, self.formatVersionChecksum(E.chksum), ...
        self.formatVersionTimestamp(E.commitTimestamp), version('-release'));
catch ME
    vprintf(0,1,ME);
    versionText = sprintf('EPsych v%s, MATLAB %s', E.Version, version('-release'));
end

url = sprintf('%s?template=feature_request.yml&version=%s', ...
    EPsychInfo.NewIssueURL, epsych.RunExpt.encodeQueryValue(versionText));

try
    web(url,'-browser');
catch ME
    vprintf(0,1,ME);
    uialert(self.H.figure1, sprintf(['Unable to open the browser.\n\n' ...
        'Open a feature request at %s instead.'], EPsychInfo.IssuesURL), ...
        'Request a Feature');
    return
end

vprintf(1,'Feature request form opened in browser')
self.setStatus('Feature request form opened in your browser.');
end
