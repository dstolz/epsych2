function smoke_test_designer_constant_expression()
% smoke_test_designer_constant_expression()
% Gate on the constant-expression fix in ProtocolDesigner: a literal constant
% entered in the Expression column is stored as a fixed design-time Value and
% the Expression is dropped; the Value column accepts direct numeric edits for
% Float/Integer/Boolean; and loading a protocol that carries constant
% Expressions (written by older designer versions) converts them.
%
% Why it matters: hw.Parameter.set.Value re-derives a non-empty Expression on
% every per-trial dispatch, so a constant Expression on an UpdateEveryTrial
% parameter overrides every runtime write - a staircase driving Depth through
% the trial table stays pinned at the constant forever.
%
%   matlab -batch "run('tmp/smoke_test_designer_constant_expression.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

% ===== 0. Literal vs expression classification (end to end) ===============
% isLiteralConstantExpression lives in the class private folder, so probe it
% through the public edit path: enter each text in the Expression column of a
% scratch Float and see whether it survives as an Expression.
P0 = epsych.Protocol;
probe = P0.addParameter('Software', 'Probe', 1);
P0.addParameter('Software', 'Anchor', 7);
pd = epsych.ProtocolDesigner(P0);
cleanupPd = onCleanup(@() localForceClose_(pd));
try
    literals = {'0', '-2', '500', '0.5', '1e3', '2.5E-2', '[0 -5 -10]', '0:5:40', '2*pi'};
    for k = 1:numel(literals)
        probe.Expression = "";
        pd.onParamEdited(localEditEvent_(pd, 'Probe', 4, literals{k}));
        assert(strlength(probe.Expression) == 0, ...
            '"%s" should be stored as a fixed value, not kept as an Expression', literals{k});
    end
    expressions = {'Anchor + 10', 'Anchor.Min', 'rand()*5', 'log10(2)', 'round(1.5)'};
    for k = 1:numel(expressions)
        probe.Expression = "";
        pd.onParamEdited(localEditEvent_(pd, 'Probe', 4, expressions{k}));
        assert(strlength(probe.Expression) > 0, ...
            '"%s" should persist as an Expression', expressions{k});
    end
    fprintf('PASS: 0. literal constants convert, expressions persist\n');
catch ME
    failures{end+1} = sprintf('0. classification: %s', ME.message);
    fprintf('FAIL: 0. %s\n', ME.message);
end
localForceClose_(pd);

% ===== Shared fixture: protocol with Float parameters =====================
P = epsych.Protocol;
pDepth = P.addParameter('Software', 'Depth', 0);
pStep  = P.addParameter('Software', 'StepOnHit', -2);
P.addParameter('Software', 'RespWin', 100);

pd = epsych.ProtocolDesigner(P);
cleanupPd2 = onCleanup(@() localForceClose_(pd));

% ===== A. Constant entered in the Expression column becomes a fixed value =
try
    pd.onParamEdited(localEditEvent_(pd, 'Depth', 4, '0'));
    assert(strlength(pDepth.Expression) == 0, 'constant "0" should not persist as an Expression');
    assert(isequal(pDepth.Values, {0}), 'Values should hold the constant 0');

    pd.onParamEdited(localEditEvent_(pd, 'StepOnHit', 4, '-2'));
    assert(strlength(pStep.Expression) == 0, 'constant "-2" should not persist as an Expression');
    assert(isequal(pStep.Values, {-2}), 'Values should hold the constant -2');

    % Arithmetic on numeric constants is still a literal.
    pd.onParamEdited(localEditEvent_(pd, 'Depth', 4, '2*pi'));
    assert(strlength(pDepth.Expression) == 0, '"2*pi" should not persist as an Expression');
    assert(abs(pDepth.Values{1} - 2*pi) < 1e-12, 'Values should hold 2*pi');

    fprintf('PASS: A. constant Expression entries are stored as fixed Values\n');
