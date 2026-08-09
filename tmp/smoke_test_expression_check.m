function smoke_test_expression_check()
% smoke_test_expression_check()
% Exercise the shared expression-evaluation core (hw.Parameter
% resolveExpressionContext / evalExpressionInContext), the runtime set.Value
% pipeline regression after the refactor, the epsych.Protocol dry-run engine
% (analyzeExpressions / dryRunExpressions) against the checked-in example
% protocol, and the new expression checks in Protocol.validate().
%
%   matlab -batch "run('tmp/smoke_test_expression_check.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

% ===== A. Resolver / eval core units =====================================
sw = hw.Software;
pa = sw.add_parameter('AttenA', 10); pa.Value = 10;
pb = sw.add_parameter('GainB', 3, Min=-inf, Max=100); pb.Value = 3;
moduleName = pa.Module.Name;

try
    % Sibling value reference
    [rw, ctx] = hw.Parameter.resolveExpressionContext('GainB + 2', 5, pa, ...
        @() pa.Module.Parameters, @() [pa pb], @(p) p.Value);
    res = hw.Parameter.evalExpressionInContext(rw, ctx, pa.Name);
    assert(isequal(res, 5), 'sibling ref: expected 5, got %s', mat2str(res));

    % Qualified Module.Param reference
    [rw, ctx] = hw.Parameter.resolveExpressionContext( ...
        sprintf('%s.GainB * 2', moduleName), 0, pa, ...
        @() pa.Module.Parameters, @() [pa pb], @(p) p.Value);
    res = hw.Parameter.evalExpressionInContext(rw, ctx, pa.Name);
    assert(isequal(res, 6), 'qualified ref: expected 6, got %s', mat2str(res));

    % Property references (sibling and cross-module)
    [rw, ctx] = hw.Parameter.resolveExpressionContext('GainB.Max + 1', 0, pa, ...
        @() pa.Module.Parameters, @() [pa pb], @(p) p.Value);
    res = hw.Parameter.evalExpressionInContext(rw, ctx, pa.Name);
    assert(isequal(res, 101), 'sibling prop ref: expected 101, got %s', mat2str(res));

    [rw, ctx] = hw.Parameter.resolveExpressionContext( ...
        sprintf('%s.GainB.Max - 1', moduleName), 0, pa, ...
        @() pa.Module.Parameters, @() [pa pb], @(p) p.Value);
    res = hw.Parameter.evalExpressionInContext(rw, ctx, pa.Name);
    assert(isequal(res, 99), 'cross prop ref: expected 99, got %s', mat2str(res));

    % Incoming value passthrough via `Value`
    [rw, ctx] = hw.Parameter.resolveExpressionContext('Value * 3', 7, pa, ...
        @() pa.Module.Parameters, @() [pa pb], @(p) p.Value);
    res = hw.Parameter.evalExpressionInContext(rw, ctx, pa.Name);
    assert(isequal(res, 21), 'Value passthrough: expected 21, got %s', mat2str(res));

    % valueFcn override changes the result (the design-time hook)
    [rw, ctx] = hw.Parameter.resolveExpressionContext('GainB + 2', 0, pa, ...
        @() pa.Module.Parameters, @() [pa pb], @(p) 99);
    res = hw.Parameter.evalExpressionInContext(rw, ctx, pa.Name);
    assert(isequal(res, 101), 'valueFcn override: expected 101, got %s', mat2str(res));

    % Reference diagnostics (info output)
    [~, ~, info] = hw.Parameter.resolveExpressionContext( ...
        sprintf('GainB + %s.AttenA + Nope.Nada', moduleName), 0, pa, ...
        @() pa.Module.Parameters, @() [pa pb], @(p) p.Value);
    assert(any(strcmp({info.references.kind}, 'sibling')), 'info: missing sibling ref');
    assert(any(strcmp({info.references.kind}, 'qualified')), 'info: missing qualified ref');
    assert(any(strcmp(info.unresolvedQualified, 'Nope.Nada')), 'info: missing unresolved token');

    fprintf('PASS: A. resolver/eval core units\n');
