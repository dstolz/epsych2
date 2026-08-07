function refreshCheckCalculations(obj)
% refreshCheckCalculations(obj)
% Recompile, sync one input field per variable involved in any calculated
% Expression, parse the field values (scalar or vector MATLAB expressions),
% run the exhaustive sweep (Protocol.sweepExpressions) over every
% combination, and populate the Check Calculations panel.
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
        obj.CheckCalcAnalysisArea.Value = {'No calculated parameters in this protocol.'};
        obj.CheckCalcStatusLabel.Text = 'No calculated parameters';
        obj.CheckCalcComboLabel.Text = '';
        delete(obj.CheckCalcInputsPanel.Children);
        obj.CheckCalcInputFields = struct('identifier', {}, 'label', {}, 'field', {});
        obj.setStatus('Check Calculations: no parameters with expressions', ...
            'Enter an expression in the Expression column of the parameter table to create a calculated parameter.');
        return
    end

    % ---- Sync input fields with the discovered variable set -------------
    wanted = {spec.inputs.identifier};
    existing = {obj.CheckCalcInputFields.identifier};
    if ~isequal(wanted, existing)
        previousText = containers.Map('KeyType', 'char', 'ValueType', 'char');
        for k = 1:numel(obj.CheckCalcInputFields)
            if isvalid(obj.CheckCalcInputFields(k).field)
                previousText(obj.CheckCalcInputFields(k).identifier) = obj.CheckCalcInputFields(k).field.Value;
            end
        end
        delete(obj.CheckCalcInputsPanel.Children);
        obj.CheckCalcInputFields = struct('identifier', {}, 'label', {}, 'field', {});

        rowH = 32;
        nRows = numel(spec.inputs);
        panelH = max(obj.CheckCalcInputsPanel.Position(4) - 8, nRows * rowH + 8);
        for k = 1:nRows
            y = panelH - k * rowH;
            lbl = uilabel(obj.CheckCalcInputsPanel, ...
                'Text', spec.inputs(k).label, ...
                'Position', [8 y 178 26], ...
                'Tooltip', localInputTooltip_(spec.inputs(k)));
            if isKey(previousText, spec.inputs(k).identifier)
                text = previousText(spec.inputs(k).identifier);
            else
                text = localFormatVector_(spec.inputs(k).defaultValues);
            end
            fld = uieditfield(obj.CheckCalcInputsPanel, 'text', ...
                'Value', text, ...
                'Position', [190 y 180 26], ...
                'Tooltip', 'Scalar or vector MATLAB expression, e.g. 500, [0.5 1 2], 100:100:1000');
            obj.CheckCalcInputFields(end+1) = struct( ...
                'identifier', spec.inputs(k).identifier, 'label', lbl, 'field', fld);
        end
    end

    % ---- Parse fields into sweep overrides ------------------------------
    parseIssues = struct('field', {}, 'message', {}, 'severity', {});
    inputsCell = cell(0, 2);
    for k = 1:numel(obj.CheckCalcInputFields)
        fld = obj.CheckCalcInputFields(k).field;
        fld.BackgroundColor = [1 1 1];
        raw = strtrim(fld.Value);
        if isempty(raw)
            continue  % blank falls back to design values
        end
        vals = str2num(raw); % str2num (not str2double) so vector expressions like 100:100:1000 work
        if isempty(vals) || ~(isnumeric(vals) || islogical(vals))
            fld.BackgroundColor = [1.0 0.88 0.88];
            parseIssues(end+1) = struct( ...
                'field', obj.CheckCalcInputFields(k).identifier, ...
                'message', sprintf('Could not parse "%s" as a numeric scalar/vector; using design values', raw), ...
                'severity', 1);
            continue
        end
        inputsCell(end+1, :) = {obj.CheckCalcInputFields(k).identifier, double(vals(:)).'};
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
    shownRows = localPopulateResults_(obj.CheckCalcTrialsTable, report);

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
    if shownRows < nCombos
        statusText = sprintf('%s (showing first %d rows)', statusText, shownRows);
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


function tip = localInputTooltip_(inputSpec)
    tip = inputSpec.identifier;
    if ~isempty(inputSpec.note)
        tip = sprintf('%s — %s', tip, inputSpec.note);
    end
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

    nIn = numel(inputs);
    nCalc = numel(calcs);
    shownRows = min(res.nCombos, MAX_ROWS);

    colNames = cell(1, nIn + nCalc + 1);
    for i = 1:nIn
        colNames{i} = inputs(i).identifier;
    end
    for k = 1:nCalc
        colNames{nIn + k} = calcs(k).fullName;
    end
    colNames{end} = 'Notes';

    data = cell(shownRows, nIn + nCalc + 1);
    for c = 1:shownRows
        for i = 1:nIn
            data{c, i} = res.inputValues(c, i);
        end
        noteParts = {};
        for k = 1:nCalc
            v = res.final(c, k);
            if isnan(res.computed(c, k))
                data{c, nIn + k} = 'ERR';
            elseif res.clamped(c, k)
                data{c, nIn + k} = sprintf('%g*', v);
            else
                data{c, nIn + k} = v;
            end
            if ~isempty(res.notes{c, k})
                noteParts{end+1} = sprintf('%s: %s', calcs(k).param.Name, res.notes{c, k});
            end
        end
        data{c, end} = strjoin(noteParts, ' | ');
    end

    tbl.ColumnName = colNames;
    tbl.ColumnWidth = [repmat({86}, 1, nIn + nCalc), {260}];
    tbl.Data = data;

    errStyle = uistyle('BackgroundColor', [1.0 0.88 0.88], 'FontColor', [0.60 0 0]);
    warnStyle = uistyle('BackgroundColor', [1.0 0.95 0.80]);
    for c = 1:shownRows
        if any(isnan(res.computed(c, :)))
            addStyle(tbl, errStyle, 'row', c);
        elseif any(res.clamped(c, :))
            addStyle(tbl, warnStyle, 'row', c);
        end
    end
end
