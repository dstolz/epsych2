function ok = rescan(self)
% ok = rescan(self)
% Look at the root again: new, changed and removed files (unchanged ones
% come from the scan cache). Refused while a session is running, because
% describing files reads each of them on the thread the trial loop's timer
% runs on (gui.SessionBrowser.sessionIsRunning).
%
% Returns:
%   ok - the scan completed (false when refused, cancelled or failed)
%
% See also: behavior.Study.rescan, behavior.Catalog.scan

ok = false;
if isempty(self.Study)
    return
end
if gui.SessionBrowser.sessionIsRunning()
    self.alert_(['A session is running. The root can be scanned once it has stopped; ' ...
        'Review Session... is still available.'], 'Rescan', 'warning');
    return
end

dlg = self.progress_('Scanning', "Looking for sessions under " + self.Study.Root + "...");
closeDlg = onCleanup(@() epsych.BehaviorAnalysis.closeDialog_(dlg));
t0 = tic;
try
    ok = self.Study.rescan(Progress = @(k, n) epsych.BehaviorAnalysis.progressStep_(dlg, k, n, 'Reading file'));
catch ME
    vprintf(0, 1, ME);
    self.alert_("The scan failed: " + string(ME.message), 'Rescan', 'error');
    return
end
clear closeDlg

C = self.Study.Catalog;
if ok
    self.setStatus_(sprintf("Scanned %s in %.1f s: %d session(s), %d file(s) read, cache %s.", ...
        C.Root, toc(t0), height(C.Sessions), C.LastScanReads, C.CacheState));
else
    self.setStatus_("Scan cancelled; the list is as it was.");
end
self.refreshHeader_();

end
