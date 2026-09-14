% smoke_test_metrics_explorer.m
% Offline smoke tests for gui.MetricsExplorer -- no hardware, no session.
%
% The point of this window is that it shows the arithmetic the toolbox actually
% runs, so most of what follows is a cross-check rather than a UI test: every
% surface and readout is compared against psychophysics.Metrics called directly,
% and against psychophysics.Metrics.fromCounts, which is what a session reports.
% A number that differs between the two is the only failure mode that matters.
%
% Run headless, from the repository root:
%   matlab -batch "run('tmp/smoke_test_metrics_explorer.m')"
%
% See also: gui.MetricsExplorer, psychophysics.Metrics,
%   documentation/gui/gui_MetricsExplorer.md

% Bootstrap: `matlab -batch` starts with whatever path the user profile leaves
% behind, and this file lives in tmp/, which is only on the path once
% epsych_startup has run.
if exist('gui.MetricsExplorer', 'class') ~= 8
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'epsych_startup.m'));
end

fprintf('\n=== gui.MetricsExplorer Smoke Test ===\n\n');
results = {};

TOL = 1e-12;
E = [];

%% 1. The catalog is well formed
try
    C = gui.MetricsExplorer.catalog();

    results(end+1,:) = check('Catalog is a non-empty struct array', ...
        isstruct(C) && ~isempty(C));
    results(end+1,:) = check('Keys are unique', ...
        numel(unique({C.Key})) == numel(C));
    results(end+1,:) = check('Every Fcn is a function handle', ...
        all(cellfun(@(f) isa(f,'function_handle'), {C.Fcn})));
    results(end+1,:) = check('Every Field is a legal struct field name', ...
        all(cellfun(@isvarname, {C.Field})));

    % The explanation panel is the deliverable, not decoration: an entry with
    % an empty field would render as a blank line the operator has to guess at.
    described = true;
    for i = 1:numel(C)
        described = described && ~isempty(C(i).Label) && ~isempty(C(i).Symbol) ...
            && ~isempty(C(i).Formula) && ~isempty(C(i).Summary) ...
            && ~isempty(C(i).Reading) && ~isempty(C(i).NeutralMeaning) ...
            && ~isempty(C(i).LowWord) && ~isempty(C(i).HighWord) ...
            && ~isempty(C(i).Reference);
    end
    results(end+1,:) = check('Every metric carries its full explanation', described);

    results(end+1,:) = check('A bad key is refused by name', ...
        throwsWith(@() gui.MetricsExplorer.metric("nope"), ...
        'gui:MetricsExplorer:UnknownMetric'));
    results(end+1,:) = check('Keys resolve case-insensitively', ...
        strcmp(gui.MetricsExplorer.metric("DPRIME").Key, 'dprime'));
catch ME
    results(end+1,:) = check(['Catalog: ' ME.message], false);
end

