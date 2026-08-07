function graphData = dependencyGraph(obj, analysis)
% graphData = dependencyGraph(obj)
% graphData = dependencyGraph(obj, analysis)
%
% Build the parameter dependency graph implied by the Expression fields of
% this protocol: one node per parameter that either has an expression
% referencing another parameter or is referenced by one, and one edge per
% referenced pair. Pure data — no graphics — so the graph can be inspected
% headlessly; epsych.ProtocolDesigner.onShowParameterDependencyGraph draws it.
%
% Edges point from the referenced parameter to the parameter whose expression
% uses it, so following the arrows is the direction values flow at runtime.
%
% Parameters:
%   analysis  - Result of analyzeExpressions() (default: computed here).
%               Pass an existing analysis to reuse work already done.
%
% Returns:
%   graphData - struct with fields:
%     G       - digraph over 1:numel(nodes); G.Edges rows align with edges
%     nodes   - struct array (one per node):
%         key         - unique identifier ('Iface.Module.Param', or '?token')
%         label       - short display name ('Module.Param')
%         category    - 'calculated' | 'source' | 'dormant' | 'problem' | 'missing'
%         param       - hw.Parameter handle (empty for 'missing')
%         expression  - char, '' when the parameter has no expression
%         dispatch    - char, human-readable per-trial dispatch position
%         levels      - numel(Values) (0 for 'missing')
%         varies      - true when the value differs across trials
%         notes       - cellstr of per-node warnings
%     edges   - struct array (one per edge, in G.Edges order):
%         source/target - node indices
%         tokens        - cellstr of reference texts as written
%         category      - 'normal' | 'ambiguous' | 'stale' | 'cycle' | 'missing'
%         label         - short edge annotation ('' for 'normal')
%     meta    - struct: nCalculated, nIsolated, isolated (cellstr of
%               calculated parameters excluded because nothing links them)
%
% See also analyzeExpressions, dryRunExpressions.

arguments
    obj (1,1) epsych.Protocol
    analysis struct = obj.analyzeExpressions()
end

graphData = struct( ...
    'G', digraph(), ...
    'nodes', localEmptyNodes_(), ...
    'edges', localEmptyEdges_(), ...
    'meta', struct('nCalculated', numel(analysis), 'nIsolated', 0, 'isolated', {{}}));

if isempty(analysis)
    return
end

% Canonical, collision-free name for every parameter in the protocol. Analysis
% entries carry an 'Iface.Module.Param' fullName but references carry only
% hw.Parameter handles, so nodes are keyed by handle identity and named here.
[allParams, allNames] = localCatalogParameters_(obj);

nodes = localEmptyNodes_();
edges = localEmptyEdges_();
nodeParams = {};    % parallel to nodes; empty for 'missing' nodes
nodeKeys = {};      % parallel to nodes
edgeKeys = {};      % parallel to edges, 'source>target'

for k = 1:numel(analysis)
    a = analysis(k);
    if isempty(a.refs) && isempty(a.unresolvedRefs)
        continue    % nothing to draw; counted as isolated below
    end

    srcIdx = addParamNode(a.param);

    for r = 1:numel(a.refs)
        ref = a.refs(r);
        if isempty(ref.param)
            continue
        end
        [category, label] = localClassifyRef_(ref, a, analysis);
        addOrMergeEdge(addParamNode(ref.param), srcIdx, ref.token, category, label);
    end

    for u = 1:numel(a.unresolvedRefs)
        token = a.unresolvedRefs{u};
        addOrMergeEdge(addMissingNode(token), srcIdx, token, 'missing', 'missing');
    end
end

% Calculated parameters that neither reference nor are referenced by anything
% have no place in a dependency graph; report them so the caller can say so.
isolated = {};
for k = 1:numel(analysis)
    if isempty(analysis(k).refs) && isempty(analysis(k).unresolvedRefs) ...
            && isempty(findParamNode(analysis(k).param))
        isolated{end+1} = analysis(k).fullName;
    end
