function smoke_test_index_expressions()
% smoke_test_index_expressions()
% Exercise index-selecting Expressions on String and StimType parameters:
% the shared hw.Parameter core, runtime set.Value dispatch, compile-time
% cross-product handling, and the static analysis / dry-run reporting.
%
%   matlab -batch "run('tmp/smoke_test_index_expressions.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

% ===== A. expressionSelectsIndex classification =========================
try
    assert(hw.Parameter.expressionSelectsIndex('String'), 'String should select by index');
    assert(hw.Parameter.expressionSelectsIndex('StimType'), 'StimType should select by index');
    assert(~hw.Parameter.expressionSelectsIndex('Float'), 'Float should not select by index');
    assert(~hw.Parameter.expressionSelectsIndex('Integer'), 'Integer should not select by index');
    assert(~hw.Parameter.expressionSelectsIndex('Boolean'), 'Boolean should not select by index');
    assert(~hw.Parameter.expressionSelectsIndex('File'), 'File should not select by index');
    fprintf('PASS: A. expressionSelectsIndex classifies types\n');
catch ME
    failures{end+1} = sprintf('A. classification: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% ===== B. selectValueByIndex validation =================================
try
    items = {'low', 'mid', 'high'};

    [item, idx] = hw.Parameter.selectValueByIndex(2, items, 'Level');
    assert(strcmp(item, 'mid') && idx == 2, 'index 2 should select "mid"');
    assert(strcmp(hw.Parameter.selectValueByIndex(true, items, 'Level'), 'low'), ...
        'logical true should select item 1');

    localExpectError_(@() hw.Parameter.selectValueByIndex(1, {}, 'Level'), ...
        'hw:Parameter:IndexExpressionNoItems', 'empty item list');
    localExpectError_(@() hw.Parameter.selectValueByIndex([1 2], items, 'Level'), ...
        'hw:Parameter:IndexExpressionNotScalar', 'non-scalar result');
    localExpectError_(@() hw.Parameter.selectValueByIndex('two', items, 'Level'), ...
        'hw:Parameter:IndexExpressionNotScalar', 'char result');
    localExpectError_(@() hw.Parameter.selectValueByIndex(0, items, 'Level'), ...
        'hw:Parameter:IndexExpressionOutOfRange', 'zero index');
    localExpectError_(@() hw.Parameter.selectValueByIndex(4, items, 'Level'), ...
        'hw:Parameter:IndexExpressionOutOfRange', 'index past the end');

    % The fractional message must name the rounding functions.
    try
        hw.Parameter.selectValueByIndex(1.5, items, 'Level');
        error('smoke:NoError', 'fractional index should have raised');
    catch fracME
        assert(strcmp(fracME.identifier, 'hw:Parameter:IndexExpressionNotInteger'), ...
            'wrong identifier for fractional index: %s', fracME.identifier);
        assert(contains(fracME.message, 'round()') && contains(fracME.message, 'fix()'), ...
            'fractional index message should suggest round()/fix(): %s', fracME.message);
    end

    fprintf('PASS: B. selectValueByIndex validates scalar, integer, and range\n');
catch ME
    failures{end+1} = sprintf('B. selectValueByIndex: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. Runtime selection on a String parameter =======================
try
    P = epsych.Protocol;
    pSel = P.addParameter('Software', 'Sel', 2);
    pChoice = P.addParameter('Software', 'Choice', 'a', Type='String');
    pChoice.Values = {'a', 'b', 'c'};
    pChoice.Expression = "Sel";

    pSel.Value = 2;
    pChoice.Value = 'a';                 % incoming value is overridden by the index
    assert(strcmp(pChoice.Value, 'b'), 'expected item 2 ("b"), got "%s"', pChoice.Value);

    pSel.Value = 3;
    pChoice.Value = 'a';
    assert(strcmp(pChoice.Value, 'c'), 'expected item 3 ("c"), got "%s"', pChoice.Value);

    % A fractional source must be rounded by the expression, not silently coerced.
    pChoice.Expression = "Sel / 2";
    pSel.Value = 3;
    localExpectError_(@() localSet_(pChoice, 'a'), ...
        'hw:Parameter:IndexExpressionNotInteger', 'fractional runtime index');

    pChoice.Expression = "round(Sel / 2)";
    pChoice.Value = 'a';
    assert(strcmp(pChoice.Value, 'b'), 'round(3/2) should select item 2, got "%s"', pChoice.Value);

    pSel.Value = 9;
    localExpectError_(@() localSet_(pChoice, 'a'), ...
        'hw:Parameter:IndexExpressionOutOfRange', 'out-of-range runtime index');

    fprintf('PASS: C. String parameter selects its item by index at runtime\n');
catch ME
    failures{end+1} = sprintf('C. runtime String: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end

% ===== D. Multi-item expression stays live in analyzeExpressions ========
try
    P = epsych.Protocol;
    P.addParameter('Software', 'Sel', 1);
    pChoice = P.addParameter('Software', 'Choice', 'a', Type='String');
    pChoice.Values = {'a', 'b', 'c'};
    pChoice.Expression = "Sel";

    A = P.analyzeExpressions();
    aIdx = find(arrayfun(@(a) a.param == pChoice, A), 1);
    assert(~isempty(aIdx), 'Choice missing from the expression analysis');
    assert(~A(aIdx).multiLevelDormant, 'index-selecting expression must not be dormant');
    assert(A(aIdx).selectsIndex, 'selectsIndex should be true');
    assert(A(aIdx).itemCount == 3, 'itemCount should be 3, got %d', A(aIdx).itemCount);

    issues = P.validate();
    msgs = {issues.message};
    assert(any(contains(msgs, 'selects one of 3 item(s) by index')), ...
        'expected the index-contract note among issues: %s', strjoin(msgs, ' | '));
    assert(~any(contains(msgs, 'level generator')), ...
        'index-selecting parameter should not be reported as a level generator');

    % An empty item list is a hard error, not a note.
    pChoice.Values = {};
    emptyIssues = P.validate();
    hit = find(contains({emptyIssues.message}, 'no items in its Value list'), 1);
    assert(~isempty(hit), 'expected an issue for an empty item list');
    assert(emptyIssues(hit).severity == 2, 'empty item list should be severity 2');

    fprintf('PASS: D. analyzeExpressions reports index selection, not dormancy\n');
catch ME
    failures{end+1} = sprintf('D. analysis: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end

% ===== E. Item list does not multiply the trial cross product ===========
try
    P = epsych.Protocol;
    pSel = P.addParameter('Software', 'Sel', 1);
    pSel.Values = {1, 2};                % 2 real trial levels
    pChoice = P.addParameter('Software', 'Choice', 'a', Type='String');
    pChoice.Values = {'a', 'b', 'c'};    % 3 items, selected by expression
    pChoice.Expression = "Sel";
    P.compile();
    assert(P.COMPILED.ntrials == 2, ...
        'expected 2 trials (item list must not expand), got %d', P.COMPILED.ntrials);

    % Without an expression the same list is a normal 3-level parameter.
    pChoice.Expression = "";
    P.compile();
    assert(P.COMPILED.ntrials == 6, ...
        'expected 6 trials without an expression, got %d', P.COMPILED.ntrials);

    fprintf('PASS: E. compile treats the item list as a lookup, not as trial levels\n');
catch ME
    failures{end+1} = sprintf('E. compile: %s', ME.message);
    fprintf('FAIL: E. %s\n', ME.message);
end

% ===== F. dryRunExpressions resolves and annotates the index ============
try
    P = epsych.Protocol;
    pSel = P.addParameter('Software', 'Sel', 1);
    pSel.Values = {1, 3};
    pChoice = P.addParameter('Software', 'Choice', 'a', Type='String');
    pChoice.Values = {'a', 'b', 'c'};
    pChoice.Expression = "Sel";
    P.compile();

    report = P.dryRunExpressions(NumTrials=4);
    recs = report.trials(strcmp({report.trials.parameter}, pChoice.FullName));
    assert(~isempty(recs), 'no dry-run records for Choice');
    assert(~any(strcmp({recs.status}, 'dormant')), 'index expression reported dormant in the dry run');
    assert(all(contains({recs.notes}, 'Index selects item')), ...
        'dry run should note which item the index selects');
    finals = cellfun(@(f) char(string(f)), {recs.final}, 'UniformOutput', false);
    assert(all(ismember(finals, {'a', 'c'})), ...
        'dry run should resolve to items a/c, got %s', strjoin(unique(finals), ','));

    fprintf('PASS: F. dryRunExpressions resolves the selected item\n');
catch ME
    failures{end+1} = sprintf('F. dry run: %s', ME.message);
    fprintf('FAIL: F. %s\n', ME.message);
end

% ===== G. sweepExpressions flags an index the runtime would reject ======
try
    P = epsych.Protocol;
    pSel = P.addParameter('Software', 'Sel', 1);
    pSel.Values = {1, 7};
    pChoice = P.addParameter('Software', 'Choice', 'a', Type='String');
    pChoice.Values = {'a', 'b'};
    pChoice.Expression = "Sel";
    P.compile();

    report = P.sweepExpressions();
    msgs = {report.issues.message};
    hit = find(contains(msgs, 'index the runtime will reject'), 1);
    assert(~isempty(hit), 'expected a bad-index issue: %s', strjoin(msgs, ' | '));
    assert(report.issues(hit).severity == 2, 'bad index should be severity 2');

    fprintf('PASS: G. sweepExpressions flags out-of-range indices\n');
catch ME
    failures{end+1} = sprintf('G. sweep: %s', ME.message);
    fprintf('FAIL: G. %s\n', ME.message);
end

% ===== H. StimType parameter selects a stimulus object ==================
try
    P = epsych.Protocol;
    pSel = P.addParameter('Software', 'Sel', 1);
    pStim = P.addParameter('Software', 'Stim', 0);
    pStim.Type = 'StimType';
    pStim.Values = {stimgen.Tone, stimgen.Noise};
    pStim.Expression = "Sel";

    % A bare index is accepted as the incoming value: the expression replaces it.
    pSel.Value = 2;
    pStim.Value = 1;
    assert(isa(pStim.Value, 'stimgen.Noise'), ...
        'index 2 should select the Noise stimulus, got %s', class(pStim.Value));

    pSel.Value = 1;
    pStim.Value = 1;
    assert(isa(pStim.Value, 'stimgen.Tone'), ...
        'index 1 should select the Tone stimulus, got %s', class(pStim.Value));

    % Without an expression the type check still rejects a bare number.
    pStim.Expression = "";
    localExpectError_(@() localSet_(pStim, 1), ...
        'hw:Parameter:InvalidStimTypeValue', 'numeric value on a plain StimType parameter');

    fprintf('PASS: H. StimType parameter selects a stimulus by index\n');
catch ME
    failures{end+1} = sprintf('H. StimType: %s', ME.message);
    fprintf('FAIL: H. %s\n', ME.message);
end

% ===== I. Designer gating and status text ===============================
try
    P = epsych.Protocol;
    P.addParameter('Software', 'Sel', 2);
    pStr = P.addParameter('Software', 'Choice', 'a', Type='String');
    pStr.Values = {'a', 'b', 'c'};
    pTrig = P.addParameter('Software', 'Fire', false, Type='Boolean', isTrigger=true);

    D = epsych.ProtocolDesigner(P);
    cleanupObj = onCleanup(@() delete(D));

    % Column 4 is the Expression column of the parameter table.
    D.onParamEdited(localEditEvent_(D, pStr, 4, 'Sel'));
    assert(strcmp(pStr.Expression, "Sel"), ...
        'the designer should have stored the expression, got "%s"', pStr.Expression);
    assert(numel(pStr.Values) == 3, ...
        'the item list must survive expression evaluation, got %d item(s)', numel(pStr.Values));
    assert(strcmp(pStr.Values{2}, 'b'), 'the item list must be unchanged');

    % A fractional index is rejected and leaves the item list alone.
    D.onParamEdited(localEditEvent_(D, pStr, 4, 'Sel / 4'));
    assert(numel(pStr.Values) == 3, 'a rejected expression must not touch the item list');

    % Triggers still refuse expressions.
    D.onParamEdited(localEditEvent_(D, pTrig, 4, '1'));
    assert(strlength(pTrig.Expression) == 0, ...
        'a trigger should not accept an expression, got "%s"', pTrig.Expression);

    fprintf('PASS: I. designer accepts index expressions and keeps the item list\n');
catch ME
    failures{end+1} = sprintf('I. designer: %s', ME.message);
    fprintf('FAIL: I. %s\n', ME.message);
end

% ===== J. Save / reload round trip ======================================
try
    P = epsych.Protocol;
    P.addParameter('Software', 'Sel', 3);
    pChoice = P.addParameter('Software', 'Choice', 'a', Type='String');
    pChoice.Values = {'a', 'b', 'c'};
    pChoice.Expression = "Sel";

    protoFile = [tempname '.eprot'];
    fileCleanup = onCleanup(@() localDeleteIfPresent_(protoFile));
    P.save(protoFile);

    Q = epsych.Protocol.load(protoFile);
    qChoice = localFindParam_(Q, 'Choice');
    qSel = localFindParam_(Q, 'Sel');
    assert(strcmp(qChoice.Type, 'String'), 'reloaded type should be String, got %s', qChoice.Type);
    assert(strcmp(qChoice.Expression, "Sel"), ...
        'reloaded expression should be "Sel", got "%s"', qChoice.Expression);
    assert(numel(qChoice.Values) == 3, ...
        'reloaded item list should have 3 entries, got %d', numel(qChoice.Values));

    qSel.Value = 3;
    qChoice.Value = 'a';
    assert(strcmp(qChoice.Value, 'c'), ...
        'reloaded parameter should select item 3 ("c"), got "%s"', qChoice.Value);

    fprintf('PASS: J. index expression survives save and reload\n');
catch ME
    failures{end+1} = sprintf('J. round trip: %s', ME.message);
    fprintf('FAIL: J. %s\n', ME.message);
end

% ===== Summary ===========================================================
fprintf('\n');
if isempty(failures)
    fprintf('ALL PASS: index-selecting expressions\n');
else
    fprintf('%d FAILURE(S):\n', numel(failures));
    fprintf('  - %s\n', failures{:});
end
end


function localSet_(parameter, value)
parameter.Value = value;
end


function localExpectError_(fcn, expectedId, label)
try
    fcn();
catch ME
    assert(strcmp(ME.identifier, expectedId), ...
        '%s: expected %s, got %s (%s)', label, expectedId, ME.identifier, ME.message);
    return
end
error('smoke:NoError', '%s: expected error %s, none raised', label, expectedId);
end


function p = localFindParam_(protocol, name)
% First parameter with this name across every interface and module.
p = [];
for ifaceIdx = 1:numel(protocol.Interfaces)
    modules = protocol.Interfaces(ifaceIdx).Module;
    for modIdx = 1:numel(modules)
        params = modules(modIdx).Parameters;
        hit = find(strcmp({params.Name}, name), 1);
        if ~isempty(hit)
            p = params(hit);
            return
        end
    end
end
error('smoke:NoParameter', 'parameter "%s" not found in the reloaded protocol', name);
end


function localDeleteIfPresent_(fileName)
if exist(fileName, 'file')
    delete(fileName);
end
end


function evt = localEditEvent_(designer, parameter, column, newData)
% Synthesize the uitable CellEditCallback event for a parameter's table row.
row = find(cellfun(@(p) p == parameter, designer.ParameterHandles), 1);
assert(~isempty(row), 'parameter "%s" is not in the designer table', parameter.Name);
evt = struct('Indices', [row column], 'NewData', newData);
end
