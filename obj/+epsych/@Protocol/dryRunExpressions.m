function report = dryRunExpressions(obj, options)
% report = dryRunExpressions(obj)
% report = dryRunExpressions(obj, NumTrials=n)
%
% Simulate how calculated parameter Expressions will evaluate at runtime,
% without touching hardware or mutating any parameter. Mirrors the per-trial
% dispatch performed by epsych.Runtime.dispatchNextTrial: compiled writable
% UpdateEveryTrial parameters are "assigned" their trial-table values in
% dispatch order against a simulated value store, expressions are evaluated
% with the exact runtime evaluator core (hw.Parameter.resolveExpressionContext
% / evalExpressionInContext), and results are clamped like set.Value would.
%
% Parameters:
%   NumTrials - Number of trials to simulate (default 20, capped at 200).
%       Trial-table rows are cycled in order when NumTrials exceeds the
%       table size, matching how the runtime keeps drawing trials past one
%       pass through the table. The actual runtime order depends on the
%       trial selector; findings that depend on ordering are therefore
%       phrased order-independently.
%
% Returns:
%   report - struct with fields:
%       parameters - output of analyzeExpressions() (static per-parameter analysis)
%       trials     - struct array, one entry per (trial, expression parameter):
%                    trial, row (trial-table row used), parameter (fullName),
%                    expression, inputs (char), computed (post-eval,
%                    pre-clamp), clampedTo (NaN when not clamped), final,
%                    tableValue, designValue, status
%                    ('ok'|'clamped'|'stale'|'dormant'|'error'), notes (char)
%       issues     - struct array {field, message, severity} (validate() shape)
%       meta       - nTrialsSimulated, nTrialsTotal, compiledAt, assumptions
%
% The simulation executes no PreUpdateFcn/EvaluatorFcn callbacks and applies
% no randomization; affected rows are annotated rather than silently wrong.

arguments
    obj (1,1) epsych.Protocol
    options.NumTrials (1,1) double {mustBeInteger, mustBePositive} = 20
end

analysis = obj.analyzeExpressions();

report = struct( ...
    'parameters', analysis, ...
    'trials', localEmptyTrialRecords_(), ...
    'issues', struct('field', {}, 'message', {}, 'severity', {}), ...
    'meta', struct('nTrialsSimulated', 0, 'nTrialsTotal', 0, ...
        'compiledAt', NaT, 'assumptions', {localAssumptions_()}));

if obj.needsCompile
    try
        obj.compile();
    catch ME
        vprintf(0, 1, ME);
    end
end

report.issues = obj.expressionIssues_(analysis);

if isempty(obj.COMPILED.parameters) || obj.COMPILED.ntrials == 0
    vreport = obj.validate();
    for k = 1:numel(vreport)
        if vreport(k).severity == 2
            report.issues(end+1) = vreport(k);
        end
    end
    return
end

% Simulated value store over the full runtime resolution scope (all
% parameters of all modules, matching the runtime evaluator).
allParams = hw.Parameter.empty(1, 0);
for ifaceIdx = 1:numel(obj.Interfaces)
    modules = obj.Interfaces(ifaceIdx).Module;
    for modIdx = 1:numel(modules)
        if ~isempty(modules(modIdx).Parameters)
            allParams = [allParams, modules(modIdx).Parameters];
        end
    end
end

simVals = cell(1, numel(allParams));
estimated = false(1, numel(allParams));
for k = 1:numel(allParams)
    [simVals{k}, estimated(k)] = localInitialValue_(allParams(k));
end

P = obj.COMPILED.parameters;
dispatchMask = ~strcmp({P.Access}, 'Read') & [P.UpdateEveryTrial];
Pd = P(dispatchMask);

nTrials = min(options.NumTrials, 200);
records = localEmptyTrialRecords_();