%% 2. evaluate is psychophysics.Metrics, not a second implementation
try
    H = 0.8; F = 0.3;

    results(end+1,:) = check("d' matches Metrics.dprime", ...
        near(gui.MetricsExplorer.evaluate("dprime", H, F), ...
             psychophysics.Metrics.dprime(H, F), TOL));
    results(end+1,:) = check('c matches Metrics.criterion', ...
        near(gui.MetricsExplorer.evaluate("criterion", H, F), ...
             psychophysics.Metrics.criterion(H, F), TOL));
    results(end+1,:) = check("c' matches Metrics.criterionRelative", ...
        near(gui.MetricsExplorer.evaluate("criterionRelative", H, F), ...
             psychophysics.Metrics.criterionRelative(H, F), TOL));
    results(end+1,:) = check('ln(beta) matches Metrics.lnBeta', ...
        near(gui.MetricsExplorer.evaluate("lnBeta", H, F), ...
             psychophysics.Metrics.lnBeta(H, F), TOL));
    results(end+1,:) = check("A' matches Metrics.aprime", ...
        near(gui.MetricsExplorer.evaluate("aprime", H, F), ...
             psychophysics.Metrics.aprime(H, F), TOL));
    results(end+1,:) = check("B'' matches Metrics.bprimeprime", ...
        near(gui.MetricsExplorer.evaluate("bprimeprime", H, F), ...
             psychophysics.Metrics.bprimeprime(H, F), TOL));
    results(end+1,:) = check('pc matches Metrics.percentCorrect', ...
        near(gui.MetricsExplorer.evaluate("percentCorrect", H, F), ...
             psychophysics.Metrics.percentCorrect(H, F), TOL));

    % Against theory rather than against itself.
    results(end+1,:) = check("d' is z(H) - z(F)", ...
        near(gui.MetricsExplorer.evaluate("dprime", 0.8, 0.2, Correction="none"), ...
             norminv(0.8) - norminv(0.2), TOL));
    results(end+1,:) = check('c is -(z(H) + z(F))/2', ...
        near(gui.MetricsExplorer.evaluate("criterion", 0.8, 0.2, Correction="none"), ...
             -(norminv(0.8) + norminv(0.2))/2, TOL));
    results(end+1,:) = check("ln(beta) is c * d'", ...
        near(gui.MetricsExplorer.evaluate("lnBeta", 0.9, 0.25, Correction="none"), ...
             gui.MetricsExplorer.evaluate("criterion", 0.9, 0.25, Correction="none") * ...
             gui.MetricsExplorer.evaluate("dprime", 0.9, 0.25, Correction="none"), 1e-10));

    % Rates broadcast, so a grid goes in and a grid comes out.
    Hv = (0.1:0.1:0.9)';
    v = gui.MetricsExplorer.evaluate("dprime", Hv, 0.4);
    results(end+1,:) = check('Rates broadcast', ...
        isequal(size(v), size(Hv)) && near(v, psychophysics.Metrics.dprime(Hv, 0.4), TOL));
catch ME
    results(end+1,:) = check(['evaluate: ' ME.message], false);
end

%% 3. A number here is the number a session would report
try
    % 40 hits / 10 misses, 15 false alarms / 35 correct rejections:
    % H = 0.8, F = 0.3, nothing clamped.
    S = psychophysics.Metrics.fromCounts(40, 10, 15, 35);
    H = S.Rate.Hit; F = S.Rate.FalseAlarm;

    results(end+1,:) = check('The test counts give H = 0.8, F = 0.3', ...
        near(H, 0.8, TOL) && near(F, 0.3, TOL));

    pairs = { ...
        "dprime",            S.DPrime; ...
        "criterion",         S.Criterion; ...
        "criterionRelative", S.CriterionRelative; ...
        "lnBeta",            S.LnBeta; ...
        "aprime",            S.APrime; ...
        "bprimeprime",       S.BPrimePrime; ...
        "percentCorrect",    S.PercentCorrectBalanced};

    agrees = true;
    for i = 1:size(pairs,1)
        agrees = agrees && near(gui.MetricsExplorer.evaluate(pairs{i,1}, H, F), pairs{i,2}, TOL);
    end
    results(end+1,:) = check('Every metric agrees with Metrics.fromCounts', agrees);
catch ME
    results(end+1,:) = check(['fromCounts agreement: ' ME.message], false);
end

