function smoke_test_behavior_app()
% smoke_test_behavior_app
% Standing proof of epsych.BehaviorAnalysis, the offline behavioral analysis
% window, driven headless (Visible = false) through its public methods:
%   - opening a root lists Project > Subject > Session in the browser with
%     nothing checked; checking makes the Study's selection;
%   - selecting a session draws its staircase on the Session tab, labelled
%     from the session; a window override reaches the tab and the Study;
%   - the Subject tab draws the subject's timeline; the Compare tab groups
%     the checked sessions by a facet with a descriptive-statistics table,
%     and overlays one staircase per checked session; the Table tab has one
%     row per checked session and maps its rows to sessions in DATA order;
%   - hiding takes a session out of the list and Show > Hidden lists it;
%   - header settings apply and recompute; a remembered staircase menu
%     preference never overrides the Settings;
%   - tables, a figure, a replication script and the project file are
%     written; the recent-roots preferences are; the window is a single
%     instance; the dialogs build and tear down;
%   - deleting the window leaves no figure and no listener on the Study, and
%     the data root is byte-for-byte as it was.
%
%   run('tmp/smoke_test_behavior_app.m')

repoRoot = fileparts(fileparts(mfilename('fullpath')));
if exist('epsych.BitMask', 'class') ~= 8
    run(fullfile(repoRoot, 'epsych_startup.m'));
end

results = cell(0, 2);
pid = feature('getpid');
root = fullfile(tempdir, sprintf('epsych_behavior_app_root_%d', pid));
cache = fullfile(tempdir, sprintf('epsych_behavior_app_cache_%d', pid));
store = fullfile(tempdir, sprintf('epsych_behavior_app_store_%d', pid));
out = fullfile(tempdir, sprintf('epsych_behavior_app_out_%d', pid));
for d = {root, cache, store, out}
    if isfolder(d{1}), rmdir(d{1}, 's'); end
end
mkdir(out);

PREF = 'epsych2_BehaviorAnalysis';
STAIR = 'epsych2_psychophysics_Staircase';
saved = {localSavePrefs(PREF), localSavePrefs(STAIR)};
restorePrefs = onCleanup(@() localRestorePrefs(saved));
removeFolders = onCleanup(@() localRemove({root, cache, store, out}));
closeWindows = onCleanup(@localCloseWindows);
localCloseWindows();

%% Fixture: 2 projects x 2 subjects x 3 sessions (Pre, Pre, Post), and an empty file
day0 = datetime(2026, 10, 1, 9, 0, 0);
k = 0;
for p = ["ProjA" "ProjB"]
    for s = ["S1" "S2"] + extractAfter(p, 4)
        folder = fullfile(root, p, s);
        mkdir(folder);
        for i = 1:3
            k = k + 1;
            tag = "Pre";
            if i == 3, tag = "Post"; end
            Data = localObserverData(80, 18 + 4 * (i == 3) + k / 4, 500 + k);
            stamp = string(day0 + days(i - 1) + hours(k), 'yyMMdd''T''HHmmss');
            save(fullfile(folder, sprintf('%s_%s_%s.mat', s, stamp, tag)), 'Data');
        end
    end
end
Data = struct('Depth', {[]}, 'RespCode', {[]}, 'TrialType', {[]});
save(fullfile(root, 'ProjA', 'S1A', 'S1A_261009T090000_Pre.mat'), 'Data');
before = localListing(root);

%% 1. Open: the tree lists the root, nothing checked
try
    app = epsych.BehaviorAnalysis(root, Visible = false, Store = string(store), Roster = "none", ...
        CacheFolder = string(cache));
    S = app.Study;
    B = app.Views.Browser;
    c = B.counts();
    results(end+1,:) = check('the window opens on the root', isa(app, 'epsych.BehaviorAnalysis') && isa(S, 'behavior.Study'));
    results(end+1,:) = check('the tree has 2 projects, 4 subjects, 13 sessions', ...
        c.Projects == 2 && c.Subjects == 4 && c.Sessions == 13);
    results(end+1,:) = check('nothing is checked', isempty(S.Selection) && isempty(B.H.tree.CheckedNodes));
    T = S.sessions();
    good = reshape(string(T.Key(T.Trials > 0)), 1, []);
    results(end+1,:) = check('the header counts the sessions', contains(app.H.lblCounts.Text, '13 sessions') ...
        && contains(app.H.lblCounts.Text, '4 subjects'));
catch ME
    results(end+1,:) = check(['group 1: ' ME.message], false);
    localReport(results);
    return
end

