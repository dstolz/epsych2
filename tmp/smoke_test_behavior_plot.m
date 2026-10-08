function smoke_test_behavior_plot()
% smoke_test_behavior_plot
% Standing proof of behavior.Plot, the offline analysis figures: every
% figure is drawn into a hidden uifigure's uiaxes AND a hidden classic
% figure's axes, and checked for the tagged graphics it promises, its axis
% labels, colours that stay with a facet level from one figure to the next,
% "No data" instead of an error for an empty or all-NaN input, and that it
% never makes a figure of its own.
%
% Fixture: as tmp/smoke_test_behavior_study.m -- two subjects, three "Pre"
% sessions (threshold 20) and three "Post" (threshold 26) each, saved as
% Data-only files. Data-only files carry no snapshot, so the results are
% given Unit "dB" by hand: that is what a session with a snapshot reports.
%
%   run('tmp/smoke_test_behavior_plot.m')

repoRoot = fileparts(fileparts(mfilename('fullpath')));
if exist('behavior.Plot', 'class') ~= 8
    run(fullfile(repoRoot, 'epsych_startup.m'));
end

results = cell(0, 2);

pid = feature('getpid');
root = fullfile(tempdir, sprintf('epsych_behavior_plot_smoke_%d', pid));
cache = fullfile(tempdir, sprintf('epsych_behavior_plot_cache_%d', pid));
if isfolder(root), rmdir(root, 's'); end
mkdir(root);
figsBefore = findall(groot, 'Type', 'figure');
uf = uifigure('Visible', 'off', 'Position', [100 100 900 600]);
gl = uigridlayout(uf, [1 1]);
uax = uiaxes(gl);
uax.Tag = 'MyAxes';
cf = figure('Visible', 'off', 'Position', [100 100 900 600]);
cax = axes(cf);
cleanup = onCleanup(@() localCleanup(root, cache, [uf cf]));

%% Fixture
subjects = ["S1" "S2"];
day0 = datetime(2026, 10, 1, 9, 0, 0);
k = 0;
for s = subjects
    folder = fullfile(root, 'ProjX', char(s));
    mkdir(folder);
    for i = 1:6
        k = k + 1;
        if i <= 3
            tag = "Pre";  mu = 20;
        else
            tag = "Post"; mu = 26;
        end
        Data = localObserverData(80, mu, 100 + k);
        stamp = string(day0 + days(i - 1), 'yyMMdd''T''HHmmss');
        save(fullfile(folder, sprintf('%s_%s_%s.mat', s, stamp, tag)), 'Data');
    end
end

cat = behavior.Catalog(root, CacheFolder = cache);
cat.scan();
settings = behavior.Settings();
R = cell(height(cat.Sessions), 1);
for i = 1:height(cat.Sessions)
    sess = behavior.Session.load(cat.Sessions(i, :), Root = root);
    R{i} = sess.analyze(settings);
    R{i}.Unit = "dB";
end
Rs = [R{:}];
T = behavior.Aggregate.thresholds(R, cat.Sessions);
fTag = behavior.Facet("tag", Index = 1);
fSubj = behavior.Facet("subject");
E = behavior.Aggregate.thresholds({});
Tnan = T;
Tnan.Threshold(:) = NaN;
Tnan.FitThreshold(:) = NaN;
Tnan.DPrime(:) = NaN;