%% 4. The correction is applied where it applies, and nowhere else
try
    % Uncorrected, the corners are infinite -- which is the honest answer.
    results(end+1,:) = check('No correction leaves the corner infinite', ...
        isinf(gui.MetricsExplorer.evaluate("dprime", 1, 0, Correction="none")));

    % Clamped, the whole corner is one number, and that number is the bound's.
    results(end+1,:) = check('The clamp ceiling is 2*z(0.99)', ...
        near(gui.MetricsExplorer.evaluate("dprime", 1, 0), 2*norminv(0.99), TOL));
    results(end+1,:) = check('Wider bounds raise the ceiling', ...
        near(gui.MetricsExplorer.evaluate("dprime", 1, 0, Bounds=[0.001 0.999]), ...
             2*norminv(0.999), TOL));

    % Half-cell moves only the extremes; 1 -> 1 - 1/(2N).
    results(end+1,:) = check('Half-cell is 1/(2N) at the extremes', ...
        near(gui.MetricsExplorer.evaluate("dprime", 1, 0, ...
                Correction="halfcell", NSignal=50, NNoise=50), ...
             norminv(1 - 0.5/50) - norminv(0.5/50), TOL));
    results(end+1,:) = check('Half-cell leaves an interior rate alone', ...
        near(gui.MetricsExplorer.evaluate("dprime", 0.8, 0.3, ...
                Correction="halfcell", NSignal=50, NNoise=50), ...
             norminv(0.8) - norminv(0.3), TOL));

    % Log-linear moves EVERY rate, which is the thing worth seeing.
    results(end+1,:) = check('Log-linear moves an interior rate too', ...
        near(gui.MetricsExplorer.evaluate("dprime", 0.8, 0.3, ...
                Correction="loglinear", NSignal=50, NNoise=50), ...
             norminv((0.8*50+0.5)/51) - norminv((0.3*50+0.5)/51), TOL));

    % The metrics that are defined at 0 and 1 ignore all of it.
    freeOfCorrection = true;
    for key = ["aprime","bprimeprime","percentCorrect"]
        a = gui.MetricsExplorer.evaluate(key, 1, 0, Correction="none");
        b = gui.MetricsExplorer.evaluate(key, 1, 0, Correction="clamp");
        c = gui.MetricsExplorer.evaluate(key, 1, 0, Correction="loglinear", ...
            NSignal=20, NNoise=20);
        freeOfCorrection = freeOfCorrection && isequaln(a,b) && isequaln(a,c);
    end
    results(end+1,:) = check("A', B'' and pc take no correction, whatever is asked", ...
        freeOfCorrection);
    results(end+1,:) = check("A' is 1 at H = 1, F = 0", ...
        near(gui.MetricsExplorer.evaluate("aprime", 1, 0), 1, TOL));

    % NaN propagates rather than becoming a bound -- the bug the clamp in
    % psychophysics.Metrics was written to avoid.
    results(end+1,:) = check('NaN rates stay NaN', ...
        isnan(gui.MetricsExplorer.evaluate("dprime", NaN, 0.3)));
catch ME
    results(end+1,:) = check(['Corrections: ' ME.message], false);
end

%% 5. Neutral levels are where the catalog says they are
try
    C = gui.MetricsExplorer.catalog();
    neutralOK = true;
    for i = 1:numel(C)
        switch C(i).Key
            case {'dprime','aprime','percentCorrect'}
                v = gui.MetricsExplorer.evaluate(C(i).Key, 0.42, 0.42);   % H = F
            otherwise
                v = gui.MetricsExplorer.evaluate(C(i).Key, 0.73, 0.27);   % H = 1 - F
        end
        neutralOK = neutralOK && near(v, C(i).Neutral, 1e-10);
    end
    results(end+1,:) = check('Each metric takes its neutral value on its own neutral line', ...
        neutralOK);

    % ln(beta) = c * d' has two neutral branches, and the second one is the
    % reason it is not a bias measure on its own.
    results(end+1,:) = check("ln(beta) is also 0 at chance, where d' is 0", ...
        near(gui.MetricsExplorer.evaluate("lnBeta", 0.42, 0.42), 0, 1e-10));
catch ME
    results(end+1,:) = check(['Neutral levels: ' ME.message], false);
end