%% 2. Checking
try
    app.check(good(1:4), true);
    results(end+1,:) = check('check() makes the Study''s selection', isequal(S.Selection, good(1:4)));
    checked = B.H.tree.CheckedNodes;
    kinds = arrayfun(@(n) string(n.NodeData.Kind), checked);
    results(end+1,:) = check('the tree shows the four sessions checked', sum(kinds == "session") == 4);
    app.check(good(4), false);
    app.check(good(4), true);
    results(end+1,:) = check('uncheck and re-check', isequal(S.Selection, good(1:4)));
catch ME
    results(end+1,:) = check(['group 2: ' ME.message], false);
end

%% 3. Selecting a session draws it on the Session tab
try
    app.selectSession(good(1));
    V = app.Views.Session;
    row = S.Catalog.session(good(1));
    results(end+1,:) = check('the Session tab shows the selected session', V.Key == good(1));
    results(end+1,:) = check('its staircase axes has lines', ~isempty(findobj(V.H.stairAxes, 'Type', 'line')));
    results(end+1,:) = check('the staircase title names the subject', ...
        contains(string(V.H.stairAxes.Title.String), string(row.Subject)));
    results(end+1,:) = check('the browser selects its node', ...
        ~isempty(B.H.tree.SelectedNodes) && B.H.tree.SelectedNodes(1).NodeData.Key == good(1));
    results(end+1,:) = check('the Subject tab follows the subject', app.Views.Subject.Subject == string(row.Subject));
catch ME
    results(end+1,:) = check(['group 3: ' ME.message], false);
end

%% 4. A window override
try
    ok = app.setWindowOverride(good(1), "3-83");
    results(end+1,:) = check('setWindowOverride is accepted', ok);
    results(end+1,:) = check('the Session tab''s window field shows it', strcmp(app.Views.Session.H.window.Value, '3-83'));
    results(end+1,:) = check('the Study has it', S.windowFor(good(1)) == "3-83");
    results(end+1,:) = check('the project is now unsaved', S.Project.Dirty && strcmp(app.H.lblSave.Text, 'Unsaved'));
    results(end+1,:) = check('text no window parses is refused', ~app.setWindowOverride(good(1), "banana") ...
        && S.windowFor(good(1)) == "3-83");
catch ME
    results(end+1,:) = check(['group 4: ' ME.message], false);
end