%% 1. palette and colorsFor
try
    P = behavior.Plot.palette(8);
    outcome = localHex(epsych.BitMask.getDefaultColors([epsych.BitMask.Undefined epsych.BitMask.Hit ...
        epsych.BitMask.Miss epsych.BitMask.CorrectReject epsych.BitMask.FalseAlarm epsych.BitMask.Abort]));
    d = min(pdist2(P, outcome), [], 'all');
    results(end+1,:) = check('palette(8): 8 distinct RGB rows in 0..1', ...
        isequal(size(P), [8 3]) && size(unique(P, 'rows'), 1) == 8 && all(P(:) >= 0 & P(:) <= 1));
    results(end+1,:) = check(sprintf('no palette hue is an outcome colour (nearest %.2f)', d), d > 0.25);
    P30 = behavior.Plot.palette(30);
    results(end+1,:) = check('palette(30) keeps 24+ distinct rows and repeats nothing among the first 24', ...
        size(unique(round(P30(1:24, :), 6), 'rows'), 1) == 24 && isequal(P30(1:8, :), P));
    results(end+1,:) = check('palette(0) is 0-by-3', isequal(size(behavior.Plot.palette(0)), [0 3]));
    [c, lev, idx] = behavior.Plot.colorsFor(fSubj, T);
    results(end+1,:) = check('colorsFor: a colour per level in the facet''s order', ...
        isequal(lev, ["S1"; "S2"]) && isequal(c, P(1:2, :)) && isequal(idx, double(T.Subject == "S2") + 1));
catch ME
    results(end+1,:) = check(['group 1: ' ME.message], false);
end

results = [results; localPerAxes(uax, "uiaxes", T, Tnan, E, R, Rs, cat, fTag)];
results = [results; localPerAxes(cax, "axes", T, Tnan, E, R, Rs, cat, fTag)];

%% 9. Contract
try
    results(end+1,:) = check('a non-axes is refused', ...
        throwsWith(@() behavior.Plot.thresholdTimeline(uf, T), 'behavior:Plot:InvalidAxes'));
    figsAfter = findall(groot, 'Type', 'figure');
    results(end+1,:) = check('no figure was created besides the two the test made', ...
        numel(figsAfter) == numel(figsBefore) + 2);
    behavior.Plot.groupComparison(uax, T, "Threshold", GroupBy = fTag);
    untagged = findall(uax.Children, 'flat', 'Tag', '');
    results(end+1,:) = check('every object drawn carries a BehaviorPlot tag', isempty(untagged) ...
        && all(startsWith(string(get(uax.Children, 'Tag')), "BehaviorPlot:")));
catch ME
    results(end+1,:) = check(['group 9: ' ME.message], false);
end

%% Summary
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
fprintf('smoke_test_behavior_plot: %d checks, %d failed\n', size(results, 1), nFail);
clear cleanup
if nFail > 0
    error('smoke_test_behavior_plot:Failed', '%d check(s) failed', nFail);
end
end


function results = localPerAxes(ax, nm, T, Tnan, E, R, Rs, cat, fTag)
% Groups 2-8: every figure drawn into one axes (a uiaxes or a classic one).
results = cell(0, 2);
colTimeline = [];