%% 6. formatValue names what it cannot round
try
    results(end+1,:) = check('NaN reads as n/a', ...
        strcmp(gui.MetricsExplorer.formatValue(NaN), 'n/a'));
    results(end+1,:) = check('Inf reads as Inf', ...
        strcmp(gui.MetricsExplorer.formatValue(Inf), 'Inf'));
    results(end+1,:) = check('-Inf reads as -Inf', ...
        strcmp(gui.MetricsExplorer.formatValue(-Inf), '-Inf'));
    results(end+1,:) = check('An ordinary value gets three decimals', ...
        strcmp(gui.MetricsExplorer.formatValue(-0.49012), '-0.490'));
catch ME
    results(end+1,:) = check(['formatValue: ' ME.message], false);
end

%% 7. The colormap is diverging and centred
try
    map = gui.MetricsExplorer.divergingMap(256);
    results(end+1,:) = check('Colormap is 256-by-3 inside [0 1]', ...
        isequal(size(map), [256 3]) && all(map(:) >= 0) && all(map(:) <= 1));
    results(end+1,:) = check('Low end is blue', ...
        map(1,3) > map(1,1));
    results(end+1,:) = check('High end is red', ...
        map(end,1) > map(end,3));
    results(end+1,:) = check('The middle is near white', ...
        all(map(128,:) > 0.85));
catch ME
    results(end+1,:) = check(['Colormap: ' ME.message], false);
end

%% 8. The window opens, and the picture is the arithmetic
try
    E = gui.MetricsExplorer(Visible = false);

    results(end+1,:) = check('Window opened', isvalid(E) && isgraphics(E.H.figure));
    results(end+1,:) = check('Figure carries the singleton tag', ...
        strcmp(E.H.figure.Tag, 'EPsychMetricsExplorer'));
    results(end+1,:) = check('It opens on d''', strcmp(E.Metric, "dprime"));

    [Z, hv, fv] = E.surface();
    results(end+1,:) = check('The surface is one value per grid point', ...
        isequal(size(Z), [numel(hv) numel(fv)]));
    results(end+1,:) = check('The grid spans 0 to 1 in both rates', ...
        hv(1) == 0 && hv(end) == 1 && fv(1) == 0 && fv(end) == 1);
    results(end+1,:) = check('0.5 lands exactly on the grid', ...
        any(hv == 0.5) && any(fv == 0.5));

    % Orientation: rows are hit rate, columns false alarm rate. Getting this
    % backwards would draw a transposed map that still looks plausible.
    i = 37; j = 152;
    results(end+1,:) = check('Rows are hit rate and columns false alarm rate', ...
        near(Z(i,j), gui.MetricsExplorer.evaluate("dprime", hv(i), fv(j)), TOL));
    results(end+1,:) = check('The image shows the surface', ...
        isequaln(E.H.image.CData, Z));

    % Every point, not just the two above.
    [Fg, Hg] = meshgrid(fv, hv);
    results(end+1,:) = check('The whole surface is Metrics.dprime', ...
        isequaln(Z, psychophysics.Metrics.dprime(Hg, Fg)));
catch ME
    results(end+1,:) = check(['Window: ' ME.message], false);
end