for t = 1:nTrials
    rowIdx = mod(t - 1, obj.COMPILED.ntrials) + 1;
    row = obj.COMPILED.trials(rowIdx, dispatchMask);
    for j = 1:numel(Pd)
        p = Pd(j);
        v = row{j};
        exprText = strtrim(char(p.Expression));
        isExpr = ~isempty(exprText);
        notes = {};
        status = 'ok';
        inputs = '';
        computed = v;

        selectsIndex = hw.Parameter.expressionSelectsIndex(p.Type);

        if isExpr && numel(p.Values) > 1 && ~selectsIndex
            status = 'dormant';
            notes{end+1} = 'Expression skipped at runtime (multi-level parameter); trial-table value used';
        elseif isExpr
            aIdx = localFindAnalysis_(analysis, p);
            try
                [rewritten, context, info] = hw.Parameter.resolveExpressionContext( ...
                    exprText, v, p, ...
                    @() p.Module.Parameters, ...
                    @() allParams, ...
                    @(q) simLookup_(q));
                inputs = localFormatInputs_(info.references);
                if ~isempty(info.unresolvedQualified)
                    notes{end+1} = sprintf('Unresolved reference(s): %s', strjoin(info.unresolvedQualified, ', '));
                end
                v = hw.Parameter.evalExpressionInContext(rewritten, context, p.Name);
                if selectsIndex
                    [v, selectedIndex] = hw.Parameter.selectValueByIndex(v, p.Values, p.Name);
                    notes{end+1} = sprintf('Index selects item %d of %d', selectedIndex, numel(p.Values));
                end
                computed = v;
            catch ME
                status = 'error';
                notes{end+1} = sprintf('%s (at runtime this aborts trial dispatch)', ME.message);
            end

            if ~isempty(aIdx)
                for r = 1:numel(analysis(aIdx).refs)
                    ref = analysis(aIdx).refs(r);
                    if ref.dispatchedAfter && ref.variesAcrossTrials
                        if ~strcmp(status, 'error')
                            status = 'stale';
                        end
                        notes{end+1} = sprintf('Uses the previous trial''s value of %s (dispatched later in the trial sequence)', ref.targetFullName);
                    end
                    if ~isempty(ref.param)
                        kk = find(allParams == ref.param, 1);
                        if ~isempty(kk) && estimated(kk)
                            notes{end+1} = sprintf('%s is read from hardware at runtime; design-time value used here', ref.targetFullName);
                        end
                    end
                end
            end
        end

        if p.isRandom
            notes{end+1} = 'Randomization not simulated; compiled value used';
        end
        if isa(p.PreUpdateFcn, 'function_handle') && p.PreUpdateFcnEnabled
            notes{end+1} = 'PreUpdateFcn not executed in simulation';
        end
        if isa(p.EvaluatorFcn, 'function_handle') && p.EvaluatorFcnEnabled
            notes{end+1} = 'EvaluatorFcn not executed in simulation; result may differ at runtime';
        end

        [vClamped, wasClamped] = p.clampValue(v);
        clampedTo = NaN;
        if wasClamped
            clampedTo = vClamped;
            if strcmp(status, 'ok')
                status = 'clamped';
            else
                notes{end+1} = sprintf('Result clamped from %s to %s by Min/Max bounds', ...
                    localFormatValue_(v), localFormatValue_(vClamped));
            end
        end
        v = vClamped;

        if isExpr
            designValue = NaN;
            if isscalar(p.Values)
                designValue = p.Values{1};
            end
            rec = struct( ...
                'trial', t, ...
                'row', rowIdx, ...
                'parameter', p.FullName, ...
                'expression', exprText, ...
                'inputs', inputs, ...
                'computed', {{computed}}, ...
                'clampedTo', clampedTo, ...
                'final', {{v}}, ...
                'tableValue', {{row{j}}}, ...
                'designValue', {{designValue}}, ...
                'status', status, ...
                'notes', strjoin(notes, '; '));
            records(end+1) = rec;
        end

        kk = find(allParams == p, 1);
        if ~isempty(kk)
            simVals{kk} = v;
            estimated(kk) = false;
        end
    end
end

report.trials = records;
report.issues = [report.issues, localRunIssues_(records)];
report.meta.nTrialsSimulated = nTrials;
report.meta.nTrialsTotal = obj.COMPILED.ntrials;
report.meta.compiledAt = obj.COMPILED.compiledAt;

    function v = simLookup_(q)
        kq = find(allParams == q, 1);
        if isempty(kq)
            v = NaN;
        else
            v = simVals{kq};
        end
    end
end


function records = localEmptyTrialRecords_()
records = struct('trial', {}, 'row', {}, 'parameter', {}, 'expression', {}, ...
    'inputs', {}, 'computed', {}, 'clampedTo', {}, 'final', {}, ...
    'tableValue', {}, 'designValue', {}, 'status', {}, 'notes', {});
end


function assumptions = localAssumptions_()
assumptions = { ...
    'Trials simulated by cycling trial-table rows in order; the runtime order depends on the trial-selection function'; ...
    'PreUpdateFcn and EvaluatorFcn callbacks are not executed'; ...
    'Randomization (isRandom) is not applied'; ...
    'Read-access parameters use design-time values; at runtime they reflect live hardware'};
end


function [v, isEstimated] = localInitialValue_(q)
% Initial simulated value before trial 1. Read-access parameters reflect
% live hardware at runtime, so their design-time stand-in is flagged as an
% estimate. Never reads .Value through a connected hardware interface.
isEstimated = false;
if strcmp(q.Access, 'Read')
    isEstimated = true;
    v = NaN;
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
else
    v = NaN;
end
end


function idx = localFindAnalysis_(analysis, p)
idx = [];
for k = 1:numel(analysis)
    if analysis(k).param == p
        idx = k;
        return
    end
end
end


function txt = localFormatInputs_(references)
parts = {};
for r = 1:numel(references)
    ref = references(r);
    parts{end+1} = sprintf('%s=%s', ref.token, localFormatValue_(ref.value{1}));
end
txt = strjoin(parts, ', ');
end


function txt = localFormatValue_(v)
if isnumeric(v) || islogical(v)
    if isscalar(v)
        txt = num2str(double(v), '%g');
    else
        txt = mat2str(double(v), 4);
    end
elseif ischar(v) || isstring(v)
    txt = char(string(v));
elseif iscell(v)
    txt = sprintf('{%d values}', numel(v));
else
    txt = class(v);
end
end


function issues = localRunIssues_(records)
% Summarize per-trial simulation outcomes into issues (deduplicated per parameter).
issues = struct('field', {}, 'message', {}, 'severity', {});
if isempty(records)
    return
end

paramNames = unique({records.parameter}, 'stable');
for k = 1:numel(paramNames)
    sel = records(strcmp({records.parameter}, paramNames{k}));

    errSel = sel(strcmp({sel.status}, 'error'));
    if ~isempty(errSel)
        issues(end+1) = localIssue_(paramNames{k}, ...
            sprintf('Expression failed in %d of %d simulated trial(s): %s', ...
            numel(errSel), numel(sel), errSel(1).notes), 2);
    end

    clampedCount = nnz(~isnan([sel.clampedTo]));
    if clampedCount > 0
        issues(end+1) = localIssue_(paramNames{k}, ...
            sprintf('Computed value was silently clamped to Min/Max bounds in %d of %d simulated trial(s)', ...
            clampedCount, numel(sel)), 1);
    end
end
end


function issue = localIssue_(field, message, severity)
issue = struct('field', field, 'message', message, 'severity', severity);
end