%% 2. thresholdTimeline
try
    H = behavior.Plot.thresholdTimeline(ax, T);
    pts = localTagged(ax, "Point");
    results(end+1,:) = check(nm + ": timeline draws one marker per session, a line per subject", ...
        localCount(pts) == 12 && numel(localTagged(ax, "SubjectLine")) == 2 && numel(pts) == 2);
    results(end+1,:) = check(nm + ": timeline handles are the tagged ones", ...
        isempty(setxor(H.Point(:), pts(:))) && isequal(H.Axes, ax));
    results(end+1,:) = check(nm + ": fitted thresholds as hollow markers, one per finite fit", ...
        localCount(localTagged(ax, "Fit")) == sum(isfinite(T.FitThreshold)) ...
        && all(strcmp({localTagged(ax, "Fit").MarkerFaceColor}, 'none')));
    results(end+1,:) = check(nm + ": ylabel names the value and its unit; xlabel the time axis", ...
        contains(ax.YLabel.String, "Reversal threshold") && contains(ax.YLabel.String, "dB") ...
        && contains(ax.XLabel.String, "date"));
    results(end+1,:) = check(nm + ": the legend names the levels with their n", ...
        isgraphics(H.Legend) && any(contains(H.Legend.String, "S1 (n=6)")) && H.Legend.Title.String == "Subject");
    results(end+1,:) = check(nm + ": the axes keeps its own Tag through the clear", ...
        nm == "axes" || strcmp(ax.Tag, 'MyAxes'));
    colTimeline = localColorOf(pts, "S1");

    Tq = T;
    Tq.NumQC(:) = 0;
    Tq.NumQC([2 5]) = 1;
    Tq.Threshold(3) = NaN;
    behavior.Plot.thresholdTimeline(ax, Tq, XAxis = "session", ShowFit = false);
    results(end+1,:) = check(nm + ": QC sessions ringed; a NaN skipped, not drawn at zero", ...
        localCount(localTagged(ax, "QC")) == 2 && localCount(localTagged(ax, "Point")) == 11 ...
        && isempty(localTagged(ax, "Fit")) && ~any(localYData(localTagged(ax, "Point")) == 0));
    results(end+1,:) = check(nm + ": XAxis session counts sessions", ...
        contains(ax.XLabel.String, "Session number") && max(localXData(localTagged(ax, "Point"))) == 6);
    behavior.Plot.thresholdTimeline(ax, T, XAxis = "days", ShowQC = false);
    results(end+1,:) = check(nm + ": XAxis days starts at 0", ...
        min(localXData(localTagged(ax, "Point"))) == 0 && contains(ax.XLabel.String, "Days"));
    H = behavior.Plot.thresholdTimeline(ax, E);
    results(end+1,:) = check(nm + ": an empty table draws No data", localIsNoData(ax, H));
    H = behavior.Plot.thresholdTimeline(ax, table());
    results(end+1,:) = check(nm + ": a table with no columns draws No data", localIsNoData(ax, H));
    H = behavior.Plot.thresholdTimeline(ax, Tnan);
    results(end+1,:) = check(nm + ": an all-NaN column draws No data", localIsNoData(ax, H));
catch ME
    results(end+1,:) = check(nm + ": group 2: " + ME.message, false);
end

%% 3. metricTimeline
try
    behavior.Plot.metricTimeline(ax, T, "DPrime", ColorBy = fTag, XAxis = "session");
    pts = localTagged(ax, "Point");
    results(end+1,:) = check(nm + ": metric timeline colours by tag and labels d'", ...
        numel(pts) == 2 && localCount(pts) == sum(isfinite(T.DPrime)) && contains(ax.YLabel.String, "d'") ...
        && isempty(localTagged(ax, "Fit")) && isempty(localTagged(ax, "QC")));
    behavior.Plot.metricTimeline(ax, T, "AbortRate");
    results(end+1,:) = check(nm + ": a rate is labelled as a proportion", contains(ax.YLabel.String, "proportion"));
    H = behavior.Plot.metricTimeline(ax, Tnan, "DPrime");
    results(end+1,:) = check(nm + ": an all-NaN metric draws No data", localIsNoData(ax, H));
    results(end+1,:) = check(nm + ": an unknown column is refused", ...
        throwsWith(@() behavior.Plot.metricTimeline(ax, T, "Banana"), 'behavior:Plot:UnknownColumn'));
catch ME
    results(end+1,:) = check(nm + ": group 3: " + ME.message, false);
end