%% 9. The probe, the readout and values()
try
    E.setPoint(0.635, 0.738);
    results(end+1,:) = check('setPoint moves the probe', ...
        near(E.HitRate, 0.635, TOL) && near(E.FalseAlarmRate, 0.738, TOL));
    results(end+1,:) = check('The rate fields follow it', ...
        near(E.H.hitRate.Value, 0.635, TOL) && near(E.H.falseAlarm.Value, 0.738, TOL));
    results(end+1,:) = check('The crosshair follows it', ...
        near(E.H.vline.XData(1), 0.738, TOL) && near(E.H.hline.YData(1), 0.635, TOL));

    results(end+1,:) = check('A rate outside the plane is clamped, not refused', ...
        clampsTo(E, -0.5, 1.5, 0, 1));
    E.setPoint(0.635, 0.738);

    S = E.values();
    results(end+1,:) = check('values() reports the probe rates', ...
        near(S.HitRate, 0.635, TOL) && near(S.FalseAlarmRate, 0.738, TOL));
    results(end+1,:) = check('values() uses fromCounts field names', ...
        all(isfield(S, {'DPrime','Criterion','CriterionRelative','LnBeta', ...
                        'APrime','BPrimePrime','PercentCorrectBalanced'})));
    results(end+1,:) = check('values() agrees with Metrics', ...
        near(S.DPrime, psychophysics.Metrics.dprime(0.635, 0.738), TOL) && ...
        near(S.Criterion, psychophysics.Metrics.criterion(0.635, 0.738), TOL));
    results(end+1,:) = check('values() says what the z-transform saw', ...
        near(S.RateCorrected.Hit, 0.635, TOL) && near(S.RateCorrected.FalseAlarm, 0.738, TOL));

    % The worked example this window was built from: c = -0.490, d' = -0.291.
    % Agreement is to 3e-3 because those rates were themselves shown rounded
    % to three decimals, and z() is steep enough that the last digit matters.
    results(end+1,:) = check('The worked example reproduces to the precision its rates were shown at', ...
        near(S.Criterion, -0.490, 3e-3) && near(S.DPrime, -0.291, 3e-3));
catch ME
    results(end+1,:) = check(['Probe: ' ME.message], false);
end

%% 10. Switching metric switches the map, the range and the controls
try
    E.setMetric("criterion");
    Zc = E.surface();
    results(end+1,:) = check('The map follows the metric', ...
        strcmp(E.Metric, "criterion") && isequaln(Zc, gridOf(E, "criterion")));
    results(end+1,:) = check('The colour range resets to the metric default', ...
        near(E.H.range.Value, gui.MetricsExplorer.metric("criterion").Range, TOL));
    results(end+1,:) = check('The colour scale is centred on the neutral value', ...
        near(mean(E.H.axes.CLim), gui.MetricsExplorer.metric("criterion").Neutral, TOL));

    % A metric that takes no correction says so by greying the controls, not
    % by silently ignoring them.
    E.setMetric("aprime");
    results(end+1,:) = check('A correction-free metric greys the correction controls', ...
        strcmp(char(E.H.correction.Enable), 'off') && ...
        strcmp(char(E.H.correctionLabel.Enable), 'off'));
    results(end+1,:) = check('...and says why on the status line', ...
        contains(E.H.status.Text, 'does not apply'));

    E.setMetric("dprime");
    results(end+1,:) = check('A correcting metric re-enables them', ...
        strcmp(char(E.H.correction.Enable), 'on') && ...
        strcmp(char(E.H.boundsLo.Enable), 'on'));
    results(end+1,:) = check('The N fields stay dark under a clamp', ...
        strcmp(char(E.H.nSignal.Enable), 'off'));

    E.H.correction.Value = 'loglinear';
    E.H.correction.ValueChangedFcn(E.H.correction, []);
    results(end+1,:) = check('Choosing an N-dependent correction lights the N fields', ...
        strcmp(char(E.H.nSignal.Enable), 'on') && strcmp(char(E.H.boundsLo.Enable), 'off'));
    results(end+1,:) = check('...and the surface is recomputed through it', ...
        isequaln(E.surface(), gridOf(E, "dprime")));

    E.H.correction.Value = 'clamp';
    E.H.correction.ValueChangedFcn(E.H.correction, []);
catch ME
    results(end+1,:) = check(['Metric switching: ' ME.message], false);
end