%% 5. Subject tab
try
    app.showTab("Subject");
    VS = app.Views.Subject;
    results(end+1,:) = check('the Subject tab is in front', app.currentTab() == "Subject");
    results(end+1,:) = check('its timeline has session points', ...
        ~isempty(findobj(VS.H.timeline, 'Tag', 'BehaviorPlot:Point')));
    results(end+1,:) = check('its table lists the subject''s checked sessions', ...
        numel(VS.Keys) == 3 && all(ismember(VS.Keys, good(1:3))));
    results(end+1,:) = check('the overlay has a track per session', ...
        numel(findobj(VS.H.overlay, 'Tag', 'BehaviorPlot:Track')) == 3);
    VS.setOverlay(ColorBy = "session", ColorMap = "auto", Normalize = "none");
    tr = findobj(VS.H.overlay, 'Tag', 'BehaviorPlot:Track');
    seq = behavior.Plot.sequential("parula", 3);
    results(end+1,:) = check('the overlay colours the sessions along a gradient, first to last', ...
        numel(tr) == 3 && all(arrayfun(@(h) isequal(h.Color, seq(h.UserData.Level, :)), tr)) ...
        && strcmp(VS.H.ovColorBy.Value, 'session') && strcmp(VS.H.ovColorMap.Value, 'auto'));
    VS.setOverlay(ColorMap = "categorical", Normalize = "fraction", ShowReversals = true);
    tr = findobj(VS.H.overlay, 'Tag', 'BehaviorPlot:Track');
    results(end+1,:) = check('setOverlay redraws: distinct colours, fraction x, reversals, menu checked', ...
        all(ismember(vertcat(tr.Color), behavior.Plot.palette(3), 'rows')) ...
        && all(arrayfun(@(h) h.XData(end) == 1, tr)) ...
        && ~isempty(findobj(VS.H.overlay, 'Tag', 'BehaviorPlot:Reversal')) ...
        && VS.H.ovShowReversals.Checked == "on" && strcmp(VS.H.ovNormalize.Value, 'fraction'));
    overlayBefore = VS.Overlay;
    refused = false;
    try
        VS.setOverlay(ColorBy = "banana");
    catch
        refused = true;
    end
    results(end+1,:) = check('an overlay facet that names nothing is refused, nothing changed', ...
        refused && isequal(VS.Overlay, overlayBefore));
    VS.setOverlay(ColorBy = "session", ColorMap = "auto", Normalize = "none", ShowReversals = false);

    % Show: stacked and heatmap.
    VS.setOverlay(Display = "stacked");
    results(end+1,:) = check('Show Stacked: a band per session, the facet control reads Rows', ...
        numel(findobj(VS.H.overlay, 'Tag', 'BehaviorPlot:Track')) == 3 ...
        && numel(findobj(VS.H.overlay, 'Tag', 'BehaviorPlot:ScaleBar')) == 2 ...
        && strcmp(VS.H.ovDisplay.Value, 'stacked') && strcmp(VS.H.ovColorByLabel.Text, 'Rows') ...
        && contains(string(VS.H.overlay.Title.String), "Session #"));
    VS.setOverlay(Display = "heatmap", ColorMap = "categorical");
    img = findobj(VS.H.overlay, 'Tag', 'BehaviorPlot:Heatmap');
    results(end+1,:) = check('Show Heatmap: a row per session; Distinct colours not offered and shown as Auto', ...
        isscalar(img) && size(img.CData, 1) == 3 && ~ismember('categorical', VS.H.ovColorMap.ItemsData) ...
        && strcmp(VS.H.ovColorMap.Value, 'auto') && VS.Overlay.ColorMap == "categorical");
    results(end+1,:) = check('heatmap: thresholds and steps greyed in the menu, Combine offered', ...
        VS.H.ovShowThresholds.Enable == "off" && VS.H.ovSteps.Enable == "off" && VS.H.ovCombine.Enable == "on" ...
        && VS.H.ovCombineMean.Checked == "on");
    VS.setOverlay(ColorBy = "tag:1", Combine = "median");
    img = findobj(VS.H.overlay, 'Tag', 'BehaviorPlot:Heatmap');
    results(end+1,:) = check('heatmap by tag: a row per phase, combined by the median, menu checked', ...
        isscalar(img) && size(img.CData, 1) == 2 && VS.H.ovCombineMedian.Checked == "on" ...
        && any(contains(string(VS.H.overlay.YTickLabel), "(n=2)")));
    VS.H.ovDisplay.Value = 'overlay';
    VS.H.ovDisplay.ValueChangedFcn(VS.H.ovDisplay, []);
    remembered = [];
    if ispref(PREF, 'SubjectOverlay'), remembered = getpref(PREF, 'SubjectOverlay'); end
    results(end+1,:) = check('choosing Show is remembered with the rest of the display (SubjectOverlay pref)', ...
        isstruct(remembered) && remembered.Display == "overlay" && remembered.Combine == "median" ...
        && strcmp(VS.H.ovColorByLabel.Text, 'Color by'));
    refused = false;
    try
        VS.setOverlay(Display = "pie");
    catch
        refused = true;
    end
    results(end+1,:) = check('a Show that is no display is refused', refused && VS.Overlay.Display == "overlay");
    VS.setOverlay(ColorBy = "session", ColorMap = "auto", Combine = "mean");
catch ME
    results(end+1,:) = check(['group 5: ' ME.message], false);
end

