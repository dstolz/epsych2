function file = exportFigure(self, file)
% file = exportFigure(self, file)
% Save the figure on the tab in front -- the staircase on the Session tab,
% the threshold timeline on the Subject tab, the comparison on the Compare
% tab -- with exportgraphics. The format follows the extension (.png,
% .pdf, .svg). file "" asks, starting in the last export folder with the
% last format chosen (FigureFormat, ExportFolder prefs).
%
% Returns:
%   file - what was written ("" when nothing was)
%
% See also: exportgraphics, epsych.BehaviorAnalysis.exportTables
arguments
    self
    file (1,1) string = ""
end

ax = self.figureTarget_();
if isempty(ax)
    self.alert_("The " + self.currentTab() + " tab has no figure to export. " + ...
        "Choose the Session, Subject or Compare tab.", 'Export Figure', 'info');
    file = "";
    return
end

if file == ""
    if ~self.isVisible_(), return, end
    fmt = string(self.getPref_('FigureFormat', "png"));
    if ~ismember(fmt, ["png" "pdf" "svg"]), fmt = "png"; end
    folder = string(self.getPref_('ExportFolder', pwd));
    others = setdiff(["png" "pdf" "svg"], fmt, 'stable');
    filters = cellfun(@(e) {['*.' e], [upper(e) ' image (*.' e ')']}, cellstr([fmt others]), 'UniformOutput', false);
    filters = vertcat(filters{:});
    [n, p] = uiputfile(filters, 'Export Figure', char(fullfile(folder, self.figureName_() + "." + fmt)));
    figure(self.H.figure);
    if isequal(n, 0)
        file = "";
        return
    end
    file = string(fullfile(p, n));
    [~, ~, e] = fileparts(file);
    self.setPref_('FigureFormat', char(extractAfter(lower(e), 1)));
    self.setPref_('ExportFolder', char(p));
end

[~, ~, e] = fileparts(file);
e = lower(e);
if ~ismember(e, [".png" ".pdf" ".svg"])
    error('epsych:BehaviorAnalysis:FigureFormat', ...
        'Export a figure as .png, .pdf or .svg (not "%s").', e);
end
if e == ".png"
    args = {'Resolution', 200};
else
    args = {'ContentType', 'vector'};
end
% A tab that was behind has not been laid out yet; exportgraphics then copies
% a legend whose computed icon width is 0 and refuses it. drawnow lays it out.
drawnow
exportgraphics(ax, file, args{:});
self.setStatus_("Wrote " + file);

end