%% 11. A clipped colour scale admits it
try
    E.setMetric("dprime");
    E.H.correction.Value = 'none';
    E.H.correction.ValueChangedFcn(E.H.correction, []);

    labels = E.H.colorbar.TickLabels;
    results(end+1,:) = check('Clipping is marked on both end ticks', ...
        startsWith(labels{1}, '<=') && startsWith(labels{end}, '>='));

    % With the clamp, the whole surface fits inside +/-4.653, so a range of 5
    % clips nothing and the ticks say nothing.
    E.H.correction.Value = 'clamp';
    E.H.correction.ValueChangedFcn(E.H.correction, []);
    E.H.range.Value = 5;
    E.H.range.ValueChangedFcn(E.H.range, []);
    labels = E.H.colorbar.TickLabels;
    results(end+1,:) = check('An unclipped scale is not marked', ...
        ~startsWith(labels{1}, '<=') && ~startsWith(labels{end}, '>='));
catch ME
    results(end+1,:) = check(['Colorbar: ' ME.message], false);
end

%% 12. Bad bounds are refused and put back
try
    E.H.boundsLo.Value = 0.99;
    E.H.boundsHi.Value = 0.5;
    E.H.boundsLo.ValueChangedFcn(E.H.boundsLo, []);
    results(end+1,:) = check('Crossed bounds are refused', ...
        isequal(E.Bounds, [0.01 0.99]) && near(E.H.boundsLo.Value, 0.01, TOL));
    results(end+1,:) = check('...with the reason on the status line', ...
        contains(E.H.status.Text, 'lower bound'));

    E.H.boundsLo.Value = 0.05;
    E.H.boundsHi.Value = 0.95;
    E.H.boundsLo.ValueChangedFcn(E.H.boundsLo, []);
    results(end+1,:) = check('Good bounds are taken', isequal(E.Bounds, [0.05 0.95]));
    results(end+1,:) = check('...and reach the surface', ...
        near(gui.MetricsExplorer.evaluate("dprime", 1, 0, Bounds=[0.05 0.95]), ...
             2*norminv(0.95), TOL));
catch ME
    results(end+1,:) = check(['Bounds: ' ME.message], false);
end

%% 13. Citations carry their DOIs, and the guide is one click away
try
    R = gui.MetricsExplorer.citations();
    results(end+1,:) = check('Citation keys are unique', ...
        numel(unique({R.Key})) == numel(R));
    hasDoi = ~cellfun(@isempty, {R.DOI});
    results(end+1,:) = check('Every DOI is a DOI, not a URL', ...
        all(cellfun(@(d) ~isempty(regexp(d, '^10\.\d{4,9}/\S+$', 'once')), {R(hasDoi).DOI})));
    results(end+1,:) = check('doiUrl is the https resolver form', ...
        strcmp(gui.MetricsExplorer.doiUrl('10.1037/h0031246'), 'https://doi.org/10.1037/h0031246'));
    results(end+1,:) = check('An unknown citation key is refused by name', ...
        throwsWith(@() gui.MetricsExplorer.citations("nope"), ...
                   'gui:MetricsExplorer:UnknownCitation'));

    C = gui.MetricsExplorer.catalog();
    results(end+1,:) = check('Every metric cites at least one work', ...
        all(arrayfun(@(c) ~isempty(c.Citations), C)));
    results(end+1,:) = check('Reference is the short form of Citations', ...
        all(arrayfun(@(c) strcmp(c.Reference, strjoin({c.Citations.Short}, '; ')), C)));

    % The panel shows a link for exactly the citations that have a DOI.
    E.setMetric("aprime");
    links = findall(E.H.references, 'Type', 'uihyperlink');
    results(end+1,:) = check('A'' links Grier (1971) by DOI', ...
        isscalar(links) && strcmp(links.URL, 'https://doi.org/10.1037/h0031246') ...
        && strcmp(links.Text, 'doi:10.1037/h0031246'));

    E.setMetric("dprime");
    links = findall(E.H.references, 'Type', 'uihyperlink');
    labels = findall(E.H.references, 'Type', 'uilabel');
    results(end+1,:) = check('d'' lists both works and links only the one with a DOI', ...
        isscalar(links) && strcmp(links.URL, 'https://doi.org/10.4324/9781410611147') ...
        && numel(labels) == 3);   % heading + two citations
    results(end+1,:) = check('Switching metric rebuilds the list rather than adding to it', ...
        numel(E.H.references.Children) == numel(E.H.references.RowHeight));

    results(end+1,:) = check('The guide link points at the wiki page', ...
        strcmp(E.H.guideLink.URL, gui.MetricsExplorer.WIKI_URL));
    results(end+1,:) = check('The Help menu offers the guide', ...
        isgraphics(E.H.menuGuide) && contains(E.H.menuGuide.Text, 'Wiki'));
