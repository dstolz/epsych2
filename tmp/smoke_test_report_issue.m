function smoke_test_report_issue()
% smoke_test_report_issue()
% Exercise the Help > Report an Issue path: the URL builder's encoding and
% its trim-to-fit rule (headless), then the gathered report and the preview
% dialog against a real RunExpt window.
%
% The dialog is built and inspected but its Open Issue button is never
% pressed: that opens a browser on a public tracker.
%
%   matlab -batch "run('tmp/smoke_test_report_issue.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

% 1. URL shape ------------------------------------------------------------
s = struct('environment',sprintf('EPsych : v2\nHost   : RIG-1'), ...
    'logs',sprintf('first line\nsecond line'));
[url, trimmed] = epsych.RunExpt.issueURL(s);
assert(trimmed == 0, 'a two-line excerpt must not be trimmed');
assert(contains(url,'template=bug_report.yml'), 'the form template must be named');
assert(contains(url,'&environment=') && contains(url,'&logs='), 'both sections must be prefilled');
assert(~contains(url,'+'), 'spaces must encode as %%20, not +');
decoded = urldecode(extractAfter(url,'&logs='));
assert(contains(decoded,'first line') && contains(decoded,'```text'), ...
    'the excerpt must arrive fenced and intact');
fprintf('PASS: prefilled URL names the form and carries both sections (%d chars)\n', numel(url));

% 2. Empty excerpt is omitted rather than sent as an empty fence ----------
[url2, trimmed2] = epsych.RunExpt.issueURL(struct('environment','EPsych : v2','logs',''));
assert(~contains(url2,'&logs='), 'an empty excerpt must not produce a logs parameter');
assert(trimmed2 == 0);
fprintf('PASS: an omitted excerpt leaves the logs field to the form''s placeholder\n');

% 3. Trim to fit, keeping the END of the log -----------------------------
lines = arrayfun(@(k) sprintf('2026-08-19 10:00:00 [debug] trial %d: C:\\data\\subj\\f_%d.mat', k, k), ...
    1:2000, 'uni', 0);
big = struct('environment','EPsych : v2','logs',strjoin(lines,newline));
[url3, trimmed3] = epsych.RunExpt.issueURL(big);
assert(numel(url3) <= 6000, 'the URL must respect the default budget');
assert(trimmed3 > 0, 'a 2000-line excerpt must report what it dropped');
kept = splitlines(string(urldecode(extractAfter(url3,'&logs='))));
assert(contains(kept(2),'earlier line(s) omitted'), 'trimming must say so in the excerpt');
assert(contains(kept(end-1),'trial 2000'), 'the newest line must survive trimming');
fprintf('PASS: over-long excerpt trims from the head to %d chars, dropping %d line(s)\n', ...
    numel(url3), trimmed3);

% A budget nothing fits in still yields a usable link.
[url4, trimmed4] = epsych.RunExpt.issueURL(big, MaxLength=400);
assert(numel(url4) <= 400 || ~contains(url4,'&logs='), ...
    'an impossible budget must drop the excerpt rather than overrun');
fprintf('PASS: an impossible budget drops the excerpt entirely (%d chars, %d line(s) dropped)\n', ...
    numel(url4), trimmed4);

% 4. Gathered report and preview dialog ----------------------------------
rx = epsych.RunExpt(ReuseExisting=false, CleanupStaleFigures=false, BringToFront=false);
cleanupObj = onCleanup(@() cleanupAll(rx));

fields = rx.issueReportFields(MaxLogLines=25);
assert(contains(fields.environment,'EPsych'), 'the environment block must name the toolbox');
assert(contains(fields.environment,'MATLAB'), 'the environment block must name the MATLAB release');
assert(contains(fields.environment,'Session state'), 'the environment block must report session state');
assert(fields.logLines <= 25, 'MaxLogLines must cap the first pass');
fprintf('PASS: report gathered (%d environment chars, %d of %d log lines, log=%s)\n', ...
    numel(fields.environment), fields.logLines, fields.logTotalLines, ...
    string(missing_if_empty(fields.logPath)));

rx.ReportIssue();
dlg = findall(groot,'Type','figure','-and','Tag','RunExptReportIssue');
assert(isscalar(dlg), 'the preview dialog must open exactly once');
areas = findall(dlg,'Type','uitextarea');
assert(numel(areas) == 2, 'the preview must show both sections for review');
boxes = findall(dlg,'Type','uicheckbox');
assert(numel(boxes) == 3, 'the excerpt opt-in and both full-log offers must be present');
labels = string(get(findall(dlg,'Type','uilabel'),'Text'));
assert(any(contains(labels,'Link:')), 'the dialog must report the link size');
fprintf('PASS: preview dialog shows both sections, %d option(s), and the link size\n', numel(boxes));

% Reopening focuses the one dialog rather than composing a second report.
rx.ReportIssue();
assert(isscalar(findall(groot,'Type','figure','-and','Tag','RunExptReportIssue')), ...
    'a second invocation must reuse the open dialog');
fprintf('PASS: a second invocation reuses the open dialog\n');

% 5. Query encoding and the two Help menu items --------------------------
% RequestFeature itself is not called: it opens a browser on the tracker.
assert(strcmp(epsych.RunExpt.encodeQueryValue('a b+c'),'a%20b%2Bc'), ...
    'a space must encode as %%20 and a literal + as %%2B');
menuLabels = string(get(findall(rx.H.figure1,'Type','uimenu'),'Text'));
assert(any(menuLabels == "Report an Issue..."), 'Help must offer the bug report');
assert(any(menuLabels == "Request a Feature..."), 'Help must offer the feature request');
fprintf('PASS: query encoding is exact and both Help menu items are wired\n');

shot = fullfile(tempdir,'report_issue_dialog.png');
try
    exportapp(dlg, shot);
    fprintf('Screenshot: %s\n', shot);
catch ME
    fprintf('(screenshot skipped: %s)\n', ME.message);
end

fprintf('\nALL CHECKS PASSED\n');
end

% -----------------------------------------------------------------------
function s = missing_if_empty(p)
if isempty(p), s = "(file logging disabled)"; else, s = string(p); end
end

% -----------------------------------------------------------------------
function cleanupAll(rx)
% close() rather than delete(): the session window's own close sequence tears
% down its timer, recorder, and status bar.
delete(findall(groot,'Type','figure','-and','Tag','RunExptReportIssue'));
try
    close(rx.H.figure1);
catch ME
    vprintf(0,1,ME);
end
end