%% 4. groupComparison
try
    H = behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag);
    results(end+1,:) = check(nm + ": box: one box per level, 12 points, a median per subject x level", ...
        numel(localTagged(ax, "Box")) == 2 && localCount(localTagged(ax, "Point")) == 12 ...
        && numel(localTagged(ax, "SubjectMedian")) == 4 && numel(H.SubjectMedian) == 4);
    [levels, ~] = fTag.order(T);
    results(end+1,:) = check(nm + ": levels in facet order, n in the tick labels", ...
        isequal(numel(ax.XTick), 2) && startsWith(string(ax.XTickLabel{1}), levels(1)) ...
        && all(contains(string(ax.XTickLabel), "n=6")) && ax.XLabel.String == "Tag 1");
    results(end+1,:) = check(nm + ": ylabel names the value and its unit", ...
        contains(ax.YLabel.String, "Reversal threshold (dB)"));
    colCompare = localColorOf(localTagged(ax, "Point"), "S1");
    results(end+1,:) = check(nm + ": S1 keeps its colour from the timeline to the comparison", ...
        isequal(colTimeline, colCompare) && isequal(colCompare, behavior.Plot.palette(1)));
    boxTags = localTagSet(ax);

    behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag, Kind = "bar");
    barTags = localTagSet(ax);
    eb = localTagged(ax, "ErrorBar");
    results(end+1,:) = check(nm + ": bar: a bar per level with a mean +/- SEM error bar", ...
        numel(localTagged(ax, "Bar")) == 2 && isscalar(eb) && numel(eb.XData) == 2 && isempty(localTagged(ax, "Box")));
    H = behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag, Kind = "bar", ShowCI = true);
    ci = localTagged(ax, "CI");
    results(end+1,:) = check(nm + ": bar with ShowCI draws the bootstrap CI from Stats.describe", ...
        isscalar(ci) && isempty(localTagged(ax, "ErrorBar")) && istable(H.Stats) ...
        && all(abs(ci.YData(:) - H.Stats.Mean(:)) < 1e-12) && all(isfinite(H.Stats.CILo)));

    behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag, Kind = "strip", ShowSubjectMedians = false);
    stripTags = localTagSet(ax);
    results(end+1,:) = check(nm + ": strip: points and a mean line per level, nothing else", ...
        numel(localTagged(ax, "Mean")) == 2 && localCount(localTagged(ax, "Point")) == 12 ...
        && isempty(localTagged(ax, "Box")) && isempty(localTagged(ax, "Bar")) && isempty(localTagged(ax, "SubjectMedian")));
    results(end+1,:) = check(nm + ": the three kinds differ in what they draw", ...
        ~isequal(boxTags, barTags) && ~isequal(barTags, stripTags) && ~isequal(boxTags, stripTags));

    behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag, ColorBy = fTag, ShowPoints = false);
    b = localTagged(ax, "Box");
    results(end+1,:) = check(nm + ": coloured by its own facet, the boxes take the level colours; no points", ...
        isempty(localTagged(ax, "Point")) && numel(b) == 2 ...
        && ismember(behavior.Plot.palette(1), vertcat(b.BoxFaceColor), 'rows'));
    behavior.Plot.groupComparison(ax, T, "Threshold");
    results(end+1,:) = check(nm + ": no facet: one box, a median per subject", ...
        isscalar(localTagged(ax, "Box")) && numel(localTagged(ax, "SubjectMedian")) == 2);
    H = behavior.Plot.groupComparison(ax, E, "Threshold");
    results(end+1,:) = check(nm + ": comparison of an empty table draws No data", localIsNoData(ax, H));
    H = behavior.Plot.groupComparison(ax, Tnan, "Threshold", GroupBy = fTag, Kind = "bar");
    results(end+1,:) = check(nm + ": comparison of an all-NaN column draws No data", localIsNoData(ax, H));
catch ME
    results(end+1,:) = check(nm + ": group 4: " + ME.message, false);
end