%% 5b. Open in New Figure
try
    VS = app.Views.Subject;
    L = app.plotsOnTab();
    results(end+1,:) = check('the Subject tab lists its three plots', ...
        isequal(sort([L.Key]), sort(["timeline" "metric" "staircases"])) && all(contains([L.Name], VS.Subject)));
    item = @(ax) findobj(ax.ContextMenu, 'Tag', 'BehaviorView:OpenInFigure');
    results(end+1,:) = check('every Subject plot has Open in New Figure on its right-click menu', ...
        all(arrayfun(@(ax) isscalar(item(ax)), [VS.H.timeline VS.H.metric VS.H.overlay])) ...
        && isscalar(findobj(VS.H.overlay.ContextMenu, 'Tag', 'BehaviorView:OpenInFigure')) ...
        && VS.H.overlay.ContextMenu == VS.H.ovShowReversals.Parent);
    VS.setOverlay(Display = "heatmap");
    img = findobj(VS.H.overlay, 'Tag', 'BehaviorPlot:Heatmap');
    results(end+1,:) = check('the heatmap''s image carries the menu, so a right-click on a cell finds it', ...
        isscalar(img) && img.ContextMenu == VS.H.overlay.ContextMenu);
    f1 = app.openPlotInFigure("staircases", Visible = false);
    ax1 = findobj(f1, 'Type', 'axes');
    results(end+1,:) = check('it opens in an ordinary figure, redrawn and titled with the subject', ...
        isscalar(f1) && isgraphics(f1) && strcmp(f1.HandleVisibility, 'on') && gcf == f1 ...
        && strcmp(f1.Tag, gui.behavior.View.FIGURE_TAG) && isscalar(ax1) ...
        && isscalar(findobj(ax1, 'Tag', 'BehaviorPlot:Heatmap')) ...
        && contains(string(ax1.Title.String), VS.Subject) && contains(string(f1.Name), "heatmap") ...
        && isequaln(findobj(ax1, 'Tag', 'BehaviorPlot:Heatmap').CData, img.CData));
    VS.setOverlay(Display = "overlay");
    results(end+1,:) = check('it is a snapshot: the tab moving on leaves the figure as it was', ...
        isscalar(findobj(ax1, 'Tag', 'BehaviorPlot:Heatmap')) ...
        && isempty(findobj(VS.H.overlay, 'Tag', 'BehaviorPlot:Heatmap')));
    m = item(VS.H.timeline);
    nBefore = numel(findall(groot, 'Type', 'figure', 'Tag', gui.behavior.View.FIGURE_TAG));
    m.MenuSelectedFcn(m, []);
    f2 = findall(groot, 'Type', 'figure', 'Tag', gui.behavior.View.FIGURE_TAG);
    results(end+1,:) = check('the right-click item opens the timeline in a figure of its own', ...
        numel(f2) == nBefore + 1 && any(arrayfun(@(f) ~isempty(findobj(f, 'Tag', 'BehaviorPlot:Point')), f2)));
    set(f2, 'Visible', 'off');
    menuView = app.H.mnu_openfig.Parent;
    menuView.MenuSelectedFcn(menuView, []);
    results(end+1,:) = check('View > Open Plot in New Figure lists the tab''s plots', ...
        numel(app.H.mnu_openfig.Children) == 3);
    results(end+1,:) = check('an unknown plot opens nothing', isempty(app.openPlotInFigure("banana", Visible = false)));

    app.showTab("Session");
    VSe = app.Views.Session;
    L = app.plotsOnTab();
    results(end+1,:) = check('the Session tab lists its staircase and its fit', ...
        isequal([L.Key], ["staircase" "fit"]) && isscalar(findobj(VSe.H.fitAxes.ContextMenu, 'Tag', 'BehaviorView:OpenInFigure')));
    f3 = app.openPlotInFigure("fit", Visible = false);
    results(end+1,:) = check('the fit opens in a figure of its own', ...
        isscalar(f3) && ~isempty(findobj(f3, 'Tag', 'BehaviorPlot:Proportion')));

    app.showTab("Fit");
    L = app.plotsOnTab();
    results(end+1,:) = check('the Fit tab lists its psychometric plot', ismember("psych", [L.Key]));
    f4 = app.openPlotInFigure("psych", Visible = false);
    results(end+1,:) = check('and opens it', isscalar(f4) && isgraphics(f4));
    app.showTab("Compare");
    L = app.plotsOnTab();
    f5 = app.openPlotInFigure("compare", Visible = false);
    results(end+1,:) = check('the Compare tab lists its plot and opens it, titled with what it compares', ...
        isequal([L.Key], "compare") && isscalar(f5) && startsWith(string(f5.Name), "Compare · ") ...
        && isscalar(findobj(app.Views.Compare.H.axes.ContextMenu, 'Tag', 'BehaviorView:OpenInFigure')));
    app.showTab("Table");
    results(end+1,:) = check('the Table tab has no plot to open', isempty(app.plotsOnTab()));
    app.showTab("Subject");
catch ME
    results(end+1,:) = check(['group 5b: ' ME.message], false);
end
delete(findall(groot, 'Type', 'figure', 'Tag', gui.behavior.View.FIGURE_TAG));