end
graphData.meta.nIsolated = numel(isolated);
graphData.meta.isolated = isolated;

if isempty(edges)
    return
end

% digraph reorders edges internally; realign the metadata to G.Edges so
% per-edge styling indexes correctly.
G = digraph([edges.source], [edges.target], [], numel(nodes));
order = findedge(G, [edges.source], [edges.target]);
edges(order) = edges;

graphData.G = G;
graphData.nodes = nodes;
graphData.edges = edges;


    function idx = findParamNode(p)
        idx = [];
        for i = 1:numel(nodeParams)
            if ~isempty(nodeParams{i}) && nodeParams{i} == p
                idx = i;
                return
            end
        end
    end


    function idx = addParamNode(p)
        % Node index for a parameter, creating the node on first reference.
        idx = findParamNode(p);
        if ~isempty(idx)
            return
        end

        catIdx = find(allParams == p, 1);
        if isempty(catIdx)
            key = p.FullName;   % parameter not reachable from the interface tree
        else
            key = allNames{catIdx};
        end

        nodes(end+1) = localNodeFromParam_(p, key, analysis);
        nodeParams{end+1} = p;
        nodeKeys{end+1} = key;
        idx = numel(nodes);
    end


    function idx = addMissingNode(token)
        key = ['?' token];
        idx = find(strcmp(nodeKeys, key), 1);
        if ~isempty(idx)
            return
        end

        nodes(end+1) = struct('key', key, 'label', token, ...
            'category', 'missing', 'param', hw.Parameter.empty(1, 0), ...
            'expression', '', 'dispatch', 'no such parameter', ...
            'levels', 0, 'varies', false, ...
            'notes', {{'Reference does not match any parameter in this protocol'}});
        nodeParams{end+1} = [];
        nodeKeys{end+1} = key;
        idx = numel(nodes);
    end


    function addOrMergeEdge(s, t, token, category, label)
        % One arrow per parameter pair: an expression referencing both X and
        % X.Max depends on X once. Keep every token, take the worst category.
        key = sprintf('%d>%d', s, t);
        existing = find(strcmp(edgeKeys, key), 1);
        if isempty(existing)
            edges(end+1) = struct('source', s, 'target', t, ...
                'tokens', {{token}}, 'category', category, 'label', label);
            edgeKeys{end+1} = key;
            return
        end

        if ~ismember(token, edges(existing).tokens)
            edges(existing).tokens{end+1} = token;
        end
        if localEdgeSeverity_(category) > localEdgeSeverity_(edges(existing).category)
            edges(existing).category = category;
            edges(existing).label = label;
        end
    end
end


function nodes = localEmptyNodes_()
nodes = struct('key', {}, 'label', {}, 'category', {}, 'param', {}, ...
    'expression', {}, 'dispatch', {}, 'levels', {}, 'varies', {}, 'notes', {});
end


function edges = localEmptyEdges_()
edges = struct('source', {}, 'target', {}, 'tokens', {}, 'category', {}, 'label', {});
end


function sev = localEdgeSeverity_(category)
order = {'normal', 'ambiguous', 'stale', 'cycle', 'missing'};
sev = find(strcmp(order, category), 1) - 1;
end


function [allParams, allNames] = localCatalogParameters_(obj)
% Flat parameter list plus a unique 'Iface.Module.Param' name for each, in the
% interface/module/parameter order analyzeExpressions walks.
allParams = hw.Parameter.empty(1, 0);
allNames = {};
for ifaceIdx = 1:numel(obj.Interfaces)
    iface = obj.Interfaces(ifaceIdx);
    ifaceType = char(iface.Type);
    for modIdx = 1:numel(iface.Module)
        module = iface.Module(modIdx);
        for paramIdx = 1:numel(module.Parameters)
            allParams(end+1) = module.Parameters(paramIdx);
            allNames{end+1} = sprintf('%s.%s.%s', ifaceType, module.Name, ...
                module.Parameters(paramIdx).Name);
        end
    end
end
allNames = matlab.lang.makeUniqueStrings(allNames);
end