%% 5. subjectLines
try
    H = behavior.Plot.subjectLines(ax, T, "Threshold");
    sl = localTagged(ax, "SubjectLine");
    mn = localTagged(ax, "Mean");
    results(end+1,:) = check(nm + ": a line per subject through its two level medians", ...
        numel(sl) == 2 && all(arrayfun(@(h) numel(h.XData), sl) == 2) && numel(H.SubjectLine) == 2);
    S = behavior.Aggregate.bySubject(T, "Threshold", GroupBy = fTag);
    s1 = H.SubjectLine(arrayfun(@(h) h.UserData.Subject == "S1", H.SubjectLine));
    [levels, ~] = fTag.order(T);
    expect = arrayfun(@(L) S.Median(S.Subject == "S1" & S.Level == L), levels);
    results(end+1,:) = check(nm + ": the line goes through the subject''s medians in level order", ...
        isequal(s1.XData(:), [1; 2]) && max(abs(s1.YData(:) - expect)) < 1e-12);
    results(end+1,:) = check(nm + ": the group mean of subject medians as a heavier line", ...
        isscalar(mn) && numel(mn.YData) == 2 && mn.LineWidth > s1.LineWidth ...
        && abs(mn.YData(1) - mean(S.Median(S.Level == levels(1)))) < 1e-12);
    results(end+1,:) = check(nm + ": ticks name the levels with n subjects; S1 in its subject colour", ...
        all(contains(string(ax.XTickLabel), "n=2")) && isequal(s1.Color, behavior.Plot.palette(1)));
    H = behavior.Plot.subjectLines(ax, Tnan, "Threshold");
    results(end+1,:) = check(nm + ": subject lines of an all-NaN column draw No data", localIsNoData(ax, H));
    H = behavior.Plot.subjectLines(ax, E, "Threshold");
    results(end+1,:) = check(nm + ": subject lines of an empty table draw No data", localIsNoData(ax, H));
catch ME
    results(end+1,:) = check(nm + ": group 5: " + ME.message, false);
end