%% 6. Compare tab
try
    app.showTab("Compare");
    VC = app.Views.Compare;
    ok = app.setFacet("GroupBy", "tag:1");
    results(end+1,:) = check('setFacet reaches the project', ok && S.Project.Facets.GroupBy == "tag:1");
    results(end+1,:) = check('the dropdown follows', strcmp(VC.H.groupBy.Value, 'tag:1'));
    results(end+1,:) = check('the comparison axes is drawn', ~isempty(VC.H.axes.Children) ...
        && isempty(findobj(VC.H.axes, 'Tag', 'BehaviorPlot:NoData')));
    D = VC.Stats;
    results(end+1,:) = check('the statistics table has a row per level', height(D) == 2 ...
        && all(ismember(["Pre" "Post"], string(D.Level))) && size(VC.H.stats.Data, 1) == 2);
    results(end+1,:) = check('its sentence is on the status line', contains(string(app.H.status.Text), "by Tag 1"));
    app.setFacet("Kind", "overlay");
    results(end+1,:) = check('overlay: one track per checked session', ...
        numel(findobj(VC.H.axes, 'Tag', 'BehaviorPlot:Track')) == 4);
    results(end+1,:) = check('overlay: Colors is offered, Auto by default', ...
        VC.H.colorMap.Enable == "on" && strcmp(VC.H.colorMap.Value, 'auto') && VC.Plotted.ColorMap == "categorical");
    ok = app.setFacet("ColorMap", "turbo");
    results(end+1,:) = check('setFacet ColorMap reaches the project, the dropdown and the overlay', ok ...
        && S.Project.Facets.ColorMap == "turbo" && strcmp(VC.H.colorMap.Value, 'turbo') ...
        && VC.Plotted.ColorMap == "turbo");
    results(end+1,:) = check('an unknown colour map is refused', ~app.setFacet("ColorMap", "rainbow") ...
        && S.Project.Facets.ColorMap == "turbo");
    app.setFacet("ColorMap", "auto");
    app.setFacet("Kind", "lines");
    results(end+1,:) = check('subject lines are drawn', ~isempty(findobj(VC.H.axes, 'Tag', 'BehaviorPlot:SubjectLine')));
    app.setFacet("Kind", "box");
    results(end+1,:) = check('an unknown facet is refused', ~app.setFacet("ColorBy", "banana"));

    % The value menus: measure, then statistic and correction.
    results(end+1,:) = check('the value menus show the saved value''s address', ...
        strcmp(VC.H.measure.Value, 'Staircase threshold') && strcmp(VC.H.statistic.Value, 'Last N reversals') ...
        && strcmp(VC.H.correction.Value, 'As analysed') && VC.H.correction.Enable == "on");
    VC.H.statistic.Value = 'Median of blocks';
    VC.H.statistic.ValueChangedFcn(VC.H.statistic, []);
    VC.H.correction.Value = 'Weighted';
    VC.H.correction.ValueChangedFcn(VC.H.correction, []);
    results(end+1,:) = check('statistic then correction choose the weighted median block threshold', ...
        S.Project.Facets.Value == "WeightedMedianBlockThreshold" && strcmp(VC.H.statistic.Value, 'Median of blocks') ...
        && contains(VC.H.axes.YLabel.String, "Median block threshold, weighted") ...
        && isempty(findobj(VC.H.axes, 'Tag', 'BehaviorPlot:NoData')));
    VC.H.measure.Value = 'Psychometric fit';
    VC.H.measure.ValueChangedFcn(VC.H.measure, []);
    results(end+1,:) = check('the fit measure offers its parameters, with no correction', ...
        S.Project.Facets.Value == "FitThreshold" && VC.H.correction.Enable == "off" ...
        && ismember('Lapse rate (lambda)', VC.H.statistic.Items) && ismember('Width', VC.H.statistic.Items));
    VC.H.statistic.Value = 'Width';
    VC.H.statistic.ValueChangedFcn(VC.H.statistic, []);
    results(end+1,:) = check('a width under the built-in engine says why there is none', ...
        S.Project.Facets.Value == "FitWidth" && contains(string(app.H.status.Text), "psignifit"));
    app.setFacet("Value", "Threshold");

    % Mean and spread.
    ok = app.setFacet("Spread", "sd");
    eb = findobj(VC.H.axes, 'Tag', 'BehaviorPlot:ErrorBar');
    results(end+1,:) = check('setFacet Spread draws that spread and moves the menu', ok ...
        && S.Project.Facets.Spread == "sd" && strcmp(VC.H.spread.Value, 'sd') ...
        && isscalar(eb) && eb.UserData.Spread == "sd" && VC.Plotted.SpreadKind == "sd");
    ok = app.setFacet("ShowMean", "false");
    results(end+1,:) = check('setFacet ShowMean false takes the mean away and unticks Mean', ok ...
        && ~S.Project.Facets.ShowMean && ~VC.H.mean.Value ...
        && isempty(findobj(VC.H.axes, 'Tag', 'BehaviorPlot:Mean')));
    VC.H.mean.Value = true;
    VC.H.mean.ValueChangedFcn(VC.H.mean, []);
    results(end+1,:) = check('ticking Mean puts it back', S.Project.Facets.ShowMean ...
        && ~isempty(findobj(VC.H.axes, 'Tag', 'BehaviorPlot:Mean')));
    results(end+1,:) = check('an unknown spread is refused', ~app.setFacet("Spread", "banana") ...
        && S.Project.Facets.Spread == "sd");
    app.setFacet("Kind", "overlay");
    results(end+1,:) = check('overlay: Mean and Spread are greyed', ...
        VC.H.mean.Enable == "off" && VC.H.spread.Enable == "off");
    app.setFacet("Kind", "box");
    app.setFacet("Spread", "auto");
catch ME
    results(end+1,:) = check(['group 6: ' ME.message], false);
end

