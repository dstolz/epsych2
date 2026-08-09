function report = sweepExpressions(obj, options)
% report = sweepExpressions(obj)
% report = sweepExpressions(obj, Inputs=inputsCell, DiscoverOnly=tf)
%
% Exhaustively evaluate every calculated parameter Expression over the full
% cross-product of its input values, using the exact runtime evaluator core
% (hw.Parameter.resolveExpressionContext / evalExpressionInContext) and
% set.Value clamping. Nothing is written to any parameter or to hardware.
%
% Input variables are every non-calculated parameter referenced by any live
% expression (plus, per calculated parameter that reads the `Value` variable,
% a pseudo-input for its incoming value). Calculated parameters referenced by
% other calculated parameters are NOT inputs: they are evaluated first and
% their clamped result feeds the downstream expression (dependency order).
%
% Parameters:
%   Inputs - N x 2 cell {identifier, numericVector} overriding the default
%       (design-time) values of any input. Identifiers are 'Module.Param'
%       (hw.Parameter FullName), or 'Module.Param:Value' for a calculated
%       parameter's incoming-Value pseudo-input. Unrecognized identifiers are
%       reported as issues and ignored.
%   DiscoverOnly - When true, return the discovered inputs/calcs (with
%       default values) without running the sweep. Default false.
%   MaxCombinations - Abort (with an issue) when the cross-product exceeds
%       this count. Default 10000.
%
% Returns:
%   report - struct with fields:
%       parameters - analyzeExpressions() output
%       inputs  - struct array: identifier, label, param (hw.Parameter or []),
%                 calcParam ([] except for :Value pseudo-inputs),
%                 defaultValues, values (vector used), source ('design'|'user'),
%                 note (char)
%       calcs   - struct array: param, fullName, expressionText, order
%                 (evaluation position, dependency-sorted)
%       results - struct: nCombos, inputValues (nCombos x nInputs),
%                 computed / final (nCombos x nCalcs, NaN on error or
%                 non-scalar), clamped (logical nCombos x nCalcs),
%                 notes (nCombos x nCalcs cellstr)
%       issues  - struct array {field, message, severity} (validate() shape)
%       meta    - nCombos, aborted, assumptions

arguments
    obj (1,1) epsych.Protocol
    options.Inputs cell = cell(0, 2)
    options.DiscoverOnly (1,1) logical = false
    options.MaxCombinations (1,1) double {mustBeInteger, mustBePositive} = 10000
end

analysis = obj.analyzeExpressions();

report = struct( ...
    'parameters', analysis, ...
    'inputs', localEmptyInputs_(), ...
    'calcs', struct('param', {}, 'fullName', {}, 'expressionText', {}, 'order', {}), ...
    'results', struct('nCombos', 0, 'inputValues', [], 'computed', [], ...
        'final', [], 'clamped', logical([]), 'notes', {{}}), ...
    'issues', obj.expressionIssues_(analysis), ...
    'meta', struct('nCombos', 0, 'aborted', false, 'assumptions', {localAssumptions_()}));

if isempty(analysis)
    return
end

% Full parameter set (runtime resolution scope) and design-value store
allParams = hw.Parameter.empty(1, 0);
for ifaceIdx = 1:numel(obj.Interfaces)
    modules = obj.Interfaces(ifaceIdx).Module;
    for modIdx = 1:numel(modules)
        if ~isempty(modules(modIdx).Parameters)
            allParams = [allParams, modules(modIdx).Parameters];
        end
    end
end

designVals = cell(1, numel(allParams));
for k = 1:numel(allParams)
    designVals{k} = localDesignValue_(allParams(k));
end

% Live calculated parameters (expressions that actually evaluate at runtime)
liveMask = arrayfun(@(a) ~a.multiLevelDormant && ~a.onReadParam, analysis);
liveCalcs = analysis(liveMask);
calcParams = hw.Parameter.empty(1, 0);
for k = 1:numel(liveCalcs)
    calcParams(end+1) = liveCalcs(k).param;
end

