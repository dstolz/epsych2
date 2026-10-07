function refreshTransferPreview(obj)
% refreshTransferPreview(obj)
% Recompute and display the plan shown in the Copy or Move Parameters dialog.
%
% Runs on every control change and after every refreshParameterTab, so the
% preview always describes the protocol as it is now; the module dropdowns are
% rebuilt each time and keep their selection by module handle, not by position,
% so adding or removing a module elsewhere cannot silently retarget them.
    if isempty(obj.TransferFigure) || ~isvalid(obj.TransferFigure)
        return
    end

    [modules, labels] = obj.getModuleChoices();
    sourceModule = localSyncModuleDropdown_(obj.TransferSource, modules, labels);
    targetModule = localSyncModuleDropdown_(obj.TransferTarget, modules, labels);
    isMove = strcmp(obj.TransferMode.Value, 'move');
    if isMove
        obj.TransferApply.Text = 'Move';
        verb = 'moved';
    else
        obj.TransferApply.Text = 'Copy';
        verb = 'copied';
    end

    state = obj.TransferTable.UserData;
    removeStyle(obj.TransferTable);
    if isempty(sourceModule)
        obj.TransferPlan = struct();
        state.RowParams = hw.Parameter.empty(1, 0);
        obj.TransferTable.UserData = state;
        obj.TransferTable.Data = cell(0, 7);
        obj.TransferRewriteTable.Data = cell(0, 4);
        obj.TransferRewriteLabel.Text = '';
        state.Detail.Value = {''};
        obj.TransferSummary.Text = 'The protocol has no modules.';
        obj.TransferApply.Enable = 'off';
        return
    end

    rowParams = sourceModule.Parameters;
    isChecked = arrayfun(@(p) any(obj.TransferChecked == p), rowParams);
    plan = obj.planParameterTransfer(rowParams(isChecked), targetModule, ...
        Mode = obj.TransferMode.Value, OnConflict = obj.TransferConflict.Value);
    obj.TransferPlan = plan;

    tableData = cell(numel(rowParams), 7);
    rowNotes = repmat({''}, 1, numel(rowParams));
    for row = 1:numel(rowParams)
        parameter = rowParams(row);
        tableData(row, :) = {isChecked(row), parameter.Name, parameter.Type, ...
            obj.getParameterValueDisplay(parameter), '', '', ''};
    end

    actionLabels = struct('copy', 'Copy', 'move', 'Move', 'overwrite', 'Overwrite', 'skip', 'Skip');
    skipRows = [];
    overwriteRows = [];
    for k = 1:numel(plan.Entries)
        entry = plan.Entries(k);
        row = find(rowParams == entry.Parameter, 1);
        tableData(row, 5:7) = {entry.NewName, actionLabels.(entry.Status), entry.Message};
        rowNotes{row} = entry.Message;
        switch entry.Status
            case 'skip'
                skipRows(end + 1) = row;
            case 'overwrite'
                overwriteRows(end + 1) = row;
        end
    end

    state.RowParams = rowParams;
    obj.TransferTable.Data = tableData;

    uncheckedRows = find(~isChecked);
    if ~isempty(uncheckedRows)
        addStyle(obj.TransferTable, uistyle('FontColor', [0.55 0.58 0.62]), 'row', uncheckedRows);
    end
    if ~isempty(overwriteRows)
        addStyle(obj.TransferTable, uistyle('BackgroundColor', [1.0 0.94 0.78]), 'row', overwriteRows);
    end
    if ~isempty(skipRows)
        addStyle(obj.TransferTable, ...
            uistyle('BackgroundColor', [1.0 0.88 0.88], 'FontColor', [0.60 0.00 0.00]), 'row', skipRows);
    end

    % Keep the clicked row's notes on show across refreshes, by parameter.
    detailRow = [];
    if ~isempty(state.DetailParam)
        detailRow = find(rowParams == state.DetailParam, 1);
    end
    if isempty(detailRow)
        state.DetailParam = hw.Parameter.empty(1, 0);
        state.Detail.Value = {'Click a row to read its notes in full.'};
    elseif ~isChecked(detailRow)
        state.Detail.Value = {sprintf('%s is not ticked.', rowParams(detailRow).Name)};
    elseif isempty(rowNotes{detailRow})
        state.Detail.Value = {sprintf('%s: nothing to note.', rowParams(detailRow).Name)};
    else
        state.Detail.Value = {sprintf('%s: %s', rowParams(detailRow).Name, rowNotes{detailRow})};
    end
    obj.TransferTable.UserData = state;

    rewriteData = cell(numel(plan.Rewrites), 4);
    for k = 1:numel(plan.Rewrites)
        rewrite = plan.Rewrites(k);
        rewriteData(k, :) = {rewrite.Location, rewrite.Parameter.Name, ...
            rewrite.OldExpression, rewrite.NewExpression};
    end
    obj.TransferRewriteTable.Data = rewriteData;
    if isMove
        obj.TransferRewriteLabel.Text = sprintf( ...
            'Other expressions the move updates (%d)', numel(plan.Rewrites));
    else
        obj.TransferRewriteLabel.Text = 'Other expressions: a copy leaves them unchanged.';
    end

    actionCount = numel(plan.Entries) - numel(skipRows);
    if isempty(rowParams)
        summary = 'The source module has no parameters.';
    elseif isempty(plan.Entries)
        summary = sprintf('Tick the parameters to be %s.', verb);
    else
        summary = sprintf('%d parameter(s) will be %s to %s', actionCount, verb, plan.TargetLocation);
        if ~isempty(overwriteRows)
            summary = sprintf('%s, %d overwriting an existing one', summary, numel(overwriteRows));
        end
        if ~isempty(skipRows)
            summary = sprintf('%s; %d skipped (highlighted)', summary, numel(skipRows));
        end
        summary = [summary '.'];
    end
    if ~isempty(plan.Warnings)
        summary = strjoin([{summary}, reshape(plan.Warnings, 1, [])], ' ');
    end
    obj.TransferSummary.Text = summary;
    obj.TransferApply.Enable = obj.onOffForCondition(actionCount > 0);
end


function module = localSyncModuleDropdown_(dropdown, modules, labels)
% Refill a module dropdown and keep the module it had selected, by handle.
% UserData holds the modules in Items order; labels are unique because they
% carry the interface and module indices.
    previous = [];
    previousIdx = find(strcmp(dropdown.Items, dropdown.Value), 1);
    if ~isempty(previousIdx) && previousIdx <= numel(dropdown.UserData)
        previous = dropdown.UserData(previousIdx);
    end

    if isempty(modules)
        dropdown.Items = {'<none>'};
        dropdown.Value = '<none>';
        dropdown.UserData = hw.Module.empty(1, 0);
        module = [];
        return
    end

    index = [];
    if ~isempty(previous)
        index = find(modules == previous, 1);
    end
    if isempty(index)
        index = 1;
    end

    dropdown.Items = labels;
    dropdown.Value = labels{index};
    dropdown.UserData = modules;
    module = modules(index);
end