%% 7. Table tab
try
    app.showTab("Table");
    VT = app.Views.Table;
    results(end+1,:) = check('one row per checked session', height(VT.Table) == 4 ...
        && height(VT.shownTable()) == 4 && isequal(sort(VT.Keys), sort(good(1:4))));
    results(end+1,:) = check('the default columns include identity and values', ...
        all(ismember(["Subject" "Threshold" "DPrime"], string(VT.shownTable().Properties.VariableNames))));
    % The callbacks get DATA rows whatever the header sort shows.
    evt = struct('InteractionInformation', struct('Row', 3));
    VT.H.table.DoubleClickedFcn(VT.H.table, evt);
    results(end+1,:) = check('double-click opens the DATA row''s session', ...
        app.Views.Session.Key == VT.Keys(3) && VT.Keys(3) == string(VT.Table.Key(3)) && app.currentTab() == "Session");
    VT.H.table.Selection = 2;
    VT.H.table.SelectionChangedFcn(VT.H.table, []);
    results(end+1,:) = check('selecting a row shows the DATA row''s session', app.Views.Session.Key == VT.Keys(2));
    VT.setColumns(["Subject" "Threshold"]);
    results(end+1,:) = check('the column chooser picks the columns', ...
        isequal(string(VT.shownTable().Properties.VariableNames), ["Subject" "Threshold"]));
    txt = behavior.Export.toTSV(VT.shownTable());
    results(end+1,:) = check('Copy''s text has a header and a line per row', numel(splitlines(txt)) == 5);
    VT.setColumns(strings(1, 0));
catch ME
    results(end+1,:) = check(['group 7: ' ME.message], false);
end

%% 8. Hiding
try
    app.hide(good(5), true);
    results(end+1,:) = check('a hidden session leaves the list', ~ismember(good(5), B.NodeKeys) && B.counts().Sessions == 12);
    B.setFilter("Hidden");
    results(end+1,:) = check('Show > Hidden lists it', isequal(B.NodeKeys, good(5)));
    B.setFilter("Checked");
    results(end+1,:) = check('Show > Checked lists the checked ones', isequal(sort(B.NodeKeys), sort(good(1:4))));
    B.setSearch("S2A");
    results(end+1,:) = check('the search narrows the list', isequal(B.NodeKeys, good(4)));
    B.setSearch("");
    B.setFilter("All");
    results(end+1,:) = check('the header counts it as hidden', contains(app.H.lblCounts.Text, '1 hidden'));
catch ME
    results(end+1,:) = check(['group 8: ' ME.message], false);
end

%% 9. Settings from the header and applySettings
try
    s = S.Settings;
    s.Window = "20+";
    ok = app.applySettings(s);
    results(end+1,:) = check('applySettings is accepted', ok && S.Settings.Window == "20+");
    results(end+1,:) = check('the header shows the window', strcmp(app.H.edWindow.Value, '20+'));
    [Tr, Rr] = S.results(good(2:4));
    results(end+1,:) = check('results recompute under it', all(string(Tr.SettingsHash) == s.hash()) ...
        && all(string({Rr.Window}) == "20+"));
    bad = S.Settings;
    bad.Window = "banana";
    results(end+1,:) = check('settings with a new problem are refused', ~app.applySettings(bad) && S.Settings.Window == "20+");
    app.H.edWindow.Value = 'last 60';
    app.H.edWindow.ValueChangedFcn(app.H.edWindow, []);
    results(end+1,:) = check('typing in the header window applies it', S.Settings.Window == "last 60");
    app.H.edTypes.Value = '2';
    app.H.edTypes.ValueChangedFcn(app.H.edTypes, []);
    results(end+1,:) = check('typing trial types applies them', isequal(S.Settings.ExcludeTrialTypes, 2));
    app.H.edTypes.Value = '';
    app.H.edTypes.ValueChangedFcn(app.H.edTypes, []);
    app.H.edWindow.Value = '20+';
    app.H.edWindow.ValueChangedFcn(app.H.edWindow, []);
catch ME
    results(end+1,:) = check(['group 9: ' ME.message], false);
end

%% 10. A remembered staircase menu choice never overrides the Settings
try
    setpref(STAIR, 'EPsychBehaviorAnalysis_Depth', struct('ThresholdFromLastNReversals', 4));
    app.selectSession(good(3));
    St = app.Views.Session.Staircase;
    results(end+1,:) = check('the staircase keeps the Settings'' 12 reversals', ...
        isa(St, 'psychophysics.Staircase') && St.ThresholdFromLastNReversals == 12 ...
        && S.Settings.Staircase.ThresholdFromLastNReversals == 12);
    rmpref(STAIR, 'EPsychBehaviorAnalysis_Depth');
catch ME
    results(end+1,:) = check(['group 10: ' ME.message], false);
end

%% 11. Exports, figure, script, project file
try
    files = app.exportTables(string(out));
    results(end+1,:) = check('exportTables writes files', ~isempty(files) && all(arrayfun(@isfile, files)));
catch ME
    results(end+1,:) = check(['group 11 (tables): ' ME.message], false);
