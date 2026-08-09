function refreshCheckCalculations(obj)
% refreshCheckCalculations(obj)
% Recompile, sync the editable sweep-input table (one row per variable
% involved in any calculated Expression; the Values column accepts scalar or
% vector MATLAB expressions), run the exhaustive sweep
% (Protocol.sweepExpressions) over every combination of the values, and
% populate the Check Calculations panel.
    if isempty(obj.CheckCalcTrialsTable) || ~isvalid(obj.CheckCalcTrialsTable)
        return
    end

    dialogFig = ancestor(obj.CheckCalcTrialsTable, 'figure');

    try
        % Always recompile: needsCompile only notices changes after a save,
        % so unsaved designer edits would otherwise reuse stale values.
        obj.Protocol.compile();
        spec = obj.Protocol.sweepExpressions(DiscoverOnly = true);
    catch ME
        vprintf(0, 1, ME);
        obj.CheckCalcStatusLabel.Text = 'Check failed';
        obj.setStatus('Check calculations failed', 'See the error dialog and command window for details.');
        uialert(dialogFig, ME.message, 'Check Calculations Failed');
        return
    end

    if isempty(spec.parameters)
        obj.CheckCalcIssuesTable.Data = {};
        obj.CheckCalcTrialsTable.Data = {};
        obj.CheckCalcInputsTable.Data = {};
        obj.CheckCalcInputsTable.UserData = {};
        obj.CheckCalcAnalysisArea.Value = {'No calculated parameters in this protocol.'};
        obj.CheckCalcStatusLabel.Text = 'No calculated parameters';
        obj.CheckCalcComboLabel.Text = '';
        obj.setStatus('Check Calculations: no parameters with expressions', ...
            'Enter an expression in the Expression column of the parameter table to create a calculated parameter.');
        return
    end

    % ---- Sync the input table with the discovered variable set ----------
    % UserData holds the identifier per row; user-typed Values text is
    % preserved for identifiers that persist across refreshes.
    wanted = {spec.inputs.identifier};
    previousIdents = obj.CheckCalcInputsTable.UserData;
    previousData = obj.CheckCalcInputsTable.Data;
    previousText = containers.Map('KeyType', 'char', 'ValueType', 'char');
    if iscell(previousIdents) && iscell(previousData) && size(previousData, 2) >= 2
        for k = 1:min(numel(previousIdents), size(previousData, 1))
            previousText(previousIdents{k}) = char(string(previousData{k, 2}));
        end
    end

    inputData = cell(numel(spec.inputs), 3);
    for k = 1:numel(spec.inputs)
        inputData{k, 1} = spec.inputs(k).label;
        if isKey(previousText, spec.inputs(k).identifier)
            inputData{k, 2} = previousText(spec.inputs(k).identifier);
        else
            inputData{k, 2} = localFormatVector_(spec.inputs(k).defaultValues);
        end
        inputData{k, 3} = spec.inputs(k).note;
    end
    obj.CheckCalcInputsTable.Data = inputData;
    obj.CheckCalcInputsTable.UserData = wanted;

    % ---- Parse the Values column into sweep overrides -------------------
    removeStyle(obj.CheckCalcInputsTable);
    badStyle = uistyle('BackgroundColor', [1.0 0.88 0.88], 'FontColor', [0.60 0 0]);
    parseIssues = struct('field', {}, 'message', {}, 'severity', {});
    inputsCell = cell(0, 2);
    for k = 1:numel(spec.inputs)
        raw = strtrim(char(string(inputData{k, 2})));
        if isempty(raw)
            continue  % blank falls back to design values
        end
        vals = str2num(raw); % str2num (not str2double) so vector expressions like 100:100:1000 work
        if isempty(vals) || ~(isnumeric(vals) || islogical(vals))
            addStyle(obj.CheckCalcInputsTable, badStyle, 'cell', [k 2]);
            parseIssues(end+1) = struct( ...
                'field', spec.inputs(k).identifier, ...
                'message', sprintf('Could not parse "%s" as a numeric scalar/vector; using design values', raw), ...
                'severity', 1);
            continue
        end
        inputsCell(end+1, :) = {spec.inputs(k).identifier, double(vals(:)).'};
    end

    % ---- Run the exhaustive sweep ---------------------------------------
    try
        report = obj.Protocol.sweepExpressions(Inputs = inputsCell);
    catch ME
        vprintf(0, 1, ME);
        obj.CheckCalcStatusLabel.Text = 'Check failed';
        obj.setStatus('Check calculations failed', 'See the error dialog and command window for details.');
        uialert(dialogFig, ME.message, 'Check Calculations Failed');
        return
    end
    report.issues = [parseIssues, report.issues];
    obj.CheckCalcReport = report;

    localPopulateIssues_(obj.CheckCalcIssuesTable, report.issues);
    obj.CheckCalcAnalysisArea.Value = localAnalysisText_(report);
    shownCombos = localPopulateResults_(obj.CheckCalcTrialsTable, report);

    nCombos = report.meta.nCombos;
    obj.CheckCalcComboLabel.Text = sprintf('%d combination(s)', nCombos);

    if report.meta.aborted
        obj.CheckCalcTrialsTable.Data = {};
        obj.CheckCalcStatusLabel.Text = sprintf('Aborted: %d combinations exceed the limit', nCombos);
        obj.setStatus('Check Calculations aborted: too many combinations', ...
            'Narrow the input ranges to at most 10000 combinations.');
        return
    end

    nErrors = nnz([report.issues.severity] == 2);
    nWarnings = nnz([report.issues.severity] == 1);
    statusText = sprintf('%d combination(s): %d error(s), %d warning(s)', nCombos, nErrors, nWarnings);
    if shownCombos < nCombos
        statusText = sprintf('%s (showing first %d combinations)', statusText, shownCombos);
    end
    obj.CheckCalcStatusLabel.Text = statusText;

    if nErrors > 0
        nextStep = 'Fix the expression errors above before running this protocol.';
    elseif nWarnings > 0
        nextStep = 'Review the warnings: values may be silently clamped or lag a trial at runtime.';
    else
        nextStep = 'All combinations evaluated cleanly with runtime semantics.';
    end
    obj.setStatus(sprintf('Check Calculations: %s', statusText), nextStep);
end


function txt = localFormatVector_(vals)
    if isempty(vals)
        txt = '';
    elseif isscalar(vals)
        txt = num2str(vals, '%g');
    else
        txt = mat2str(vals, 6);
    end
end


function localPopulateIssues_(tbl, issues)
    removeStyle(tbl);
    if isempty(issues)
        tbl.Data = {'', '', 'No issues found'};
        return
    end

    [~, order] = sort([issues.severity], 'descend');
    issues = issues(order);

    sevText = {'Info', 'Warning', 'Error'};
    data = cell(numel(issues), 3);
    for k = 1:numel(issues)
        data{k, 1} = sevText{issues(k).severity + 1};
        data{k, 2} = issues(k).field;
        data{k, 3} = issues(k).message;
    end
    tbl.Data = data;

    errStyle = uistyle('BackgroundColor', [1.0 0.88 0.88], 'FontColor', [0.60 0 0]);
    warnStyle = uistyle('BackgroundColor', [1.0 0.95 0.80]);
    for k = 1:numel(issues)
        if issues(k).severity == 2
            addStyle(tbl, errStyle, 'row', k);
        elseif issues(k).severity == 1
            addStyle(tbl, warnStyle, 'row', k);
        end
    end
end


function lines = localAnalysisText_(report)
    analysis = report.parameters;
    lines = {};
    for k = 1:numel(analysis)
        a = analysis(k);
        lines{end+1} = a.fullName;
        lines{end+1} = sprintf('  Expression : %s', a.expressionText);
        if a.multiLevelDormant
            lines{end+1} = '  Dormant    : multi-level parameter; expression skipped at runtime';
        elseif a.onReadParam
            lines{end+1} = '  Dormant    : Read access; expression never evaluates';
        end
        if a.selectsIndex
            lines{end+1} = sprintf(['  Selects    : %s parameter; the result is a whole-number index ' ...
                'from 1 to %d choosing one of its items (use round() or fix() if fractional)'], ...
                a.param.Type, a.itemCount);
        end
        lines{end+1} = sprintf('  Clamp      : [%g, %g]', a.clampMin, a.clampMax);
        if a.usesValueVariable
            lines{end+1} = '  Uses `Value` (incoming value) in the expression';
        end
        if a.isRandom
            lines{end+1} = '  Randomized at runtime (not simulated)';
        end
        if a.hasPreUpdateFcn
            lines{end+1} = '  Has PreUpdateFcn (not simulated)';
        end
        if a.hasEvaluatorFcn
            lines{end+1} = '  Has EvaluatorFcn (not simulated)';
        end
        if isempty(a.refs) && isempty(a.unresolvedRefs)
            lines{end+1} = '  References : none';
        else
            lines{end+1} = '  References :';
            for r = 1:numel(a.refs)
                ref = a.refs(r);
                extras = {};
                if ref.isReadAccess
                    extras{end+1} = 'hardware read';
                end
                if ref.dispatchedAfter && ref.variesAcrossTrials
                    extras{end+1} = 'lags one trial at runtime';
                end
                if ref.ambiguous
                    extras{end+1} = 'AMBIGUOUS';
                end
                if isempty(extras)
                    lines{end+1} = sprintf('    %s', ref.token);
                else
                    lines{end+1} = sprintf('    %s  (%s)', ref.token, strjoin(extras, ', '));
                end
            end
            for u = 1:numel(a.unresolvedRefs)
                lines{end+1} = sprintf('    %s  (UNRESOLVED)', a.unresolvedRefs{u});
            end
        end
        if ~isempty(a.cycleWith)
            lines{end+1} = sprintf('  Cycle with : %s', strjoin(a.cycleWith, ', '));
        end
        lines{end+1} = '';
    end

    lines{end+1} = 'Assumptions:';
    for k = 1:numel(report.meta.assumptions)
        lines{end+1} = sprintf('  - %s', report.meta.assumptions{k});
    end
end


function shownRows = localPopulateResults_(tbl, report)
% Populate the results table: one row per combination, one column per input
% and per calculated parameter, plus notes. Returns the number of rows shown.
    MAX_ROWS = 2000;
    removeStyle(tbl);

    res = report.results;
    inputs = report.inputs;
    calcs = report.calcs;
    shownRows = 0;

    if report.meta.aborted || res.nCombos == 0
        tbl.Data = {};
        return
    end

    % Transposed layout: one column per combination (easier to scan a single
    % calculation across many combos), one row per variable. Row order:
    % inputs, then calculated parameters, then a combined Notes row.
    nIn = numel(inputs);
    nCalc = numel(calcs);
    nShown = min(res.nCombos, MAX_ROWS);
    shownRows = nShown;

    rowNames = cell(1, nIn + nCalc + 1);
    for i = 1:nIn
        rowNames{i} = inputs(i).identifier;
    end
    for k = 1:nCalc
        rowNames{nIn + k} = calcs(k).fullName;
    end
    rowNames{end} = 'Notes';

    colNames = arrayfun(@(c) sprintf('Combo %d', c), 1:nShown, 'UniformOutput', false);

    data = cell(nIn + nCalc + 1, nShown);
    errCombo = false(1, nShown);
    warnCombo = false(1, nShown);
    for c = 1:nShown
        for i = 1:nIn
            data{i, c} = res.inputValues(c, i);
        end
        noteParts = {};
        for k = 1:nCalc
            v = res.final(c, k);
            if isnan(res.computed(c, k))
                data{nIn + k, c} = 'ERR';
                errCombo(c) = true;
            elseif res.clamped(c, k)
                data{nIn + k, c} = sprintf('%g*', v);
                warnCombo(c) = true;
            else
                data{nIn + k, c} = v;
            end
            if ~isempty(res.notes{c, k})
                noteParts{end+1} = sprintf('%s: %s', calcs(k).param.Name, res.notes{c, k});
            end
        end
        data{end, c} = strjoin(noteParts, ' | ');
    end

    tbl.RowName = rowNames;
    tbl.ColumnName = colNames;
    tbl.ColumnWidth = repmat({100}, 1, nShown);
    tbl.Data = data;

    errStyle = uistyle('BackgroundColor', [1.0 0.88 0.88], 'FontColor', [0.60 0 0]);
    warnStyle = uistyle('BackgroundColor', [1.0 0.95 0.80]);
    for c = 1:nShown
        if errCombo(c)
            addStyle(tbl, errStyle, 'column', c);
        elseif warnCombo(c)
            addStyle(tbl, warnStyle, 'column', c);
        end
    end
end
