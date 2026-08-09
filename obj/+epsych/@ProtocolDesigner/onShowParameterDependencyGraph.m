function onShowParameterDependencyGraph(obj)
% onShowParameterDependencyGraph(obj)
% Plot the parameter dependency graph of the bound protocol in a new figure.
%
% Nodes are parameters that reference another parameter in their Expression,
% plus the parameters they reference. Arrows point from a referenced parameter
% to the parameter that uses it, so reading left to right follows the order
% values are derived. Each calculated parameter's expression is annotated on
% the arrows feeding it, so the graph reads as "these inputs, combined this
% way, give that value". Colour encodes each node's role and each edge's
% hazard; click a node for the full expression, dispatch position, and
% warnings.
%
% See also epsych.Protocol.dependencyGraph, onOpenCheckCalculationsDialog.

    graphData = obj.Protocol.dependencyGraph();

    if isempty(graphData.edges)
        localReportEmpty_(obj, graphData);
        return
    end

    nodes = graphData.nodes;
    edges = graphData.edges;

    fig = figure( ...
        'Name', 'Parameter Dependencies', ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'Position', localFigurePosition_(obj));

    ax = axes(fig, 'Position', [0.04 0.06 0.74 0.84]);

    % GraphPlot's own node labels sit on top of the markers and get rotated
    % once they are long, so they are suppressed and drawn by hand below.
    p = plot(ax, graphData.G, ...
        'Layout', 'layered', ...
        'Direction', 'right', ...
        'NodeLabel', repmat({''}, 1, numel(nodes)), ...
        'EdgeLabel', {edges.label}, ...
        'ArrowSize', 12, ...
        'MarkerSize', 8, ...
        'EdgeFontSize', 8, ...
        'EdgeFontAngle', 'normal', ...
        'Interpreter', 'none');

    localStyleNodes_(p, nodes);
    localStyleEdges_(p, edges);
    localAttachDataTips_(p, nodes, edges);

    axis(ax, 'off');
    ax.Toolbar.Visible = 'on';

    title(ax, 'Parameter Dependencies', 'FontSize', 14, 'FontWeight', 'bold');
    subtitle(ax, localSubtitle_(graphData), 'FontSize', 10, ...
        'FontAngle', 'italic', 'Color', [0.35 0.35 0.38], 'Interpreter', 'none');

    % Legend first: it shrinks the axes, and the labels are fitted to whatever
    % width the axes ends up with.
    localAddLegend_(ax, nodes, edges);
    nodeTxt = localLabelNodes_(ax, p, nodes);
    formulaTxt = localLabelFormulas_(ax, p, nodes, edges);

    % Fit first: text is sized in points, so a box only takes its final width in
    % data units once the limits have settled, and that width decides what it
    % overlaps. Fit again afterwards in case a nudge pushed a box off the axes.
    localFitLimitsToText_(ax, [nodeTxt formulaTxt]);
    localSpreadFormulas_(formulaTxt, nodeTxt);
    localFitLimitsToText_(ax, [nodeTxt formulaTxt]);

    localAddFormulaToggle_(fig, formulaTxt);

    obj.setStatus(sprintf('Parameter dependency graph: %d parameter(s), %d dependency link(s)', ...
        numel(nodes), numel(edges)), ...
        'Click a node in the new figure for its expression and warnings.');
end


function localReportEmpty_(obj, graphData)
% Nothing to draw: either no expressions at all, or expressions that reference
% nothing. Say which, since the fix differs.
    if graphData.meta.nCalculated == 0
        msg = ['No parameter in this protocol has an Expression, so there are ' ...
               'no dependencies to plot.' newline newline ...
               'Enter an expression in the Expression column of the parameter ' ...
               'table to derive one parameter from others.'];
        status = 'Parameter dependency graph: no calculated parameters';
        nextStep = 'Add an expression to a parameter, then plot dependencies again.';
    else
        msg = sprintf(['%d parameter(s) have an Expression, but none of them ' ...
                       'reference another parameter, so there are no ' ...
                       'dependencies to plot:' newline newline '  %s'], ...
                      graphData.meta.nCalculated, ...
                      strjoin(graphData.meta.isolated, [newline '  ']));
        status = 'Parameter dependency graph: no parameter references found';
        nextStep = 'Reference another parameter by name in an expression to create a dependency.';
    end

    uialert(obj.Figure, msg, 'Parameter Dependencies', 'Icon', 'info');
    obj.setStatus(status, nextStep);
