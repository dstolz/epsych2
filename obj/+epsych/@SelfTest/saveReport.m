function ffn = saveReport(self, results, ffn)
% ffn = saveReport(self, results)
% ffn = saveReport(self, results, ffn)
% Write the plain-text report to disk.
%
% Reports default to the eplog log directory alongside the daily text log,
% so a rig's diagnostics all live in one place.
%
% Parameters:
%	self	- epsych.SelfTest instance.
%	results	- Result struct array returned by run().
%	ffn	- Destination file. Default: .error_logs/selftest_<timestamp>.txt
%
% Returns:
%	ffn	- Full path of the file written.
%
% See also: epsych.SelfTest.formatReport, epsych.RunExpt.OpenCurrentErrorLog
arguments
    self
    results struct
    ffn (1,1) string = ""
end

if strlength(ffn) == 0
    % Same directory the logger writes to, resolved the same way, so the
    % report cannot land somewhere the daily log does not.
    logDir = eplog.defaultLogDir();
    if ~isfolder(logDir)
        mkdir(logDir);
    end
    stamp = char(datetime('now', Format='yyMMdd''T''HHmmss'));
    ffn = string(fullfile(logDir, sprintf('selftest_%s.txt', stamp)));
end

pth = fileparts(ffn);
if strlength(pth) > 0 && ~isfolder(pth)
    mkdir(pth);
end

fid = fopen(ffn, 'wt');
if fid < 0
    error('epsych:SelfTest:ReportWriteFailed', ...
        'Could not open "%s" for writing.', ffn);
end
closeFile = onCleanup(@() fclose(fid));

fprintf(fid, '%s\n', self.formatReport(results));

vprintf(0, 'Self-test report saved: %s', ffn)

end