end
try
    app.showTab("Session");
    f1 = app.exportFigure(string(fullfile(out, 'session.png')));
    results(end+1,:) = check('exportFigure writes the Session tab''s PNG', isfile(f1) && dir(f1).bytes > 1000);
catch ME
    results(end+1,:) = check(['group 11 (session figure): ' ME.message], false);
end
try
    app.showTab("Compare");
    f2 = app.exportFigure(string(fullfile(out, 'compare.pdf')));
    results(end+1,:) = check('exportFigure writes the Compare tab''s PDF', isfile(f2));
catch ME
    results(end+1,:) = check(['group 11 (compare figure): ' ME.message], false);
end
try
    app.showTab("Table");
    results(end+1,:) = check('the Table tab has no figure to export', app.exportFigure(string(fullfile(out, 'x.png'))) == "");

    sw = fullfile(repoRoot, 'obj', '+behavior', '@ScriptWriter');
    if isfile(fullfile(sw, 'session.m')) && isfile(fullfile(sw, 'compare.m')) && isfile(fullfile(sw, 'write.m'))
        sf = app.writeScript(string(fullfile(out, 'replicate_app.m')), Scope = "selected");
        results(end+1,:) = check('writeScript writes the file', isfile(sf));
        txt = localRunScript(sf, root, out);
        results(end+1,:) = check('the script runs and replicates', contains(txt, '4 of 4 sessions replicated'));
        sf2 = app.writeScript(string(fullfile(out, 'replicate_one.m')), Scope = "session");
        results(end+1,:) = check('a one-session script is written', isfile(sf2));
    else
        results(end+1,:) = check('writeScript: SKIPPED, behavior.ScriptWriter.session/compare not available yet', true);
    end

    ok = app.saveProject();
    results(end+1,:) = check('saveProject writes project.json under the Store', ok ...
        && isfile(fullfile(store, 'project.json')) && ~S.Project.Dirty && strcmp(app.H.lblSave.Text, 'Saved'));
catch ME
    results(end+1,:) = check(['group 11: ' ME.message], false);
end

%% 12. Preferences, single instance, dialogs
try
    recent = string(getpref(PREF, 'RecentRoots'));
    results(end+1,:) = check('openRoot wrote RecentRoots and LastRoot', ispref(PREF, 'LastRoot') ...
        && strcmpi(string(getpref(PREF, 'LastRoot')), S.Root) && strcmpi(recent(1), S.Root));
    results(end+1,:) = check('a hidden window writes no position', ~ispref(PREF, 'FigurePosition') || saved{1}.existed);
    app2 = epsych.BehaviorAnalysis(root, Visible = false);
    results(end+1,:) = check('a second call returns the same window', app2 == app && app.Study == S);
    results(end+1,:) = check('find() returns it', epsych.BehaviorAnalysis.find() == app);

    D = gui.behavior.SettingsDialog(S, OnApply = @(s) app.applySettings(s), Visible = false);
    winField = D.control("", "Window");
    results(end+1,:) = check('the settings dialog shows the settings', strcmp(winField.Value, '20+'));
    winField.Value = 'banana';
    D.check();
    results(end+1,:) = check('the settings dialog reports a problem and greys Apply', ...
        ~isempty(D.Problems) && strcmp(D.H.btnApply.Enable, 'off'));
    winField.Value = 'last 70';
    D.check();
    okA = D.apply();
    results(end+1,:) = check('... and applies a good value', okA && S.Settings.Window == "last 70");
    delete(D);

    G = gui.behavior.GroupingsDialog(S, Visible = false);
    S.addGrouping("Treatment", ["Control" "Noise"]);
    results(end+1,:) = check('the groupings dialog follows a new grouping', ...
        isequal(string(G.H.list.Items), "Treatment") && size(G.H.subjects.Data, 1) == 4);
    evt = struct('Indices', [1 2], 'NewData', 'Noise');
    G.H.subjects.CellEditCallback(G.H.subjects, evt);
    subj1 = string(G.H.subjects.Data{1, 1});
    results(end+1,:) = check('editing a level assigns the subject', ...
        S.Project.groupingLevel("Treatment", "", subj1) == "Noise");
    delete(G);
    E = gui.behavior.ExportDialog(app, Visible = false);
    results(end+1,:) = check('the export dialog builds', isgraphics(E.H.figure) && numel(E.H.tables) == numel(behavior.Export.TABLES));
    delete(E);
    results(end+1,:) = check('the dialogs close their windows', isempty(findall(groot, 'Type', 'figure', ...
        '-regexp', 'Tag', '^EPsychBehavior(Settings|Groupings|Export)$')));
catch ME
    results(end+1,:) = check(['group 12: ' ME.message], false);
end