function entry = localNodeFromParam_(p, key, analysis)
% Classify one parameter node. Parameters carrying an expression are described
% from their analysis entry; everything else is a plain value source.
entry = struct('key', key, 'label', p.FullName, 'category', 'source', ...
    'param', p, 'expression', '', 'dispatch', '', ...
    'levels', numel(p.Values), 'varies', numel(p.Values) > 1 || p.isRandom, ...
    'notes', {{}});

aIdx = localAnalysisIndex_(analysis, p);
if isempty(aIdx)
    if strcmp(p.Access, 'Read')
        entry.dispatch = 'read back from hardware';
    elseif entry.varies
        entry.dispatch = 'trial table value (varies across trials)';
    else
        entry.dispatch = 'fixed trial table value';
    end
    return
end

a = analysis(aIdx);
entry.expression = a.expressionText;
entry.notes = localNodeNotes_(a);

if a.isDispatched
    entry.dispatch = sprintf('#%d in per-trial dispatch order', a.dispatchIndex);
elseif a.onReadParam
    entry.dispatch = 'never (Read access)';
else
    entry.dispatch = 'only when set manually (UpdateEveryTrial off)';
end

% Dormant outranks 'problem': the expression never runs, so its defects are
% inert and the useful thing to show is that it is inert.
if a.multiLevelDormant || a.onReadParam
    entry.category = 'dormant';
elseif localHasDefect_(a)
    entry.category = 'problem';
else
    entry.category = 'calculated';
end
end


function notes = localNodeNotes_(a)
notes = {};
if a.multiLevelDormant
    notes{end+1} = 'Multi-level parameter: expression skipped at runtime';
end
if a.onReadParam
    notes{end+1} = 'Read access: expression never evaluates';
end
if a.hasAssignment
    notes{end+1} = 'Expression contains an assignment (runtime error)';
end
if a.hasSemicolon
    notes{end+1} = 'Expression contains '';'' (runtime error)';
end
if a.bareSelfRef
    notes{end+1} = 'References its own bare name (runtime error)';
end
if a.qualifiedSelfRef
    notes{end+1} = 'References itself: reads its own previous value';
end
if ~isempty(a.cycleWith)
    notes{end+1} = sprintf('Reference cycle with %s', strjoin(a.cycleWith, ', '));
end
if ~isempty(a.resolveError)
    notes{end+1} = sprintf('Reference resolution failed: %s', a.resolveError);
end
if a.usesValueVariable
    notes{end+1} = 'Uses the incoming `Value` in the expression';
end
if a.isRandom
    notes{end+1} = 'Randomized at runtime';
end
if a.hasPreUpdateFcn
    notes{end+1} = 'Has a PreUpdateFcn';
end
if a.hasEvaluatorFcn
    notes{end+1} = 'Has an EvaluatorFcn';
end
end


function tf = localHasDefect_(a)
tf = a.hasAssignment || a.hasSemicolon || a.bareSelfRef || a.qualifiedSelfRef ...
    || ~isempty(a.cycleWith) || ~isempty(a.unresolvedRefs) || ~isempty(a.resolveError);
end


function [category, label] = localClassifyRef_(ref, a, analysis)
% Severity order: a cycle makes staleness and ambiguity moot.
inCycle = ref.param == a.param;
if ~inCycle
    refAIdx = localAnalysisIndex_(analysis, ref.param);
    inCycle = ~isempty(refAIdx) && ismember(analysis(refAIdx).fullName, a.cycleWith);
end

if inCycle
    category = 'cycle';
    label = 'cycle';
elseif ref.dispatchedAfter && ref.variesAcrossTrials
    category = 'stale';
    label = 'previous trial';
elseif ref.ambiguous
    category = 'ambiguous';
    label = 'ambiguous';
else
    category = 'normal';
    label = '';
end
end


function idx = localAnalysisIndex_(analysis, p)
idx = [];
for k = 1:numel(analysis)
    if analysis(k).param == p
        idx = k;
        return
    end
end
end