end


function pos = localFigurePosition_(obj)
% Offset from the designer so the new figure does not land exactly on top.
    w = 1100;
    h = 760;
    parent = obj.Figure.Position;
    pos = [parent(1) + 60, max(60, parent(2) + parent(4) - h - 40), w, h];
end


function txt = localLabelNodes_(ax, p, nodes)
% Draw node labels as ordinary text so they stay horizontal and clear of the
% markers. The leftmost layer is labelled on its left and everything else on
% its right, so no label sits on the arrows leaving or entering its own layer.
% '*' marks values that differ from trial to trial; the subtitle spells that out.
    [onLeft, pad] = localLabelSide_(p);

    txt = gobjects(1, numel(nodes));
    for k = 1:numel(nodes)
        label = nodes(k).label;
        if nodes(k).varies
            label = [label ' *'];
        end

        if onLeft(k)
            align = 'right';
            x = p.XData(k) - pad;
        else
            align = 'left';
            x = p.XData(k) + pad;
        end

        txt(k) = text(ax, x, p.YData(k), label, ...
            'HorizontalAlignment', align, ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 10, ...
            'FontWeight', 'bold', ...
            'Color', localNodeStyle_(nodes(k).category).color, ...
            'Interpreter', 'none', ...
            'Clipping', 'off', ...
            'PickableParts', 'none', ...
            'Tag', 'nodeLabel');
    end
end


function [onLeft, pad] = localLabelSide_(p)
% Labels go on the left of the leftmost layer and on the right of every other,
% so a label never lands on the arrows entering or leaving its own layer.
    xSpread = max(max(p.XData) - min(p.XData), 1);
    onLeft = p.XData <= min(p.XData) + 0.01 * xSpread;
    pad = 0.12 * xSpread;
end


function txt = localLabelFormulas_(ax, p, nodes, edges)
% Annotate each calculated parameter with the expression that produces it,
% placed midway between the parameters feeding it and the parameter itself, so
% the formula sits on the arrows it explains. A calculated parameter with no
% contributors (a constant expression) carries its formula under its own
% marker instead. Long expressions are clipped here; the datatip has the full
% text.
    txt = gobjects(1, numel(nodes));
    n = 0;

    [onLeft, pad] = localLabelSide_(p);
    yStep = localMinSpacing_(p.YData);
    targets = [edges.target];

    for k = 1:numel(nodes)
        if isempty(nodes(k).expression)
            continue
        end

        src = [edges(targets == k).source];
        if isempty(src)
            x = p.XData(k) + pad * (1 - 2 * onLeft(k));
            y = p.YData(k) - 0.42 * yStep;
            if onLeft(k)
                align = 'right';
            else
                align = 'left';
            end
        else
            % Halfway from the centre of the contributors to the node they feed:
            % on the arrow itself when there is one contributor, and inside the
            % fan of arrows when there are several.
            x = mean([mean(p.XData(src)), p.XData(k)]);
            y = mean([mean(p.YData(src)), p.YData(k)]);
            align = 'center';
        end

        n = n + 1;
        txt(n) = text(ax, x, y, localFormulaText_(nodes(k)), ...
            'HorizontalAlignment', align, ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 8, ...
            'FontName', get(groot, 'FixedWidthFontName'), ...
            'Color', localNodeStyle_(nodes(k).category).color, ...
            'BackgroundColor', [1 1 1], ...
            'EdgeColor', [0.85 0.85 0.88], ...
            'Margin', 2, ...
            'Interpreter', 'none', ...
            'Clipping', 'off', ...
            'PickableParts', 'none', ...
            'Tag', 'formulaLabel');
    end

    txt = txt(1:n);