%% 6. staircaseOverlay
try
    H = behavior.Plot.staircaseOverlay(ax, Rs, cat.Sessions);
    tr = localTagged(ax, "Track");
    results(end+1,:) = check(nm + ": overlay: one track per result", numel(tr) == 12 && numel(H.Track) == 12);
    okLen = arrayfun(@(r) numel(r.Track.Value), Rs);
    lens = arrayfun(@(h) numel(h.XData), H.Track);
    results(end+1,:) = check(nm + ": each track has its result''s stimulus trials", isequal(lens(:), okLen(:)));
    results(end+1,:) = check(nm + ": thresholds as end markers, none for reversals unless asked", ...
        numel(localTagged(ax, "Threshold")) == sum(isfinite([Rs.Threshold])) && isempty(localTagged(ax, "Reversal")) ...
        && all(strcmp({localTagged(ax, "Threshold").LineStyle}, 'none')) ...
        && all(arrayfun(@(h) isscalar(h.XData), localTagged(ax, "Threshold"))));
    results(end+1,:) = check(nm + ": overlay ylabel is the parameter and unit; a legend entry per level and the threshold key", ...
        contains(ax.YLabel.String, "Depth (dB)") && numel(H.Legend.String) == 3 ...
        && any(contains(H.Legend.String, "S1 (n=6)")) && any(startsWith(H.Legend.String, "Session threshold")));
    results(end+1,:) = check(nm + ": tracks are steps by default, plain lines with Steps=false", ...
        all(strcmp(get(H.Track, 'Type'), 'stair')) && H.ColorMap == "categorical" && isempty(H.ColorBar));
    s1 = H.Track(arrayfun(@(h) contains(h.UserData.Key, "/S1/"), H.Track));
    results(end+1,:) = check(nm + ": S1''s tracks share the colour S1 has everywhere else", ...
        numel(s1) == 6 && all(arrayfun(@(h) isequal(h.Color, behavior.Plot.palette(1)), s1)));

    H = behavior.Plot.staircaseOverlay(ax, R, cat.Sessions, Normalize = "fraction", ShowReversals = true, ...
        ColorBy = fTag);
    results(end+1,:) = check(nm + ": fraction: every track ends at x = 1 and starts above 0", ...
        all(arrayfun(@(h) h.XData(end) == 1 && h.XData(1) > 0, H.Track)));
    results(end+1,:) = check(nm + ": reversals marked when asked, one marker set per track", ...
        numel(localTagged(ax, "Reversal")) == sum(arrayfun(@(r) any(r.Track.Reversal), Rs)));
    results(end+1,:) = check(nm + ": coloured by tag: two colours, legend says the levels", ...
        size(unique(vertcat(H.Track.Color), 'rows'), 1) == 2 ...
        && isempty(setxor(["Pre (n=6)" "Post (n=6)" "Session threshold (n=12)" "Reversal"], string(H.Legend.String))));
    H = behavior.Plot.staircaseOverlay(ax, Rs, [], Normalize = "trial", ShowThresholds = false, Steps = false);
    results(end+1,:) = check(nm + ": no sessions table: still a track each, renumbered from 1", ...
        numel(H.Track) == 12 && all(arrayfun(@(h) h.XData(1) == 1, H.Track)) && isempty(H.Threshold) ...
        && all(strcmp(get(H.Track, 'Type'), 'line')));

    % Colour mapping across an ordered facet.
    fSess = behavior.Facet("session");
    H = behavior.Plot.staircaseOverlay(ax, Rs, cat.Sessions, ColorBy = fSess);
    c6 = behavior.Plot.sequential("parula", 6);
    ord = arrayfun(@(h) h.UserData.Level, H.Track);
    results(end+1,:) = check(nm + ": auto + session: a parula gradient, level k = sample k, drawn in level order", ...
        H.ColorMap == "parula" && all(arrayfun(@(h) isequal(h.Color, c6(h.UserData.Level, :)), H.Track)) ...
        && issorted(ord) && size(unique(vertcat(H.Track.Color), 'rows'), 1) == 6);
    results(end+1,:) = check(nm + ": six gradient levels fit the legend, so no colour bar", ...
        isempty(H.ColorBar) && numel(H.Legend.String) == 7);
    S12 = cat.Sessions;
    S12.Group_Run = compose("R%02d", (1:height(S12))');
    H = behavior.Plot.staircaseOverlay(ax, Rs, S12, ColorBy = behavior.Facet("manual", Name = "Run"), ...
        ColorMap = "turbo");
    results(end+1,:) = check(nm + ": a gradient over 12 levels is keyed by a colour bar, not 12 legend rows", ...
        H.ColorMap == "turbo" && isscalar(H.ColorBar) && isgraphics(H.ColorBar) ...
        && numel(H.ColorBar.Ticks) == 12 && string(H.ColorBar.TickLabels(1)) == "R01" ...
        && isequal(H.Legend.String, {'Session threshold (n=12)'}));
    S12.Group_Day = compose("2026-09-%02d", (1:height(S12))');
    S12.Group_Long = compose("Treatment phase %02d", (1:height(S12))');
    H = behavior.Plot.staircaseOverlay(ax, Rs, S12, ColorBy = behavior.Facet("manual", Name = "Day"), ...
        ColorMap = "parula");
    dayTick = string(H.ColorBar.TickLabels(1));
    dayTitle = string(H.ColorBar.Label.String);
    H = behavior.Plot.staircaseOverlay(ax, Rs, S12, ColorBy = behavior.Facet("manual", Name = "Long"), ...
        ColorMap = "parula");
    results(end+1,:) = check(nm + ": colour-bar ticks stay short: a shared prefix moves to the title, long ones are cut", ...
        dayTick == "01" && contains(dayTitle, "2026-09-") ...
        && all(strlength(string(H.ColorBar.TickLabels)) <= behavior.Plot.MAX_TICK_CHARS));
    fSubj = behavior.Facet("subject");
    H = behavior.Plot.staircaseOverlay(ax, Rs, cat.Sessions, ColorBy = fSubj, ColorMap = "copper");
    results(end+1,:) = check(nm + ": a gradient may be asked for on any facet; auto keeps subject categorical", ...
        H.ColorMap == "copper" && behavior.Plot.resolveColorMap("auto", fSubj) == "categorical");
    behavior.Plot.staircaseOverlay(ax, Rs, S12, ColorBy = behavior.Facet("manual", Name = "Run"), ColorMap = "turbo");
    hadBar = ~isempty(findall(ancestor(ax, 'figure'), 'Tag', 'BehaviorPlot:ColorBar'));
    H = behavior.Plot.staircaseOverlay(ax, Rs, cat.Sessions, ColorBy = fSubj);
    results(end+1,:) = check(nm + ": the next figure clears a colour bar the last one left", ...
        hadBar && isempty(H.ColorBar) && isempty(findall(ancestor(ax, 'figure'), 'Tag', 'BehaviorPlot:ColorBar')));
    bad = false;
    try
        behavior.Plot.staircaseOverlay(ax, Rs, cat.Sessions, ColorMap = "rainbow");
    catch
        bad = true;
    end
    results(end+1,:) = check(nm + ": an unknown colour map is refused", bad);
    H = behavior.Plot.staircaseOverlay(ax, {}, cat.Sessions);
    results(end+1,:) = check(nm + ": overlay of no results draws No data", localIsNoData(ax, H));
    H = behavior.Plot.staircaseOverlay(ax, struct([]), []);
    results(end+1,:) = check(nm + ": overlay of an empty struct draws No data", localIsNoData(ax, H));
catch ME
    results(end+1,:) = check(nm + ": group 6: " + ME.message, false);
end

%% 7. psychometric
try
    good = find(arrayfun(@(r) r.Fit.Converged && r.Fit.Identifiable, Rs), 1);
    results(end+1,:) = check(nm + ": the fixture has a converged fit", ~isempty(good));
    F = Rs(good).Fit;
    H = behavior.Plot.psychometric(ax, F, Unit = "dB");
    cu = localTagged(ax, "Curve");
    results(end+1,:) = check(nm + ": psychometric: proportions, a curve of >10 points, a threshold line", ...
        isscalar(localTagged(ax, "Proportion")) && isscalar(cu) && numel(cu.XData) > 10 ...
        && isscalar(localTagged(ax, "Threshold")) && isequal(H.Threshold.XData, [F.Threshold F.Threshold]));
    results(end+1,:) = check(nm + ": marker area follows NumTotal", ...
        numel(unique(H.Proportion.SizeData)) > 1 || isscalar(unique(F.NumTotal)));
    results(end+1,:) = check(nm + ": psychometric labels: level with unit, proportion", ...
        contains(ax.XLabel.String, "(dB)") && contains(ax.YLabel.String, "Proportion"));
    Fc = F;
    Fc.CI.ThresholdLo = F.Threshold - 1;
    Fc.CI.ThresholdHi = F.Threshold + 1;
    Fc.CI.Level = 0.95;
    behavior.Plot.psychometric(ax, Fc);
    ci = localTagged(ax, "CI");
    results(end+1,:) = check(nm + ": a finite CI is a shaded band", isscalar(ci) && isequal(sort(unique(ci.XData))', Fc.Threshold + [-1 1]));
    behavior.Plot.psychometric(ax, Fc, ShowCI = false, ShowCounts = false);
    results(end+1,:) = check(nm + ": ShowCI false: no band", isempty(localTagged(ax, "CI")));

    Fn = F;
    Fn.Converged = false;
    Fn.Message = "Complete separation: the slope is unbounded.";
    H = behavior.Plot.psychometric(ax, Fn);
    results(end+1,:) = check(nm + ": a non-converged fit draws its proportions and its message, no curve", ...
        isscalar(localTagged(ax, "Proportion")) && isempty(localTagged(ax, "Curve")) ...
        && isscalar(H.Message) && contains(H.Message.String, "Complete separation"));
    Fe = behavior.fit.Builtin.empty();
    Fe.Message = "Fewer than two distinct levels.";
    H = behavior.Plot.psychometric(ax, Fe);
    results(end+1,:) = check(nm + ": an empty fit with a message draws No data and the message", ...
        localIsNoData(ax, H) && any(contains(string(H.NoData.String), "Fewer than two distinct levels")));
    H = behavior.Plot.psychometric(ax, []);
    results(end+1,:) = check(nm + ": psychometric of [] draws No data", localIsNoData(ax, H));
catch ME
    results(end+1,:) = check(nm + ": group 7: " + ME.message, false);
end

%% 8. reversalHistogram
try
    H = behavior.Plot.reversalHistogram(ax, Rs(1));
    results(end+1,:) = check(nm + ": histogram of the reversal values with mean and median lines", ...
        isscalar(localTagged(ax, "Histogram")) && sum(H.Histogram.Values) == numel(Rs(1).ReversalValues) ...
        && abs(H.Mean.Value - mean(Rs(1).ReversalValues)) < 1e-12 ...
        && abs(H.Median.Value - median(Rs(1).ReversalValues)) < 1e-12);
    results(end+1,:) = check(nm + ": histogram labels: parameter at reversal with unit, count", ...
        contains(ax.XLabel.String, "Depth at reversal (dB)") && ax.YLabel.String == "Count");
    H = behavior.Plot.reversalHistogram(ax, Rs, Unit = "dB SPL");
    results(end+1,:) = check(nm + ": several results are pooled; a stated unit wins", ...
        sum(H.Histogram.Values) == numel([Rs.ReversalValues]) && contains(ax.XLabel.String, "dB SPL"));
    R0 = Rs(1);
    R0.ReversalValues = zeros(1, 0);
    H = behavior.Plot.reversalHistogram(ax, R0);
    results(end+1,:) = check(nm + ": no reversals draws No data", localIsNoData(ax, H));
    H = behavior.Plot.reversalHistogram(ax, struct([]));
    results(end+1,:) = check(nm + ": histogram of no results draws No data", localIsNoData(ax, H));
catch ME
    results(end+1,:) = check(nm + ": group 8: " + ME.message, false);
end
end

function row = check(label, tf)
row = {char(label), logical(tf)};
end

function tf = throwsWith(fcn, id)
tf = false;
try
    fcn();
catch ME
    tf = strcmp(ME.identifier, id);
end
end

function h = localTagged(ax, role)
h = findall(ax, 'Tag', char("BehaviorPlot:" + role));
end

function n = localCount(h)
% Finite markers across line objects.
n = sum(arrayfun(@(x) sum(isfinite(double(x.YData))), h));
end

function y = localYData(h)
y = cell2mat(arrayfun(@(x) reshape(double(x.YData), 1, []), reshape(h, 1, []), 'UniformOutput', false));
end

function x = localXData(h)
x = cell2mat(arrayfun(@(v) reshape(double(v.XData), 1, []), reshape(h, 1, []), 'UniformOutput', false));
end

function c = localColorOf(h, level)
c = [];
for k = 1:numel(h)
    if startsWith(string(h(k).DisplayName), level + " ")
        c = h(k).MarkerFaceColor;
    end
end
end

function tags = localTagSet(ax)
tags = unique(string(get(findall(ax.Children, 'flat'), 'Tag')));
end

function tf = localIsNoData(ax, H)
t = localTagged(ax, "NoData");
tf = false;
if ~isscalar(t), return, end
s = string(t.String);
tf = isequal(t, H.NoData) && startsWith(s(1), "No data") ...
    && isscalar(ax.Children);
end

function rgb = localHex(hex)
hex = char(erase(reshape(string(hex), [], 1), "#"));
rgb = [hex2dec(hex(:, 1:2)) hex2dec(hex(:, 3:4)) hex2dec(hex(:, 5:6))] / 255;
end

function DATA = localObserverData(nTrials, mu, seed)
% A symmetric 1-up/1-down track on a positive-dB Depth, converging on mu, with
% a catch trial every sixth and the odd abort; shaped like RUNTIME.TRIALS.DATA.
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

function localCleanup(root, cache, figs)
for f = figs
    if isgraphics(f), delete(f); end
end
for d = {root, cache}
    try
        if isfolder(d{1}), rmdir(d{1}, 's'); end
    catch
    end
end
end