% ---- Discover input variables ------------------------------------------
inputs = localEmptyInputs_();
for k = 1:numel(liveCalcs)
    a = liveCalcs(k);
    for r = 1:numel(a.refs)
        ref = a.refs(r);
        q = ref.param;
        if isempty(q) || any(calcParams == q)
            continue  % unresolved, or chained calc (computed, not an input)
        end
        % Property references to static metadata are not inputs
        if ismember(ref.kind, {'sibProp', 'crossProp'}) && ~strcmp(ref.propName, 'Value')
            continue
        end
        if ~ismember(q.Type, {'Float', 'Integer', 'Boolean'})
            continue
        end
        if any(arrayfun(@(s) ~isempty(s.param) && s.param == q, inputs))
            continue
        end
        entry = localInputEntry_(q.FullName, q.FullName, q, [], localNumericValues_(q));
        if strcmp(q.Access, 'Read')
            entry.note = 'read from hardware at runtime';
        elseif numel(q.Values) > 1
            entry.note = 'varies per trial';
        end
        inputs(end+1) = entry;
    end

    if a.usesValueVariable
        incoming = localNumericValues_(a.param);
        if isempty(incoming)
            incoming = NaN;
        end
        entry = localInputEntry_( ...
            sprintf('%s:Value', a.param.FullName), ...
            sprintf('%s (incoming Value)', a.param.FullName), ...
            [], a.param, incoming);
        entry.note = 'value assigned to the parameter before its expression runs';
        inputs(end+1) = entry;
    end
end

% ---- Apply user overrides ----------------------------------------------
for k = 1:size(options.Inputs, 1)
    ident = char(string(options.Inputs{k, 1}));
    vals = options.Inputs{k, 2};
    idx = find(strcmp({inputs.identifier}, ident), 1);
    if isempty(idx)
        report.issues(end+1) = struct('field', ident, ...
            'message', 'Sweep input does not match any calculation variable; ignored', ...
            'severity', 1);
        continue
    end
    if ~(isnumeric(vals) || islogical(vals)) || isempty(vals)
        report.issues(end+1) = struct('field', ident, ...
            'message', 'Sweep input values must be a nonempty numeric vector; using design values', ...
            'severity', 1);
        continue
    end
    inputs(idx).values = double(vals(:)).';
    inputs(idx).source = 'user';
end

% Inputs with no usable default and no override cannot be swept numerically
for k = 1:numel(inputs)
    if isempty(inputs(k).values)
        inputs(k).values = NaN;
        report.issues(end+1) = struct('field', inputs(k).identifier, ...
            'message', 'No design value available for sweep input; using NaN', ...
            'severity', 1);
    end
end

% ---- Dependency-order the calculations ---------------------------------
n = numel(liveCalcs);
depends = false(n);
for i = 1:n
    for r = 1:numel(liveCalcs(i).refs)
        q = liveCalcs(i).refs(r).param;
        if isempty(q)
            continue
        end
        j = find(calcParams == q, 1);
        if ~isempty(j) && j ~= i
            depends(i, j) = true;  % calc i needs calc j first
        end
    end
end
order = localTopoOrder_(depends);

report.inputs = inputs;
for k = 1:n
    report.calcs(k) = struct('param', liveCalcs(order(k)).param, ...
        'fullName', liveCalcs(order(k)).fullName, ...
        'expressionText', liveCalcs(order(k)).expressionText, ...
        'order', k);
end

if options.DiscoverOnly
    return
end

% ---- Cross-product sweep ------------------------------------------------
lens = arrayfun(@(s) numel(s.values), inputs);
if isempty(lens)
    nCombos = 1;
else
    nCombos = prod(lens);
end
report.meta.nCombos = nCombos;

if nCombos > options.MaxCombinations
    report.meta.aborted = true;
    report.issues(end+1) = struct('field', 'Sweep', ...
        'message', sprintf('%d combinations exceed the limit of %d; narrow the input ranges', ...
        nCombos, options.MaxCombinations), 'severity', 2);
    return
end

nInputs = numel(inputs);
inputValues = zeros(nCombos, nInputs);
computed = nan(nCombos, n);
finalVals = nan(nCombos, n);
clamped = false(nCombos, n);
notes = repmat({''}, nCombos, n);

simVals = designVals;

    function v = simLookup_(q)
        kq = find(allParams == q, 1);
        if isempty(kq)
            v = NaN;
        else
            v = simVals{kq};
        end
    end

