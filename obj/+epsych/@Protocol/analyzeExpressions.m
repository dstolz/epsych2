function analysis = analyzeExpressions(obj)
% analysis = analyzeExpressions(obj)
%
% Static analysis of all parameter Expressions in this protocol, without
% compiling and without evaluating any expression. Used by validate() and by
% the Protocol Designer's Check Calculations tool to surface conditions that
% only manifest at runtime (dispatch ordering, multi-level dormancy,
% unresolvable references, cycles).
%
% Returns:
%   analysis - struct array, one entry per visible parameter with a nonempty
%       Expression:
%       param             - hw.Parameter handle
%       fullName          - 'InterfaceType.Module.Param' (validate() style)
%       expressionText    - char, the trimmed expression
%       dispatchIndex     - Position in the runtime per-trial dispatch order
%                           (epsych.Runtime.dispatchNextTrial), NaN if the
%                           parameter is not dispatched every trial
%       isDispatched      - true when dispatched every trial
%       multiLevelDormant - true when numel(Values) > 1: the runtime skips
%                           the expression entirely (design-time level
%                           generator only). Always false for index-selecting
%                           types, where many items are the normal case
%       selectsIndex      - true for 'String'/'StimType', where the result is
%                           a 1-based index into the parameter's item list
%                           rather than the value itself
%       itemCount         - numel(Values); the valid index range is 1..itemCount
%                           when selectsIndex is true
%       onReadParam       - true when Access == 'Read' (set.Value forbidden;
%                           expression never evaluates)
%       hasSemicolon      - true when text contains ';' (runtime error)
%       hasAssignment     - true when text contains an assignment (runtime
%                           eval error; the designer rejects these)
%       usesValueVariable - true when the expression references `Value`
%       bareSelfRef       - true when the expression references its own bare
%                           name (unbound at runtime -> eval error)
%       qualifiedSelfRef  - true when it references itself as Module.Self
%                           (silently reads its own previous value)
%       refs              - struct array of resolved references: token, kind,
%                           targetFullName, param, dispatchIndex,
%                           variesAcrossTrials, isReadAccess,
%                           dispatchedAfter, ambiguous
%       unresolvedRefs    - cellstr of Name.Name tokens matching reference
%                           syntax but resolving to no parameter
%       resolveError      - char, message when reference resolution itself
%                           failed ('' when none)
%       cycleWith         - cellstr of other expression parameters forming a
%                           reference cycle with this one
%       clampMin/clampMax - The bounds set.Value silently clamps results to
%       hasPreUpdateFcn / hasEvaluatorFcn - enabled callback present
%                           (stages a design-time simulation cannot execute)
%       isRandom          - true when randomize_value applies at runtime

analysis = localEmptyAnalysis_();

% Resolution scope matches the runtime evaluator: every parameter of every
% module, regardless of visibility or access.
allParams = hw.Parameter.empty(1, 0);
for ifaceIdx = 1:numel(obj.Interfaces)
    modules = obj.Interfaces(ifaceIdx).Module;
    for modIdx = 1:numel(modules)
        if ~isempty(modules(modIdx).Parameters)
            allParams = [allParams, modules(modIdx).Parameters];
        end
    end
end

% Per-trial dispatch order: compiled parameters (visible, ~Read) filtered to
% UpdateEveryTrial, in interface/module/parameter order, then permuted so
% expression parameters follow the parameters whose values they read.
% Mirrors Protocol.compile_internal + epsych.Runtime.dispatchNextTrial,
% which applies the same hw.Parameter.orderByDependencies permutation.
dispatchParams = hw.Parameter.empty(1, 0);
for ifaceIdx = 1:numel(obj.Interfaces)
    modules = obj.Interfaces(ifaceIdx).Module;
    for modIdx = 1:numel(modules)
        params = modules(modIdx).Parameters;
        for paramIdx = 1:numel(params)
            p = params(paramIdx);
            if p.Visible && ~strcmp(p.Access, 'Read') && p.UpdateEveryTrial
                dispatchParams(end+1) = p;
            end
        end
    end
end
dispatchParams = dispatchParams(hw.Parameter.orderByDependencies(dispatchParams, allParams));

for ifaceIdx = 1:numel(obj.Interfaces)
    iface = obj.Interfaces(ifaceIdx);
    ifaceType = char(iface.Type);
    for modIdx = 1:numel(iface.Module)
        module = iface.Module(modIdx);
        for paramIdx = 1:numel(module.Parameters)
            p = module.Parameters(paramIdx);
            exprText = strtrim(char(p.Expression));
            if ~p.Visible || isempty(exprText)
                continue
            end

            entry = localAnalyzeOne_(p, exprText, ifaceType, module, allParams, dispatchParams);
            analysis(end+1) = entry;
        end
    end
end

% Reference cycles among expression parameters
analysis = localFindCycles_(analysis);
end


function analysis = localEmptyAnalysis_()
analysis = struct('param', {}, 'fullName', {}, 'expressionText', {}, ...
    'dispatchIndex', {}, 'isDispatched', {}, 'multiLevelDormant', {}, ...
    'selectsIndex', {}, 'itemCount', {}, ...
    'onReadParam', {}, 'hasSemicolon', {}, 'hasAssignment', {}, ...
    'usesValueVariable', {}, 'bareSelfRef', {}, 'qualifiedSelfRef', {}, ...
    'refs', {}, 'unresolvedRefs', {}, 'resolveError', {}, 'cycleWith', {}, ...
    'clampMin', {}, 'clampMax', {}, 'hasPreUpdateFcn', {}, ...
    'hasEvaluatorFcn', {}, 'isRandom', {});