end


function txt = localFormulaText_(node)
% One line, whitespace collapsed, clipped to keep a long expression from
% spanning the whole figure.
    maxChars = 46;
    expr = strtrim(regexprep(char(node.expression), '\s+', ' '));
    if numel(expr) > maxChars
        expr = [expr(1:maxChars - 3) '...'];
    end
    txt = ['= ' expr];
end


function localSpreadFormulas_(txt, nodeTxt)
% A formula box is as wide as its expression, so it readily lands on a node
% label or on another formula. Nudge each box up or down, in growing steps,
% until it clears the node labels and the boxes already placed; boxes are only
% moved, never resized, so the shifted extent follows arithmetically.
    if isempty(txt)
        return
    end

    drawnow
    placed = vertcat(nodeTxt.Extent);

    for k = 1:numel(txt)
        ext = txt(k).Extent;
        % One step is one box height: enough to clear whatever it landed on,
        % and small enough that the formula stays with the arrows it explains.
        offsets = 1.15 * ext(4) * [0, 1, -1, 2, -2, 3, -3];
        for o = offsets
            if ~any(localBoxesOverlap_(ext + [0 o 0 0], placed))
                break
            end
        end

        if o ~= 0
            pos = txt(k).Position;
            txt(k).Position = [pos(1), pos(2) + o, pos(3)];
            ext(2) = ext(2) + o;
        end
        placed(end+1, :) = ext;
    end
end


function tf = localBoxesOverlap_(box, others)
% box: [x y w h]; others: one such row per already-placed box.
    if isempty(others)
        tf = false;
        return
    end
    tf = box(1) < others(:, 1) + others(:, 3) & box(1) + box(3) > others(:, 1) ...
       & box(2) < others(:, 2) + others(:, 4) & box(2) + box(4) > others(:, 2);
end


function step = localMinSpacing_(v)
% Smallest gap between distinct coordinates: the layout's own row pitch, which
% is the natural unit for nudging annotations.
    d = diff(unique(v(:)));
    if isempty(d)
        step = 1;
    else
        step = min(d);
    end
end


function localAddFormulaToggle_(fig, txt)
% Formulas are the point of the annotation but they crowd a dense graph, so
% they can be switched off without redrawing.
    if isempty(txt)
        return
    end

    uicontrol(fig, ...
        'Style', 'checkbox', ...
        'String', 'Show formulas', ...
        'Units', 'normalized', ...
        'Position', [0.80 0.015 0.18 0.035], ...
        'Value', 1, ...
        'BackgroundColor', 'w', ...
        'FontSize', 9, ...
        'Tag', 'formulaToggle', ...
        'Callback', @(src, ~) set(txt(isgraphics(txt)), 'Visible', localOnOff_(src.Value)));
end


function state = localOnOff_(value)
    if value
        state = 'on';
    else
        state = 'off';
    end
end


function localFitLimitsToText_(ax, txt)
% Widen the axes until every label fits inside it. Text extents are reported in
% data units but sized in points, so a change to the limits changes them again;
% two passes are enough to settle at this scale.
    for pass = 1:2
        drawnow limitrate
        ext = vertcat(txt.Extent);
        xSpan = [min(ext(:, 1)), max(ext(:, 1) + ext(:, 3))];
        ySpan = [min(ext(:, 2)), max(ext(:, 2) + ext(:, 4))];

        xMargin = 0.03 * max(diff(xSpan), eps);
        yMargin = 0.08 * max(diff(ySpan), eps);

        cur = xlim(ax);
        xlim(ax, [min(cur(1), xSpan(1)) - xMargin, max(cur(2), xSpan(2)) + xMargin]);
        cur = ylim(ax);
        ylim(ax, [min(cur(1), ySpan(1)) - yMargin, max(cur(2), ySpan(2)) + yMargin]);
    end
end