catch ME
    failures{end+1} = sprintf('A. constant expression: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% ===== B. Referencing expressions still persist ===========================
try
    pd.onParamEdited(localEditEvent_(pd, 'Depth', 4, 'RespWin - 100'));
    assert(strcmp(char(pDepth.Expression), 'RespWin - 100'), ...
        'a referencing expression must persist, got "%s"', pDepth.Expression);

    % Multi-value entries keep the existing drop-to-levels behavior.
    pd.onParamEdited(localEditEvent_(pd, 'StepOnHit', 4, '[0 -5 -10]'));
    assert(strlength(pStep.Expression) == 0, 'multi-value entry should drop the Expression');
    assert(isequal(pStep.Values, {0, -5, -10}), 'Values should hold the level list');

    fprintf('PASS: B. referencing expressions persist; level lists drop the Expression\n');
catch ME
    failures{end+1} = sprintf('B. referencing expression: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. Value column accepts direct numeric edits =======================
try
    pd.onParamEdited(localEditEvent_(pd, 'StepOnHit', 5, '-12'));
    assert(isequal(pStep.Values, {-12}), 'Value edit should store -12, got %s', mat2str([pStep.Values{:}]));
    assert(strlength(pStep.Expression) == 0, 'Value edit should leave no Expression');

    % Editing the Value of an expression-bearing parameter clears the rule.
    assert(strlength(pDepth.Expression) > 0, 'fixture: Depth should still carry its expression');
    pd.onParamEdited(localEditEvent_(pd, 'Depth', 5, '-6'));
    assert(isequal(pDepth.Values, {-6}), 'Value edit should store -6');
    assert(strlength(pDepth.Expression) == 0, 'Value edit should remove the prior Expression');

    % A level list typed into Value works like the Expression column did.
    pd.onParamEdited(localEditEvent_(pd, 'Depth', 5, '0:-10:-40'));
    assert(isequal(pDepth.Values, {0, -10, -20, -30, -40}), 'Value edit should accept a range');
    assert(pDepth.isArray, 'range entry should set isArray');

    fprintf('PASS: C. Value column edits store fixed Values and clear Expressions\n');
catch ME
    failures{end+1} = sprintf('C. value column: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end
localForceClose_(pd);

% ===== D. Loading a protocol file heals stored constant Expressions =======
% Built like a protocol saved by the pre-fix designer: a constant Expression
% on every numeric parameter. Loading through the file path (the same route
% onLoad/openProtocolFile take) must convert the constants, keep genuine
% rules, and mark the designer modified so the healed state gets saved.
try
    P2 = epsych.Protocol;
    d = P2.addParameter('Software', 'Depth', 0);
    d.Values = {0};
    d.Expression = "0";                       % old designer output
    s = P2.addParameter('Software', 'StimDur', 500);
    s.Values = {500};
    s.Expression = "500";                     % old designer output
    r = P2.addParameter('Software', 'RespWinDur', 200);
    r.Expression = "StimDur - 300";           % genuine rule: must survive
    c = P2.addParameter('Software', 'Choice', 'a', Type='String');
    c.Values = {'a', 'b'};
    c.Expression = "2";                       % index-selecting: must survive

    tmpFile = fullfile(tempdir, 'smoke_designer_constant_expr.eprot');
    cleanupFile = onCleanup(@() localDeleteFile_(tmpFile));
    P2.save(tmpFile);

    pd = epsych.ProtocolDesigner(tmpFile);
    cleanupPd3 = onCleanup(@() localForceClose_(pd));

    dL = localFindParameter_(pd, 'Depth');
    sL = localFindParameter_(pd, 'StimDur');
    rL = localFindParameter_(pd, 'RespWinDur');
    cL = localFindParameter_(pd, 'Choice');

    assert(strlength(dL.Expression) == 0 && isequal(dL.Values, {0}), 'Depth "0" should convert on load');
    assert(strlength(sL.Expression) == 0 && isequal(sL.Values, {500}), 'StimDur "500" should convert on load');
    assert(strcmp(char(rL.Expression), 'StimDur - 300'), 'referencing expression must survive the load');
    assert(strcmp(char(cL.Expression), '2'), 'index-selecting constant must survive the load');

    % The conversion counts as an unsaved change, so closing prompts to save.
    warnState = warning('off', 'MATLAB:structOnObject');
    pdState = struct(pd);
    warning(warnState);
    assert(pdState.IsModified_, 'conversion on load must mark the protocol modified');

    % A designer bound afterward finds nothing left to convert.
    assert(isempty(pd.normalizeConstantExpressions()), 'second pass should convert nothing');

    fprintf('PASS: D. file load converts constants, keeps rules, marks modified\n');
catch ME
    failures{end+1} = sprintf('D. normalization: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end
localForceClose_(pd);

% ===== Summary ============================================================
if isempty(failures)
    fprintf('\nALL PASS: designer constant-expression handling\n');
else
    fprintf('\n%d FAILURE(S):\n', numel(failures));
    fprintf('  %s\n', failures{:});
    error('smoke:designerConstantExpression', 'smoke test failed');
end

end


function evt = localEditEvent_(pd, parameterName, column, newData)
% Build a CellEditCallback-shaped event for the named parameter row.
row = find(cellfun(@(h) strcmp(h.Name, parameterName), pd.ParameterHandles), 1);
assert(~isempty(row), 'fixture: parameter %s not found in the designer table', parameterName);
evt = struct('Indices', [row, column], 'NewData', newData);
end


function p = localFindParameter_(pd, parameterName)
idx = find(cellfun(@(h) strcmp(h.Name, parameterName), pd.ParameterHandles), 1);
assert(~isempty(idx), 'parameter %s not found in the loaded designer', parameterName);
p = pd.ParameterHandles{idx};
end


function localDeleteFile_(filePath)
if isfile(filePath)
    delete(filePath);
end
end


function localForceClose_(pd)
if isvalid(pd)
    warnState = warning('off', 'MATLAB:structOnObject');
    s = struct(pd);
    warning(warnState);
    figs = {s.Figure, s.InterfaceFigure, s.OptionsFigure, s.PreviewFigure, s.CheckCalcFigure};
    for idx = 1:numel(figs)
        if ~isempty(figs{idx}) && isvalid(figs{idx})
            delete(figs{idx});
        end
    end
end
end
