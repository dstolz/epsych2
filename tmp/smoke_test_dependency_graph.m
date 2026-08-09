function smoke_test_dependency_graph()
% smoke_test_dependency_graph()
% Exercise epsych.Protocol.dependencyGraph (node/edge classification, edge
% merging, G.Edges alignment) and the Protocol Designer's
% onShowParameterDependencyGraph plot, headlessly.
%
%   matlab -batch "run('tmp/smoke_test_dependency_graph.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

% ===== A. Empty protocol: no expressions ================================
try
    P = epsych.Protocol;
    P.addParameter('Software', 'Plain', 5);
    gd = P.dependencyGraph();

    assert(isempty(gd.edges), 'expected no edges');
    assert(isempty(gd.nodes), 'expected no nodes');
    assert(gd.meta.nCalculated == 0, 'expected 0 calculated parameters');
    fprintf('PASS: A. protocol with no expressions yields an empty graph\n');
catch ME
    failures{end+1} = sprintf('A. empty graph: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% ===== B. Isolated calculated parameter (expression, no references) ======
try
    P = epsych.Protocol;
    pc = P.addParameter('Software', 'Const', 0);
    pc.Expression = "42";
    gd = P.dependencyGraph();

    assert(isempty(gd.edges), 'expected no edges for a reference-free expression');
    assert(gd.meta.nCalculated == 1, 'expected 1 calculated parameter');
    assert(gd.meta.nIsolated == 1, 'expected the parameter to be reported isolated');
    assert(endsWith(gd.meta.isolated{1}, '.Const'), 'wrong isolated name: %s', gd.meta.isolated{1});
    fprintf('PASS: B. reference-free expression reported as isolated\n');
catch ME
    failures{end+1} = sprintf('B. isolated: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. Basic chain: Src -> Mid -> Out ================================
try
    P = epsych.Protocol;
    P.addParameter('Software', 'Src', 5);
    pMid = P.addParameter('Software', 'Mid', 0);
    pMid.Expression = "Src * 2";
    pOut = P.addParameter('Software', 'Out', 0);
    pOut.Expression = "Mid + 1";

    gd = P.dependencyGraph();

    assert(numel(gd.nodes) == 3, 'expected 3 nodes, got %d', numel(gd.nodes));
    assert(numel(gd.edges) == 2, 'expected 2 edges, got %d', numel(gd.edges));
    assert(numnodes(gd.G) == 3 && numedges(gd.G) == 2, 'digraph size mismatch');

    cats = containers.Map({gd.nodes.label}, {gd.nodes.category});
    assert(strcmp(cats('Params.Src'), 'source'), 'Src should be a source, got %s', cats('Params.Src'));
    assert(strcmp(cats('Params.Mid'), 'calculated'), 'Mid should be calculated, got %s', cats('Params.Mid'));
    assert(strcmp(cats('Params.Out'), 'calculated'), 'Out should be calculated, got %s', cats('Params.Out'));

    % Arrows point from the referenced parameter to the calculated one
    labelOf = {gd.nodes.label};
    pair = cell(1, numel(gd.edges));
    for k = 1:numel(gd.edges)
        pair{k} = sprintf('%s->%s', labelOf{gd.edges(k).source}, labelOf{gd.edges(k).target});
    end
    assert(ismember('Params.Src->Params.Mid', pair), 'missing Src->Mid edge: %s', strjoin(pair, ','));
    assert(ismember('Params.Mid->Params.Out', pair), 'missing Mid->Out edge: %s', strjoin(pair, ','));

    % Metadata must line up with G.Edges row order (per-edge styling depends on it)
    ends = gd.G.Edges.EndNodes;
    assert(isequal(ends(:, 1)', [gd.edges.source]) && isequal(ends(:, 2)', [gd.edges.target]), ...
        'edges struct is not aligned with G.Edges');

    fprintf('PASS: C. dependency chain, direction, and G.Edges alignment\n');
catch ME
    failures{end+1} = sprintf('C. chain: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end

% ===== D. Edge merging: two tokens, one arrow ===========================
try
    P = epsych.Protocol;
    P.addParameter('Software', 'Src', 5, Min=0, Max=100);
    pOut = P.addParameter('Software', 'Out', 0);
    pOut.Expression = "Src + Src.Max";

    gd = P.dependencyGraph();
    assert(numel(gd.edges) == 1, 'expected the two tokens to merge into 1 edge, got %d', numel(gd.edges));
    assert(numel(gd.edges(1).tokens) == 2, 'expected 2 merged tokens, got %d', numel(gd.edges(1).tokens));
    assert(all(ismember({'Src', 'Src.Max'}, gd.edges(1).tokens)), ...
        'merged tokens wrong: %s', strjoin(gd.edges(1).tokens, ','));
    fprintf('PASS: D. multiple references to one parameter merge into one arrow\n');
catch ME
    failures{end+1} = sprintf('D. edge merge: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end

% ===== E. Stale, missing, dormant, and problem classification ===========
try
    P = epsych.Protocol;
    pCalc = P.addParameter('Software', 'Calc', 0);
    pCalc.Expression = "Vary + 1";            % Vary is dispatched later
    P.addParameter('Software', 'Vary', [10 20]);
    pMiss = P.addParameter('Software', 'Missing', 0);
    pMiss.Expression = "Nope.Nada + 1";
    pDorm = P.addParameter('Software', 'Dormant', [1 2 3]);
    pDorm.Expression = "Vary * 2";
    pBad = P.addParameter('Software', 'Bad', 0);
    pBad.Expression = "Bad + 1";              % bare self-reference

    gd = P.dependencyGraph();

    byLabel = containers.Map({gd.nodes.label}, num2cell(1:numel(gd.nodes)));
    catOf = @(lbl) gd.nodes(byLabel(lbl)).category;

    assert(strcmp(catOf('Params.Calc'), 'calculated'), 'Calc: %s', catOf('Params.Calc'));
    assert(strcmp(catOf('Params.Vary'), 'source'), 'Vary: %s', catOf('Params.Vary'));
    assert(gd.nodes(byLabel('Params.Vary')).varies, 'Vary should be flagged as varying');
    assert(strcmp(catOf('Params.Dormant'), 'dormant'), 'Dormant: %s', catOf('Params.Dormant'));
    assert(strcmp(catOf('Params.Missing'), 'problem'), 'Missing: %s', catOf('Params.Missing'));
    assert(strcmp(catOf('Nope.Nada'), 'missing'), 'Nope.Nada: %s', catOf('Nope.Nada'));

    % Bad has a bare self-reference and no resolvable refs, so it is isolated
    assert(any(endsWith(gd.meta.isolated, '.Bad')), 'Bad should be isolated');

    edgeCat = @(sLbl, tLbl) gd.edges(arrayfun(@(e) e.source == byLabel(sLbl) && e.target == byLabel(tLbl), gd.edges)).category;
    assert(strcmp(edgeCat('Params.Vary', 'Params.Calc'), 'stale'), ...
        'Vary->Calc should be stale, got %s', edgeCat('Params.Vary', 'Params.Calc'));
    assert(strcmp(edgeCat('Nope.Nada', 'Params.Missing'), 'missing'), 'missing edge not classified');

    fprintf('PASS: E. stale / missing / dormant / problem classification\n');
catch ME
    failures{end+1} = sprintf('E. classification: %s', ME.message);
    fprintf('FAIL: E. %s\n', ME.message);
end

% ===== F. Reference cycle ===============================================
try
    P = epsych.Protocol;
    pA = P.addParameter('Software', 'CycA', 1);
    pB = P.addParameter('Software', 'CycB', 1);
    moduleName = pA.Module.Name;
    pA.Expression = string(sprintf('%s.CycB + 1', moduleName));
    pB.Expression = string(sprintf('%s.CycA + 1', moduleName));

    gd = P.dependencyGraph();
    assert(numel(gd.edges) == 2, 'expected 2 cycle edges, got %d', numel(gd.edges));
    assert(all(strcmp({gd.edges.category}, 'cycle')), ...
        'both edges should be cycle, got %s', strjoin({gd.edges.category}, ','));
    assert(all(strcmp({gd.nodes.category}, 'problem')), ...
        'both cycle nodes should be problem, got %s', strjoin({gd.nodes.category}, ','));
    fprintf('PASS: F. reference cycle detected on nodes and edges\n');
catch ME
    failures{end+1} = sprintf('F. cycle: %s', ME.message);
    fprintf('FAIL: F. %s\n', ME.message);
end

% ===== G. Example protocol ==============================================
protocolFile = fullfile(here, 'TEST_NEW_PROTOCOL2.eprot');
if exist(protocolFile, 'file')
    try
        P = epsych.Protocol.load(protocolFile);
        gd = P.dependencyGraph();
        assert(~isempty(gd.edges), 'example protocol produced no dependency edges');
        assert(numnodes(gd.G) == numel(gd.nodes), 'node count mismatch');
        assert(numedges(gd.G) == numel(gd.edges), 'edge count mismatch');
        ends = gd.G.Edges.EndNodes;
        assert(isequal(ends(:, 1)', [gd.edges.source]) && isequal(ends(:, 2)', [gd.edges.target]), ...
            'edges struct not aligned with G.Edges on the example protocol');
        assert(all(ismember({gd.nodes.category}, ...
            {'calculated', 'source', 'dormant', 'problem', 'missing'})), 'unknown node category');
        assert(all(ismember({gd.edges.category}, ...
            {'normal', 'ambiguous', 'stale', 'cycle', 'missing'})), 'unknown edge category');
        assert(all(cellfun(@(t) ~isempty(t), {gd.edges.tokens})), 'an edge carries no reference token');
        fprintf('PASS: G. dependency graph on TEST_NEW_PROTOCOL2.eprot (%d nodes, %d edges)\n', ...
            numel(gd.nodes), numel(gd.edges));
    catch ME
        failures{end+1} = sprintf('G. example protocol: %s', ME.message);
        fprintf('FAIL: G. %s\n', ME.message);
    end
else
    fprintf('SKIP: G. example protocol not found (%s)\n', protocolFile);
end

% ===== H. Designer plot round trip ======================================
try
    % Reference the multi-level parameter through a scalar property: a plain
    % reference to it would be consumed by the designer's design-time level
    % generator (expression cleared, Values expanded) before the graph is built.
    P = epsych.Protocol;
    P.addParameter('Software', 'Src', 5, Min=0, Max=100);
    pMid = P.addParameter('Software', 'Mid', 0);
    pMid.Expression = "Src * 2 + Src.Max";
    pOut = P.addParameter('Software', 'Out', 0);
    pOut.Expression = "Mid + Vary.Max";
    P.addParameter('Software', 'Vary', [1 2 3]);
    pMiss = P.addParameter('Software', 'Miss', 0);
    pMiss.Expression = "Ghost.Gone + Mid";

    before = findall(groot, 'Type', 'figure');
    D = epsych.ProtocolDesigner(P);
    D.onShowParameterDependencyGraph();
    drawnow;

    created = setdiff(findall(groot, 'Type', 'figure'), before);
    plotFig = created(arrayfun(@(f) strcmp(f.Name, 'Parameter Dependencies'), created));
    assert(isscalar(plotFig), 'expected exactly one new "Parameter Dependencies" figure');

    gp = findobj(plotFig, 'Type', 'GraphPlot');
    assert(isscalar(gp), 'expected one GraphPlot in the figure');
    assert(size(gp.NodeColor, 1) == numel(gp.XData), 'per-node colours not applied');
    assert(iscell(gp.Marker) && numel(gp.Marker) == numel(gp.XData), 'per-node markers not applied');

    ax = findobj(plotFig, 'Type', 'axes');
    assert(~isempty(ax), 'no axes in the plot figure');

    % Labels are drawn as text objects, not GraphPlot NodeLabel
    labels = get(findobj(ax, 'Tag', 'nodeLabel'), 'String');
    assert(numel(labels) == numel(gp.XData), 'expected one text label per node, got %d of %d', ...
        numel(labels), numel(gp.XData));
    assert(any(contains(labels, 'Params.Vary *')), ...
        'multi-level parameter not marked with *: %s', strjoin(labels', ', '));
    assert(any(strcmp(labels, 'Ghost.Gone')), 'unresolved reference not labelled');

    % Every parameter with an expression is annotated with its formula, placed
    % between the parameters feeding it and itself
    formulas = get(findobj(ax, 'Tag', 'formulaLabel'), 'String');
    assert(numel(formulas) == 3, 'expected 3 formula annotations, got %d', numel(formulas));
    assert(any(strcmp(formulas, '= Src * 2 + Src.Max')), ...
        'Mid formula not annotated: %s', strjoin(formulas', ', '));
    assert(any(strcmp(formulas, '= Mid + Vary.Max')), ...
        'Out formula not annotated: %s', strjoin(formulas', ', '));

    % Mid is calculated from Src alone, so its formula sits between the two
    lSrc = findobj(ax, 'Tag', 'nodeLabel', 'String', 'Params.Src');
    lMid = findobj(ax, 'Tag', 'nodeLabel', 'String', 'Params.Mid');
    fMid = findobj(ax, 'Tag', 'formulaLabel', 'String', '= Src * 2 + Src.Max');
    assert(isscalar(lSrc) && isscalar(lMid) && isscalar(fMid), ...
        'expected one Src label, one Mid label, and one Mid formula');
    xSrc = lSrc.Position(1);
    xMid = lMid.Position(1);
    assert(fMid.Position(1) > min(xSrc, xMid) && fMid.Position(1) < max(xSrc, xMid), ...
        'Mid formula is not between Src and Mid');

    toggle = findobj(plotFig, 'Tag', 'formulaToggle');
    assert(isscalar(toggle), 'expected a "Show formulas" toggle');
    toggle.Value = 0;
    toggle.Callback(toggle, []);
    assert(strcmp(fMid.Visible, 'off'), 'toggle did not hide the formula annotations');
    toggle.Value = 1;
    toggle.Callback(toggle, []);
    assert(strcmp(fMid.Visible, 'on'), 'toggle did not restore the formula annotations');
    lgd = findobj(plotFig, 'Type', 'legend');
    assert(~isempty(lgd), 'no legend in the plot figure');
    assert(any(contains(lgd(1).String, 'Missing reference')), ...
        'legend missing the "Missing reference" entry: %s', strjoin(lgd(1).String, ','));

    delete(plotFig);
    delete(D.Figure);
    fprintf('PASS: H. designer plots the dependency graph into a new figure\n');
catch ME
    failures{end+1} = sprintf('H. designer plot: %s', ME.message);
    fprintf('FAIL: H. %s\n', ME.message);
end

% ===== I. Empty-graph path shows an alert, not a figure =================
try
    P = epsych.Protocol;
    P.addParameter('Software', 'Plain', 5);

    before = findall(groot, 'Type', 'figure');
    D = epsych.ProtocolDesigner(P);
    D.onShowParameterDependencyGraph();
    drawnow;

    created = setdiff(findall(groot, 'Type', 'figure'), before);
    assert(~any(arrayfun(@(f) strcmp(f.Name, 'Parameter Dependencies'), created)), ...
        'an empty graph should not open a plot figure');
    delete(D.Figure);
    fprintf('PASS: I. no plot figure when there are no dependencies\n');
catch ME
    failures{end+1} = sprintf('I. empty path: %s', ME.message);
    fprintf('FAIL: I. %s\n', ME.message);
end

% ===== Summary ==========================================================
if isempty(failures)
    fprintf('\nsmoke_test_dependency_graph: ALL SECTIONS PASS\n');
else
    fprintf('\nsmoke_test_dependency_graph: %d FAILURE(S)\n', numel(failures));
    error('smoke_test_dependency_graph failed:\n  %s', strjoin(failures, sprintf('\n  ')));
end
end