function localStyleNodes_(p, nodes)
    colors = zeros(numel(nodes), 3);
    markers = cell(1, numel(nodes));
    sizes = zeros(1, numel(nodes));
    for k = 1:numel(nodes)
        spec = localNodeStyle_(nodes(k).category);
        colors(k, :) = spec.color;
        markers{k} = spec.marker;
        sizes(k) = spec.size;
    end
    p.NodeColor = colors;
    p.Marker = markers;
    p.MarkerSize = sizes;
end


function localStyleEdges_(p, edges)
    colors = zeros(numel(edges), 3);
    widths = zeros(1, numel(edges));
    styles = cell(1, numel(edges));
    for k = 1:numel(edges)
        spec = localEdgeStyle_(edges(k).category);
        colors(k, :) = spec.color;
        widths(k) = spec.width;
        styles{k} = spec.style;
    end
    p.EdgeColor = colors;
    p.LineWidth = widths;
    p.LineStyle = styles;
    p.EdgeLabelColor = colors;
end


function spec = localNodeStyle_(category)
    switch category
        case 'calculated'
            spec = struct('color', [0.13 0.40 0.72], 'marker', 'o', 'size', 9);
        case 'source'
            spec = struct('color', [0.15 0.55 0.32], 'marker', 's', 'size', 8);
        case 'dormant'
            spec = struct('color', [0.58 0.58 0.62], 'marker', 'o', 'size', 8);
        case 'problem'
            spec = struct('color', [0.80 0.15 0.12], 'marker', 'p', 'size', 13);
        otherwise   % 'missing'
            spec = struct('color', [0.80 0.15 0.12], 'marker', 'x', 'size', 11);
    end
end


function spec = localEdgeStyle_(category)
    switch category
        case 'stale'
            spec = struct('color', [0.88 0.52 0.05], 'width', 2.0, 'style', '-');
        case 'cycle'
            spec = struct('color', [0.80 0.15 0.12], 'width', 2.4, 'style', '-');
        case 'ambiguous'
            spec = struct('color', [0.55 0.25 0.65], 'width', 1.8, 'style', '-');
        case 'missing'
            spec = struct('color', [0.80 0.15 0.12], 'width', 1.5, 'style', ':');
        otherwise   % 'normal'
            spec = struct('color', [0.50 0.53 0.57], 'width', 1.3, 'style', '-');
    end
end


function localAttachDataTips_(p, nodes, edges)
% One datatip template serves both nodes and edges, so every row is filled for
% both: edge rows repeat the source-to-target description.
    nNodes = numel(nodes);
    nEdges = numel(edges);

    name = cell(1, nNodes + nEdges);
    role = cell(1, nNodes + nEdges);
    detail = cell(1, nNodes + nEdges);
    note = cell(1, nNodes + nEdges);

    for k = 1:nNodes
        name{k} = nodes(k).key;
        role{k} = localRoleText_(nodes(k));
        detail{k} = localNodeDetail_(nodes(k));
        note{k} = localJoinNotes_(nodes(k).notes);
    end

    for k = 1:nEdges
        e = edges(k);
        idx = nNodes + k;
        name{idx} = sprintf('%s  -->  %s', nodes(e.source).label, nodes(e.target).label);
        role{idx} = localEdgeRoleText_(e.category);
        detail{idx} = sprintf('referenced as: %s', strjoin(e.tokens, ', '));
        note{idx} = localEdgeNote_(e, nodes);
    end

    % Rows span nodes then edges: GraphPlot indexes node clicks by node number,
    % and the trailing block covers edge clicks where the release supports them.
    dt = p.DataTipTemplate;
    dt.Interpreter = 'none';
    dt.DataTipRows = [ ...
        dataTipTextRow('', name), ...
        dataTipTextRow('', role), ...
        dataTipTextRow('', detail), ...
        dataTipTextRow('', note)];
end


function txt = localRoleText_(node)
    switch node.category
        case 'calculated'
            txt = 'calculated from other parameters';
        case 'source'
            txt = 'value source (no expression)';
        case 'dormant'
            txt = 'expression never evaluates at runtime';
        case 'problem'
            txt = 'calculated, but the expression has a problem';
        otherwise
            txt = 'unresolved reference';
    end