for c = 1:nCombos
    % Decode combination index into one scalar per input
    remIdx = c - 1;
    for i = 1:nInputs
        vi = mod(remIdx, lens(i)) + 1;
        remIdx = floor(remIdx / lens(i));
        inputValues(c, i) = inputs(i).values(vi);
        if ~isempty(inputs(i).param)
            kq = find(allParams == inputs(i).param, 1);
            if ~isempty(kq)
                simVals{kq} = inputValues(c, i);
            end
        end
    end

    for k = 1:n
        a = liveCalcs(order(k));
        p = a.param;

        % Incoming `Value`: pseudo-input when defined, else first design level
        vin = NaN;
        pv = find(arrayfun(@(s) ~isempty(s.calcParam) && s.calcParam == p, inputs), 1);
        if ~isempty(pv)
            vin = inputValues(c, pv);
        elseif ~isempty(p.Values) && (isnumeric(p.Values{1}) || islogical(p.Values{1}))
            vin = double(p.Values{1});
        end

        noteParts = {};
        try
            [rewritten, context] = hw.Parameter.resolveExpressionContext( ...
                a.expressionText, vin, p, ...
                @() p.Module.Parameters, ...
                @() allParams, ...
                @(q) simLookup_(q));
            v = hw.Parameter.evalExpressionInContext(rewritten, context, p.Name);
            if isnumeric(v) && isscalar(v)
                computed(c, k) = double(v);
            elseif islogical(v) && isscalar(v)
                computed(c, k) = double(v);
            else
                noteParts{end+1} = sprintf('non-scalar result (%s, %d elements)', class(v), numel(v));
                v = NaN;
            end
        catch ME
            noteParts{end+1} = ME.message;
            v = NaN;
        end

        [vf, wasClamped] = p.clampValue(v);
        clamped(c, k) = wasClamped;
        if wasClamped
            noteParts{end+1} = sprintf('clamped from %g to %g', v, vf);
        end
        if isnumeric(vf) && isscalar(vf)
            finalVals(c, k) = double(vf);
        end
        notes{c, k} = strjoin(noteParts, '; ');

        % Chained feed: downstream expressions see the clamped result
        kq = find(allParams == p, 1);
        if ~isempty(kq)
            simVals{kq} = finalVals(c, k);
        end
    end
end

report.results = struct('nCombos', nCombos, 'inputValues', inputValues, ...
    'computed', computed, 'final', finalVals, 'clamped', clamped, 'notes', {notes});

% ---- Summarize sweep outcomes as issues --------------------------------
for k = 1:n
    fullName = report.calcs(k).fullName;
    errMask = isnan(computed(:, k));
    if any(errMask)
        firstErr = notes{find(errMask, 1), k};
        report.issues(end+1) = struct('field', fullName, ...
            'message', sprintf('Expression failed in %d of %d combination(s): %s', ...
            nnz(errMask), nCombos, firstErr), 'severity', 2);
    end
    if any(clamped(:, k))
        report.issues(end+1) = struct('field', fullName, ...
            'message', sprintf('Result silently clamped to Min/Max in %d of %d combination(s)', ...
            nnz(clamped(:, k)), nCombos), 'severity', 1);
    end
end
end


function inputs = localEmptyInputs_()
inputs = struct('identifier', {}, 'label', {}, 'param', {}, 'calcParam', {}, ...
    'defaultValues', {}, 'values', {}, 'source', {}, 'note', {});
end


function entry = localInputEntry_(identifier, label, param, calcParam, values)
entry = struct('identifier', identifier, 'label', label, 'param', param, ...
    'calcParam', calcParam, 'defaultValues', values, 'values', values, ...
    'source', 'design', 'note', '');
end


function v = localDesignValue_(q)
% Design-time stand-in value; never reads .Value through connected hardware.
v = NaN;
if strcmp(q.Access, 'Read')
    safeToRead = isa(q.Parent, 'hw.Software') || ...
        (isprop(q.Parent, 'IsConnected') && ~q.Parent.IsConnected);
    if safeToRead
        try
            raw = q.Value;
            if ~isempty(raw)
                v = raw;
            end
        catch
        end
    end
    if isnumeric(v) && isscalar(v) && isnan(v) && ~isempty(q.Values)
        v = q.Values{1};
    end
    return
end
if ~isempty(q.Values)
    v = q.Values{1};
end
end


function vals = localNumericValues_(q)
% Flatten a parameter's design-time Values into a numeric row vector.
vals = [];
for k = 1:numel(q.Values)
    v = q.Values{k};
    if isnumeric(v) || islogical(v)
        vals = [vals, double(v(:)).'];
    end
end
end


function order = localTopoOrder_(depends)
% Kahn's algorithm; any cycle members are appended in original order.
n = size(depends, 1);
order = [];
placed = false(1, n);
progress = true;
while progress
    progress = false;
    for i = 1:n
        if ~placed(i) && ~any(depends(i, ~placed))
            order(end+1) = i;
            placed(i) = true;
            progress = true;
        end
    end
end
order = [order, find(~placed)];
end


function assumptions = localAssumptions_()
assumptions = { ...
    'Every combination of the input values is evaluated (exhaustive cross-product)'; ...
    'Chained calculations are evaluated in dependency order; at runtime dispatch order may lag one trial (see warnings)'; ...
    'PreUpdateFcn and EvaluatorFcn callbacks are not executed'; ...
    'Randomization (isRandom) is not applied'; ...
    'Read-access inputs default to design-time values; at runtime they reflect live hardware'};
end
