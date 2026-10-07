function files = exportTables(self, folder, options)
% files = exportTables(self, folder)
% files = exportTables(self, folder, Formats = ["csv" "xlsx"], Tables = [...], Prefix = "epsych_")
% Write the tidy tables of the analysed sessions (checked and not hidden;
% every visible session when none is checked): behavior.Export.tables over
% behavior.Study.results, then behavior.Export.write.
%
% Parameters:
%   folder  - destination ("" asks, when the window is shown)
%   Formats - any of "csv", "xlsx", "mat" (default csv)
%   Tables  - which tables (default every behavior.Export.TABLES)
%   Prefix  - file-name prefix (default "epsych_")
%
% Returns:
%   files - string column, every path written ([] when nothing was)
%
% See also: behavior.Export, gui.behavior.ExportDialog
arguments
    self
    folder (1,1) string = ""
    options.Formats (1,:) string = "csv"
    options.Tables (1,:) string = behavior.Export.TABLES
    options.Prefix (1,1) string = "epsych_"
end

files = strings(0, 1);
if isempty(self.Study)
    return
end
if folder == ""
    if ~self.isVisible_(), return, end
    d = uigetdir(char(self.getPref_('ExportFolder', pwd)), 'Export the tables into');
    figure(self.H.figure);
    if isequal(d, 0), return, end
    folder = string(d);
end

keys = self.analysedKeys();
scope = "checked";
if isempty(keys)
    keys = self.Study.visibleKeys();
    scope = "visible";
end
if isempty(keys)
    self.alert_('There are no sessions to export.', 'Export Tables', 'info');
    return
end

dlg = self.progress_('Export Tables', 'Analysing sessions...');
closeDlg = onCleanup(@() epsych.BehaviorAnalysis.closeDialog_(dlg));
[T, R] = self.Study.results(keys, Progress = @(k, n) epsych.BehaviorAnalysis.progressStep_(dlg, k, n, 'Analysing session'));
if ~isempty(dlg) && isvalid(dlg)
    dlg.Message = 'Writing the tables...';
    dlg.Indeterminate = 'on';
end
Tbls = behavior.Export.tables(T, R, Tables = options.Tables, Subjects = self.Study.Catalog.Subjects);
files = behavior.Export.write(Tbls, folder, Formats = options.Formats, Prefix = options.Prefix);
clear closeDlg

self.setStatus_(sprintf("Exported %d %s session(s) to %s: %d file(s).", height(T), scope, folder, numel(files)));

end