end


function txt = localNodeDetail_(node)
    parts = {};
    if ~isempty(node.expression)
        parts{end+1} = sprintf('= %s', node.expression);
    end
    parts{end+1} = sprintf('set: %s', node.dispatch);
    if node.levels > 1
        parts{end+1} = sprintf('%d trial levels', node.levels);
    end
    txt = strjoin(parts, ' | ');
end


function txt = localEdgeRoleText_(category)
    switch category
        case 'stale'
            txt = 'uses the PREVIOUS trial''s value';
        case 'cycle'
            txt = 'part of a reference cycle';
        case 'ambiguous'
            txt = 'reference matches more than one parameter';
        case 'missing'
            txt = 'reference resolves to nothing';
        otherwise
            txt = 'dependency';
    end
end


function txt = localEdgeNote_(edge, nodes)
    switch edge.category
        case 'stale'
            txt = sprintf('%s is dispatched after %s and varies across trials', ...
                nodes(edge.source).label, nodes(edge.target).label);
        case 'cycle'
            txt = 'values depend on evaluation order';
        case 'ambiguous'
            txt = 'the first match is used silently';
        case 'missing'
            txt = 'likely an evaluation error at runtime';
        otherwise
            txt = '';
    end
end


function txt = localJoinNotes_(notes)
    if isempty(notes)
        txt = '';
    else
        txt = strjoin(notes, '; ');
    end
end


function txt = localSubtitle_(graphData)
    parts = {'arrows point from a parameter to the one calculated from it', ...
             '* = value varies across trials'};
    if graphData.meta.nIsolated > 0
        parts{end+1} = sprintf('%d calculated parameter(s) reference nothing and are not shown', ...
            graphData.meta.nIsolated);
    end
    txt = strjoin(parts, '   |   ');
end


function localAddLegend_(ax, nodes, edges)
% Legend entries are drawn from dummy handles because a GraphPlot is a single
% object; only categories actually present are listed.
    nodeCats = {'calculated', 'problem', 'dormant', 'source', 'missing'};
    nodeText = { ...
        'Calculated from other parameters', ...
        'Calculated, expression has a problem', ...
        'Expression never evaluates', ...
        'Value source (no expression)', ...
        'Unresolved reference'};

    edgeCats = {'normal', 'stale', 'cycle', 'ambiguous', 'missing'};
    edgeText = { ...
        'Dependency', ...
        'Uses previous trial''s value', ...
        'Reference cycle', ...
        'Ambiguous reference', ...
        'Missing reference'};

    hold(ax, 'on');
    handles = gobjects(1, 0);
    labels = {};

    present = unique({nodes.category});
    for k = 1:numel(nodeCats)
        if ~ismember(nodeCats{k}, present)
            continue
        end
        spec = localNodeStyle_(nodeCats{k});
        handles(end+1) = plot(ax, NaN, NaN, ...
            'LineStyle', 'none', ...
            'Marker', spec.marker, ...
            'MarkerSize', 9, ...
            'MarkerEdgeColor', spec.color, ...
            'MarkerFaceColor', spec.color);
        labels{end+1} = nodeText{k};
    end

    present = unique({edges.category});
    for k = 1:numel(edgeCats)
        if ~ismember(edgeCats{k}, present)
            continue
        end
        spec = localEdgeStyle_(edgeCats{k});
        handles(end+1) = plot(ax, [NaN NaN], [NaN NaN], ...
            'LineStyle', spec.style, ...
            'LineWidth', max(spec.width, 1.6), ...
            'Color', spec.color);
        labels{end+1} = edgeText{k};
    end

    hold(ax, 'off');

    lgd = legend(ax, handles, labels, 'Location', 'eastoutside', ...
        'Interpreter', 'none', 'FontSize', 9, 'Box', 'on');
    lgd.Title.String = 'Legend';
    lgd.Title.FontWeight = 'bold';
end