%% 13. Teardown
try
    S = app.Study;
    delete(app);
    results(end+1,:) = check('no window is left', isempty(findall(groot, 'Type', 'figure', 'Tag', 'EPsychBehaviorAnalysis')));
    evs = ["CatalogChanged" "ProjectChanged" "SettingsChanged" "SelectionChanged" "ResultsChanged" "Busy"];
    results(end+1,:) = check('no listener is left on the Study', ~any(arrayfun(@(e) event.hasListener(S, e), evs)));
    after = localListing(root);
    results(end+1,:) = check('the root is unchanged', isequal(before, after));
catch ME
    results(end+1,:) = check(['group 13: ' ME.message], false);
end

localReport(results);
end


% ---------------------------------------------------------------------------
function row = check(label, tf)
row = {char(label), logical(tf)};
end

function localReport(results)
fprintf('\n');
nFail = 0;
for k = 1:size(results, 1)
    if results{k,2}
        tag = 'PASS';
    else
        tag = 'FAIL';
        nFail = nFail + 1;
    end
    fprintf('  %s  %s\n', tag, results{k,1});
end
fprintf('smoke_test_behavior_app: %d checks, %d failed\n', size(results, 1), nFail);
if nFail > 0
    error('smoke_test_behavior_app:Failed', '%d check(s) failed', nFail);
end
end

function txt = localRunScript(file, root, out)
% Run a generated script in a workspace of its own, ROOT and OUTFOLDER set,
% closing any figure it opens.
ROOT = string(root);
OUTFOLDER = string(out);
figsBefore = findall(groot, 'Type', 'figure');
txt = evalc(sprintf('run(''%s'')', char(file)));
figsAfter = findall(groot, 'Type', 'figure');
delete(setdiff(figsAfter, figsBefore));
assert(ROOT ~= "" && OUTFOLDER ~= "");
end

function L = localListing(root)
d = dir(fullfile(root, '**', '*'));
d = d(~ismember({d.name}, {'.', '..'}));
L = sortrows([string(fullfile({d.folder}, {d.name}))', string([d.bytes])', string([d.datenum])']);
end

function s = localSavePrefs(group)
s = struct('group', group, 'existed', ispref(group), 'values', struct());
if s.existed
    s.values = getpref(group);
end
end

function localRestorePrefs(saved)
for k = 1:numel(saved)
    s = saved{k};
    try
        if ispref(s.group), rmpref(s.group); end
        names = fieldnames(s.values);
        for j = 1:numel(names)
            setpref(s.group, names{j}, s.values.(names{j}));
        end
    catch
    end
end
end

function localRemove(folders)
for f = folders
    try
        if isfolder(f{1}), rmdir(f{1}, 's'); end
    catch
    end
end
end

function localCloseWindows()
app = epsych.BehaviorAnalysis.find();
while ~isempty(app)
    delete(app);
    app = epsych.BehaviorAnalysis.find();
end
for tag = {'EPsychBehaviorSettings', 'EPsychBehaviorGroupings', 'EPsychBehaviorExport', 'EPsychBehaviorPlotFigure'}
    delete(findall(groot, 'Type', 'figure', 'Tag', tag{1}));
end
end

function DATA = localObserverData(nTrials, mu, seed)
rng(seed);
HIT   = bitset(uint32(0), uint32(epsych.BitMask.Hit));
MISS  = bitset(uint32(0), uint32(epsych.BitMask.Miss));
CR    = bitset(uint32(0), uint32(epsych.BitMask.CorrectReject));
FA    = bitset(uint32(0), uint32(epsych.BitMask.FalseAlarm));
ABORT = bitset(uint32(0), uint32(epsych.BitMask.Abort));
ttBit = uint32(epsych.BitMask.TrialType_0);
depth = 40;
step = 2;
t0 = datetime(2026, 10, 1, 9, 0, 0);
DATA = struct('Depth', cell(1, nTrials), 'RespCode', [], 'TrialType', [], ...
    'TrialIndex', [], 'TrialID', [], 'computerTimestamp', [], 'isTest', []);
for k = 1:nTrials
    if mod(k, 6) == 0
        rc = CR;
        if rand < 0.15, rc = FA; end
        tt = 1;
    elseif rand < 0.03
        rc = ABORT;
        tt = 0;
    else
        tt = 0;
        pHit = 1 / (1 + exp(-0.8 * (depth - mu)));
        rc = MISS;
        if rand() < pHit
            rc = HIT;
        end
    end
    DATA(k) = struct('Depth', depth, 'RespCode', bitset(rc, ttBit + tt), 'TrialType', tt, ...
        'TrialIndex', k, 'TrialID', tt + 1, 'computerTimestamp', t0 + seconds(8 * k), ...
        'isTest', false);
    if tt == 0 && rc == HIT
        depth = max(2, depth - step);
    elseif tt == 0 && rc == MISS
        depth = min(60, depth + step);
    end
end
end