catch ME
    results(end+1,:) = check(['Citations: ' ME.message], false);
end

%% 14. Teardown
try
    fig = E.H.figure;
    fig.CloseRequestFcn(fig, []);
    results(end+1,:) = check('Closing the window deletes the object', ~isvalid(E));
    results(end+1,:) = check('...and the figure with it', ~isgraphics(fig));
    results(end+1,:) = check('The window position was remembered', ...
        ispref('epsych2_gui_MetricsExplorer','FigurePosition'));

    % One window at a time.
    a = gui.MetricsExplorer(Visible = false);
    b = gui.MetricsExplorer(Visible = false);
    results(end+1,:) = check('Opening a second window closes the first', ~isvalid(a));
    results(end+1,:) = check('Only one figure carries the tag', ...
        numel(findall(groot,'Type','figure','Tag','EPsychMetricsExplorer')) == 1);
    delete(b);
catch ME
    results(end+1,:) = check(['Teardown: ' ME.message], false);
end

%% Cleanup
try
    delete(findall(groot,'Type','figure','Tag','EPsychMetricsExplorer'));
catch ME
    vprintf(2, ME);
end
try
    if ispref('epsych2_gui_MetricsExplorer','FigurePosition')
        rmpref('epsych2_gui_MetricsExplorer','FigurePosition');
    end
catch ME
    vprintf(2, ME);
end

%% Summary
labels = results(:,1);
passed = cell2mat(results(:,2));
for i = 1:numel(labels)
    if passed(i)
        fprintf('  PASS  %s\n', labels{i});
    else
        fprintf('  FAIL  %s\n', labels{i});
    end
end
fprintf('\n%d passed, %d failed, %d total\n\n', ...
    sum(passed), sum(~passed), numel(passed));

if any(~passed)
    error('smoke_test_metrics_explorer:Failed', '%d smoke test(s) failed.', sum(~passed));
end


function row = check(label, tf)
% row = check(label, tf)
% Record one assertion as a {label, logical} row.
row = {char(label), logical(tf)};
end


function tf = near(a, b, tol)
% Element-wise agreement, with NaN counted as agreeing with NaN: an undefined
% metric is a result here, not a missing one.
if nargin < 3, tol = 1e-12; end
a = a(:); b = b(:);
if ~isequal(size(a), size(b)), tf = false; return, end
both = isnan(a) & isnan(b);
tf = all(both | (abs(a - b) <= tol));
end


function tf = throwsWith(fcn, identifier)
% True when fcn throws the named identifier.
tf = false;
try
    fcn();
catch ME
    tf = strcmp(ME.identifier, identifier);
end
end


function tf = clampsTo(E, h, f, expectedH, expectedF)
% setPoint clamps into the plane rather than erroring.
E.setPoint(h, f);
tf = E.HitRate == expectedH && E.FalseAlarmRate == expectedF;
end


function Z = gridOf(E, key)
% The surface the explorer's current settings should produce for one metric,
% built from psychophysics.Metrics independently of the window.
[~, hv, fv] = E.surface();
[Fg, Hg] = meshgrid(fv, hv);
Z = gui.MetricsExplorer.evaluate(key, Hg, Fg, ...
    Correction = E.Correction, Bounds = E.Bounds, ...
    NSignal = E.NSignal, NNoise = E.NNoise);
end
