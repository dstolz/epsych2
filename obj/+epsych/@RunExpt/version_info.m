function version_info(self)
% obj.version_info
% Display toolbox version metadata in a dedicated dialog window.
fig = findall(groot,'Type','figure','-and','Tag','RunExptVersionInfo');
if ~isempty(fig) && isgraphics(fig(1))
    fig = fig(1);
    fig.Visible = 'on';
    movegui(fig,'onscreen');
    return
end

E = EPsychInfo;
checksumText = self.formatVersionChecksum(E.chksum);
commitText = self.formatVersionTimestamp(E.commitTimestamp);

% The worktree row is shown only when this checkout is one, so the ordinary
% case is not cluttered by a field that is always empty.
worktreeText = E.worktree;
showWorktree = ~isempty(worktreeText);

fig = uifigure('Name','EPsych Version Info', ...
    'Tag','RunExptVersionInfo', ...
    'Position',[100 100 560 520], ...
    'Resize','off', ...
    'Color',[0.97 0.98 1.00]);
movegui(fig,'center');

rootGrid = uigridlayout(fig,[3 1]);
rootGrid.RowHeight = {92,'1x',44};
rootGrid.ColumnWidth = {'1x'};
rootGrid.RowSpacing = 12;
rootGrid.Padding = [18 18 18 18];
rootGrid.BackgroundColor = fig.Color;

headerPanel = uipanel(rootGrid,'BorderType','none', ...
    'BackgroundColor',[0.13 0.25 0.47]);
headerPanel.Layout.Row = 1;

headerGrid = uigridlayout(headerPanel,[2 1]);
headerGrid.RowHeight = {'fit','fit'};
headerGrid.ColumnWidth = {'1x'};
headerGrid.RowSpacing = 4;
headerGrid.Padding = [16 14 16 14];
headerGrid.BackgroundColor = headerPanel.BackgroundColor;

titleLink = uihyperlink(headerGrid, ...
    'Text','EPsych', ...
    'URL',E.RepositoryURL);
titleLink.FontSize = 24;
titleLink.FontWeight = 'bold';
titleLink.FontColor = [1 1 1];
uilabel(headerGrid, ...
    'Text',sprintf('Version %s   Data %s',E.Version,E.DataVersion), ...
    'FontSize',13, ...
    'FontColor',[0.89 0.93 1.00]);

cardPanel = uipanel(rootGrid,'BorderType','none', ...
    'BackgroundColor',[1 1 1], ...
    'Scrollable','on');
cardPanel.Layout.Row = 2;

nRows = 9 + showWorktree;

cardGrid = uigridlayout(cardPanel,[nRows 2]);
cardGrid.ColumnWidth = {140,'1x'};
cardGrid.RowHeight = repmat({'fit'},1,nRows);
cardGrid.RowSpacing = 8;
cardGrid.ColumnSpacing = 14;
cardGrid.Padding = [16 16 16 12];
cardGrid.BackgroundColor = cardPanel.BackgroundColor;

self.addVersionInfoRow(cardGrid,1,'Author',E.Author);
self.addVersionInfoLinkRow(cardGrid,2,'Email',E.AuthorEmail,['mailto:' E.AuthorEmail]);
self.addVersionInfoLinkRow(cardGrid,3,'License',E.License,E.LicenseURL);
self.addVersionInfoRow(cardGrid,4,'Copyright',E.Copyright);
self.addVersionInfoRow(cardGrid,5,'Latest Commit',commitText);
self.addVersionInfoRow(cardGrid,6,'Checksum',checksumText);
row = 6;
if showWorktree
    row = row + 1;
    self.addVersionInfoRow(cardGrid,row,'Worktree',worktreeText);
end
self.addVersionInfoLinkRow(cardGrid,row+1,'Repository', ...
    'GitHub Repository',E.RepositoryURL);
self.addVersionInfoLinkRow(cardGrid,row+2,'History', ...
    'Commit History Overview',E.CommitHistoryURL);
self.addVersionInfoLinkRow(cardGrid,row+3,'Wiki', ...
    'Repository Wiki',E.WikiURL);

footerGrid = uigridlayout(rootGrid,[1 2]);
footerGrid.Layout.Row = 3;
footerGrid.ColumnWidth = {'1x',90};
footerGrid.RowHeight = {'1x'};
footerGrid.Padding = [0 0 0 0];
footerGrid.BackgroundColor = fig.Color;

uilabel(footerGrid, ...
    'Text','Links open in your default browser.', ...
    'FontAngle','italic', ...
    'FontColor',[0.35 0.39 0.46]);

uibutton(footerGrid,'push', ...
    'Text','Close', ...
    'ButtonPushedFcn', @(~,~) delete(fig));
end