end


function entry = localAnalyzeOne_(p, exprText, ifaceType, module, allParams, dispatchParams)
selectsIndex = hw.Parameter.expressionSelectsIndex(p.Type);
entry = struct( ...
    'param', p, ...
    'fullName', sprintf('%s.%s.%s', ifaceType, module.Name, p.Name), ...
    'expressionText', exprText, ...
    'dispatchIndex', NaN, ...
    'isDispatched', false, ...
    'multiLevelDormant', numel(p.Values) > 1 && ~selectsIndex, ...
    'selectsIndex', selectsIndex, ...
    'itemCount', numel(p.Values), ...
    'onReadParam', strcmp(p.Access, 'Read'), ...
    'hasSemicolon', contains(exprText, ';'), ...
    'hasAssignment', ~isempty(regexp(exprText, '(?<![<>=~])=(?![=])', 'once')), ...
    'usesValueVariable', ~isempty(regexp(exprText, '(?<!\.)\<Value\>(?!\.)', 'once')), ...
    'bareSelfRef', false, ...
    'qualifiedSelfRef', false, ...
    'refs', localEmptyRefs_(), ...
    'unresolvedRefs', {{}}, ...
    'resolveError', '', ...
    'cycleWith', {{}}, ...
    'clampMin', p.Min, ...
    'clampMax', p.Max, ...
    'hasPreUpdateFcn', isa(p.PreUpdateFcn, 'function_handle') && p.PreUpdateFcnEnabled, ...
    'hasEvaluatorFcn', isa(p.EvaluatorFcn, 'function_handle') && p.EvaluatorFcnEnabled, ...
    'isRandom', p.isRandom);

dIdx = find(dispatchParams == p, 1);
if ~isempty(dIdx)
    entry.dispatchIndex = dIdx;
    entry.isDispatched = true;
end

selfPattern = ['(?<!\.)\<' regexptranslate('escape', p.Name) '\>(?!\.)'];
entry.bareSelfRef = ~isempty(regexp(exprText, selfPattern, 'once'));

% Resolve references with placeholder values (first design-time level; the
% resolver only needs values to populate its context, which we discard).
try
    [~, ~, info] = hw.Parameter.resolveExpressionContext( ...
        exprText, NaN, p, ...
        @() module.Parameters, ...
        @() allParams, ...
        @(q) localDesignValue_(q));
    entry.unresolvedRefs = info.unresolvedQualified;
    entry.usesValueVariable = entry.usesValueVariable || info.usesValueVariable;
    for r = 1:numel(info.references)
        ref = info.references(r);
        entry.refs(end+1) = localBuildRef_(ref, allParams, dispatchParams, entry.dispatchIndex);
        if ~isempty(ref.param) && ref.param == p
            entry.qualifiedSelfRef = true;
        end
    end
catch ME
    entry.resolveError = ME.message;
end
end


function refs = localEmptyRefs_()
refs = struct('token', {}, 'kind', {}, 'targetFullName', {}, 'param', {}, ...
    'dispatchIndex', {}, 'variesAcrossTrials', {}, 'isReadAccess', {}, ...
    'dispatchedAfter', {}, 'ambiguous', {});
end


function out = localBuildRef_(ref, allParams, dispatchParams, sourceDispatchIdx)
q = ref.param;
out = struct('token', ref.token, 'kind', ref.kind, ...
    'targetFullName', '', 'param', q, 'dispatchIndex', NaN, ...
    'variesAcrossTrials', false, 'isReadAccess', false, ...
    'dispatchedAfter', false, 'ambiguous', false);
if isempty(q)
    return
end

out.targetFullName = q.FullName;
out.isReadAccess = strcmp(q.Access, 'Read');
out.variesAcrossTrials = numel(q.Values) > 1 || q.isRandom;

dIdx = find(dispatchParams == q, 1);
if ~isempty(dIdx)
    out.dispatchIndex = dIdx;
    out.dispatchedAfter = ~isnan(sourceDispatchIdx) && dIdx > sourceDispatchIdx;
end

% A qualified reference is ambiguous when several parameters share the same
% Module.Param name pair; the runtime silently uses the first match.
if ismember(ref.kind, {'qualified', 'crossProp'})
    matchCount = 0;
    for k = 1:numel(allParams)
        if strcmp(allParams(k).Module.Name, ref.moduleName) && strcmp(allParams(k).Name, ref.paramName)
            matchCount = matchCount + 1;
        end
    end
    out.ambiguous = matchCount > 1;
end
end


function v = localDesignValue_(q)
% Placeholder value for reference resolution: first design-time level.
% Never reads q.Value (which can trigger a live hardware read).
if ~isempty(q.Values)
    v = q.Values{1};
else
    v = NaN;
end
end


function analysis = localFindCycles_(analysis)
n = numel(analysis);
if n < 2 && ~(n == 1 && analysis(1).qualifiedSelfRef)
    return
end

% Adjacency: entry i references entry j's parameter
adj = false(n);
for i = 1:n
    for r = 1:numel(analysis(i).refs)
        q = analysis(i).refs(r).param;
        if isempty(q)
            continue
        end
        for j = 1:n
            if analysis(j).param == q
                adj(i, j) = true;
            end
        end
    end
end

% Transitive closure (n is small)
reach = adj;
for k = 1:n
    reach = reach | (reach(:, k) & reach(k, :));
end

for i = 1:n
    partners = {};
    for j = 1:n
        if i ~= j && reach(i, j) && reach(j, i)
            partners{end+1} = analysis(j).fullName;
        end
    end
    analysis(i).cycleWith = partners;
end
end