catch ME
    failures{end+1} = sprintf('A. resolver/eval core: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% ';' must raise ExpressionMultiStatement
try
    hw.Parameter.resolveExpressionContext('GainB + 2;', 0, pa, ...
        @() pa.Module.Parameters, @() [pa pb], @(p) p.Value);
    failures{end+1} = 'A2. semicolon accepted (should error)';
    fprintf('FAIL: A2. semicolon accepted\n');
catch ME
    if strcmp(ME.identifier, 'hw:Parameter:ExpressionMultiStatement')
        fprintf('PASS: A2. semicolon rejected with correct identifier\n');
    else
        failures{end+1} = sprintf('A2. wrong error id: %s', ME.identifier);
        fprintf('FAIL: A2. wrong error id %s\n', ME.identifier);
    end
end

% Unresolved token left verbatim -> ExpressionError from eval
try
    [rw, ctx] = hw.Parameter.resolveExpressionContext('Nope.Nada + 1', 0, pa, ...
        @() pa.Module.Parameters, @() [pa pb], @(p) p.Value);
    hw.Parameter.evalExpressionInContext(rw, ctx, pa.Name);
    failures{end+1} = 'A3. unresolved token evaluated (should error)';
    fprintf('FAIL: A3. unresolved token evaluated\n');
catch ME
    if strcmp(ME.identifier, 'hw:Parameter:ExpressionError')
        fprintf('PASS: A3. unresolved token raises ExpressionError\n');
    else
        failures{end+1} = sprintf('A3. wrong error id: %s', ME.identifier);
        fprintf('FAIL: A3. wrong error id %s\n', ME.identifier);
    end
end

% ===== B. Runtime set.Value pipeline regression ==========================
try
    pc = sw.add_parameter('CalcC', 0);
    pc.Expression = "GainB * 2";
    pc.Value = 0;
    assert(isequal(pc.Value, 6), 'pipeline sibling: expected 6, got %s', mat2str(pc.Value));

    pd = sw.add_parameter('CalcD', 0, Min=0, Max=5);
    pd.Expression = "GainB * 4";
    pd.Value = 0;
    assert(isequal(pd.Value, 5), 'pipeline clamp: expected 5 (12 clamped), got %s', mat2str(pd.Value));

    pe = sw.add_parameter('MultiE', [1 2 3]);
    pe.Expression = "GainB * 2";
    pe.Value = 2;
    assert(isequal(pe.Value, 2), 'multi-level guard: expected 2 (expression skipped), got %s', mat2str(pe.Value));

    [cv, wasClamped] = pd.clampValue(12);
    assert(isequal(cv, 5) && wasClamped, 'clampValue preview: expected 5/true');
    [cv, wasClamped] = pd.clampValue(3);
    assert(isequal(cv, 3) && ~wasClamped, 'clampValue preview: expected 3/false');

    fprintf('PASS: B. runtime set.Value pipeline unchanged after refactor\n');
catch ME
    failures{end+1} = sprintf('B. runtime pipeline: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. Dry run against the example protocol ===========================
protocolFile = fullfile(here, 'TEST_NEW_PROTOCOL2.eprot');
if exist(protocolFile, 'file')
    try
        P = epsych.Protocol.load(protocolFile);

        allP = hw.Parameter.empty(1, 0);
        for k = 1:numel(P.Interfaces)
            for m = 1:numel(P.Interfaces(k).Module)
                allP = [allP, P.Interfaces(k).Module(m).Parameters];
            end
        end
        rwd = allP(strcmp({allP.Name}, 'RespWinDelay'));
        rwr = allP(strcmp({allP.Name}, 'RespWinDur'));
        snapshotValues = cellfun(@(n) allP(strcmp({allP.Name}, n)).Values, ...
            {'RespWinDelay', 'RespWinDur', 'StimDelay', 'StimDur', 'RespWinPreStim'}, ...
            'UniformOutput', false);

        report = P.dryRunExpressions(NumTrials = 10);

        assert(~isempty(report.trials), 'dry run produced no trial records');
        assert(report.meta.nTrialsSimulated == 10, ...
            'expected 10 simulated trials (cycling rows), got %d', report.meta.nTrialsSimulated);
        delayRecs = report.trials(endsWith({report.trials.parameter}, 'RespWinDelay'));
        durRecs = report.trials(endsWith({report.trials.parameter}, 'RespWinDur'));
        assert(numel(delayRecs) == 10 && numel(durRecs) == 10, ...
            'expected 10 records per expression parameter (got %d/%d)', numel(delayRecs), numel(durRecs));
        expectedRows = mod((1:10) - 1, report.meta.nTrialsTotal) + 1;
        assert(isequal([delayRecs.row], expectedRows), 'trial-table rows should cycle in order');
        assert(all(cellfun(@(v) isequal(v, 1200), [delayRecs.final])), ...
            'RespWinDelay simulated values differ from expected 1200');
        assert(all(cellfun(@(v) isequal(v, 1300), [durRecs.final])), ...
            'RespWinDur simulated values differ from expected 1300');
        assert(all(strcmp({delayRecs.status}, 'ok')) && all(strcmp({durRecs.status}, 'ok')), ...
            'expected all-ok status on the example protocol');

        aDelay = report.parameters(endsWith({report.parameters.fullName}, 'RespWinDelay'));
        refTokens = {aDelay.refs.token};
        assert(all(ismember({'StimDelay', 'StimDur', 'Params.RespWinPreStim'}, refTokens)), ...
            'RespWinDelay references not fully resolved: %s', strjoin(refTokens, ','));
        laterRefs = aDelay.refs(ismember(refTokens, {'StimDelay', 'StimDur'}));
        assert(all([laterRefs.dispatchedAfter]), 'StimDelay/StimDur should be flagged dispatchedAfter');

        assert(~any([report.issues.severity] == 2), 'unexpected severity-2 issue on example protocol');

        % Protocol parameter state must be untouched by the dry run
        after = cellfun(@(n) allP(strcmp({allP.Name}, n)).Values, ...
            {'RespWinDelay', 'RespWinDur', 'StimDelay', 'StimDur', 'RespWinPreStim'}, ...
            'UniformOutput', false);
        assert(isequal(snapshotValues, after), 'dry run mutated parameter Values');
        assert(isequal(rwd.Value, 1200) && isequal(rwr.Value, 1300), 'dry run mutated parameter Value');

        fprintf('PASS: C. dry run on TEST_NEW_PROTOCOL2.eprot\n');
    catch ME
        failures{end+1} = sprintf('C. example protocol dry run: %s', ME.message);
        fprintf('FAIL: C. %s\n', ME.message);
    end
else
    fprintf('SKIP: C. example protocol not found (%s)\n', protocolFile);
end

% ===== C2. Stale-reference and clamp detection (synthetic) ===============
try
    P3 = epsych.Protocol;
    pCalc = P3.addParameter('Software', 'Calc', 0);
    pCalc.Expression = "Vary + 1";
    P3.addParameter('Software', 'Vary', [10 20]);
    pClamp = P3.addParameter('Software', 'Clamped', 0, Min=0, Max=5);
    pClamp.Expression = "Vary * 1";

    report = P3.dryRunExpressions(NumTrials = 4);

    staleIssues = report.issues(endsWith({report.issues.field}, '.Calc'));
    assert(any(contains({staleIssues.message}, 'previous trial')), ...
        'missing stale-reference warning for Calc');
    calcRecs = report.trials(endsWith({report.trials.parameter}, '.Calc'));
    assert(any(strcmp({calcRecs.status}, 'stale')), 'Calc records not flagged stale');

    clampRecs = report.trials(endsWith({report.trials.parameter}, '.Clamped'));
    assert(any(~isnan([clampRecs.clampedTo])), 'Clamped records show no clamping');
    clampIssues = report.issues(endsWith({report.issues.field}, '.Clamped'));
    assert(any(contains({clampIssues.message}, 'clamped')), 'missing clamp warning');

    fprintf('PASS: C2. stale-reference and clamp detection\n');
catch ME
    failures{end+1} = sprintf('C2. stale/clamp detection: %s', ME.message);
    fprintf('FAIL: C2. %s\n', ME.message);
end

% ===== E. Exhaustive sweep engine (sweepExpressions) =====================
if exist(protocolFile, 'file')
    try
        P4 = epsych.Protocol.load(protocolFile);

        % Defaults: one combination, both calcs at their design results
        R = P4.sweepExpressions();
        assert(R.results.nCombos == 1, 'default sweep should have 1 combination');
        assert(isequal(sort(R.results.final(1, :)), [1200 1300]), ...
            'default sweep finals wrong: %s', mat2str(R.results.final(1, :)));

        % Overrides: cross-product with clamp detection (Min=400)
        R2 = P4.sweepExpressions(Inputs = { ...
            'Behavior.StimDelay', [500 1000]; ...
            'Params.RespWinPreStim', [800 1700]});
        assert(R2.results.nCombos == 4, 'expected 4 combinations');
        ci = find(strcmp({R2.calcs.fullName}, 'TDT_RPcox.Behavior.RespWinDelay'), 1);
        finals = sort(R2.results.final(:, ci)).';
        assert(isequal(finals, [400 400 700 1200]), 'sweep finals wrong: %s', mat2str(finals));
        assert(nnz(R2.results.clamped(:, ci)) == 2, 'expected 2 clamp events');

        fprintf('PASS: E. exhaustive sweep on TEST_NEW_PROTOCOL2.eprot\n');
    catch ME
        failures{end+1} = sprintf('E. sweep engine: %s', ME.message);
        fprintf('FAIL: E. %s\n', ME.message);
    end
else
    fprintf('SKIP: E. example protocol not found\n');
end

% ===== E2. Chained sweep + combination cap (synthetic) ===================
try
    P5 = epsych.Protocol;
    P5.addParameter('Software', 'BaseX', 3);
    pA = P5.addParameter('Software', 'CalcA', 0);
    pA.Expression = "BaseX * 2";
    pB2 = P5.addParameter('Software', 'CalcB', 0);
    pB2.Expression = "CalcA + 1";

    spec5 = P5.sweepExpressions(DiscoverOnly = true);
    baseIdx = find(endsWith({spec5.inputs.identifier}, '.BaseX'), 1);
    assert(~isempty(baseIdx), 'BaseX should be a sweep input');
    baseIdent = spec5.inputs(baseIdx).identifier;
    assert(~any(contains({spec5.inputs.identifier}, 'CalcA')), 'chained calc must not be an input');

    R3 = P5.sweepExpressions(Inputs = {baseIdent, [1 2 5]});
    ai = find(contains({R3.calcs.fullName}, 'CalcA'), 1);
    bi = find(contains({R3.calcs.fullName}, 'CalcB'), 1);
    assert(ai < bi, 'CalcA must evaluate before CalcB');
    assert(R3.results.nCombos == 3, 'expected 3 combinations, got %d', R3.results.nCombos);
    assert(isequal(sort(R3.results.final(:, ai)).', [2 4 10]), 'CalcA sweep wrong');
    assert(isequal(sort(R3.results.final(:, bi)).', [3 5 11]), 'chained CalcB sweep wrong');

    R4 = P5.sweepExpressions(Inputs = {baseIdent, 1:20000});
    assert(R4.meta.aborted, 'sweep should abort above MaxCombinations');

    fprintf('PASS: E2. chained sweep and combination cap\n');
catch ME
    failures{end+1} = sprintf('E2. chained sweep: %s', ME.message);
    fprintf('FAIL: E2. %s\n', ME.message);
end

% ===== D. validate() expression checks ===================================
try
    P2 = epsych.Protocol;
    P2.addParameter('Software', 'SrcA', 5);
    pB = P2.addParameter('Software', 'DerivedB', 1);
    pB.Expression = "Value = SrcA * 2";

    rep = P2.validate();
    bIssues = rep(contains({rep.field}, '.DerivedB'));
    assert(any([bIssues.severity] == 2), 'assignment expression should be a severity-2 error');

    P2.compile();
    assert(P2.COMPILED.ntrials == 0, 'compile should refuse a protocol with a fatal expression error');

    % Bare self-reference is also fatal
    pB.Expression = "DerivedB + 1";
    rep = P2.validate();
    bIssues = rep(contains({rep.field}, '.DerivedB'));
    assert(any([bIssues.severity] == 2), 'bare self-reference should be a severity-2 error');

    % A valid expression passes and compiles
    pB.Expression = "SrcA * 2";
    rep = P2.validate();
    assert(isempty(rep) || ~any([rep.severity] == 2), 'valid expression should not block');
    P2.compile();
    assert(P2.COMPILED.ntrials > 0, 'compile should succeed with a valid expression');

    fprintf('PASS: D. validate() expression checks\n');
catch ME
    failures{end+1} = sprintf('D. validate checks: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end

% ===== Summary ===========================================================
if isempty(failures)
    fprintf('\nsmoke_test_expression_check: ALL SECTIONS PASS\n');
else
    fprintf('\nsmoke_test_expression_check: %d FAILURE(S)\n', numel(failures));
    error('smoke_test_expression_check failed:\n  %s', strjoin(failures, sprintf('\n  ')));
end
end
