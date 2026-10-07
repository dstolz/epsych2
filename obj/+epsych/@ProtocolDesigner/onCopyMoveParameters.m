function onCopyMoveParameters(obj)
% onCopyMoveParameters(obj)
% Open the Copy or Move Parameters dialog (Ctrl+Shift+X), which copies or
% moves parameters from one module into another module on the same interface
% or a different one.
%
% Every change is previewed before it is applied, because a transfer can
% rewrite expressions and overwrite parameters, and there is no undo. The
% dialog opens on the module of the selected table rows with those rows
% ticked, aimed at the Add To Interface / Module target when that is a
% different module. The plan itself is planParameterTransfer; Apply hands it
% to applyParameterTransfer.
    [modules, labels] = obj.getModuleChoices();
    if isempty(modules)
        obj.setStatus('No modules to copy parameters between', ...
            'Add an interface with at least one module first.');
        return
    end

    [dialog, isNew] = obj.openToolDialog('TransferFigure', 'Copy or Move Parameters', [820 660]);
    if ~isNew
        obj.refreshTransferPreview();
        return
    end
    dialog.Color = [0.945 0.951 0.960];

    % Seed from the table selection and the Add To target.
    seeds = localSelectedParameters_(obj);
    sourceModule = obj.getSelectedTargetModule();
    if ~isempty(seeds)
        sourceModule = seeds(1).Module;
    end
    if isempty(sourceModule)
        sourceModule = modules(1);
    end
    targetModule = obj.getSelectedTargetModule();
    if isempty(targetModule) || targetModule == sourceModule
        others = modules(modules ~= sourceModule);
        if isempty(others)
            targetModule = sourceModule;
        else
            targetModule = others(1);
        end
    end
    obj.TransferChecked = seeds;

    labelColor = [0.22 0.28 0.36];

    uilabel(dialog, 'Text', 'From', 'Position', [20 618 90 22], ...
        'FontWeight', 'bold', 'FontColor', labelColor);
    obj.TransferSource = uidropdown(dialog, ...
        'Position', [112 616 290 26], ...
        'Items', labels, ...
        'Value', labels{modules == sourceModule}, ...
        'UserData', modules, ...
        'BackgroundColor', [0.997 0.998 0.999], ...
        'Tooltip', 'Module whose parameters are listed below.', ...
        'ValueChangedFcn', @(~, ~) obj.refreshTransferPreview());

    uilabel(dialog, 'Text', 'To', 'Position', [420 618 100 22], ...
        'FontWeight', 'bold', 'FontColor', labelColor);
    obj.TransferTarget = uidropdown(dialog, ...
        'Position', [522 616 278 26], ...
        'Items', labels, ...
        'Value', labels{modules == targetModule}, ...
        'UserData', modules, ...
        'BackgroundColor', [0.997 0.998 0.999], ...
        'Tooltip', ['Module that receives the parameters: another module on the same interface, ' ...
                    'a module on a different interface, or (for a copy) the same module.'], ...
        'ValueChangedFcn', @(~, ~) obj.refreshTransferPreview());

    uilabel(dialog, 'Text', 'Action', 'Position', [20 580 90 22], ...
        'FontWeight', 'bold', 'FontColor', labelColor);
    obj.TransferMode = uidropdown(dialog, ...
        'Position', [112 578 290 26], ...
        'Items', {'Copy (originals stay where they are)', 'Move (originals leave the source)'}, ...
        'ItemsData', {'copy', 'move'}, ...
        'Value', 'copy', ...
        'BackgroundColor', [0.997 0.998 0.999], ...
        'Tooltip', ['Copy leaves the source parameters and every other expression alone. ' ...
                    'Move takes them out of the source module and repoints expressions that named them.'], ...
        'ValueChangedFcn', @(~, ~) obj.refreshTransferPreview());

    uilabel(dialog, 'Text', 'If target has it', 'Position', [420 580 100 22], ...
        'FontWeight', 'bold', 'FontColor', labelColor);
    obj.TransferConflict = uidropdown(dialog, ...
        'Position', [522 578 278 26], ...
        'Items', {'Rename the new one (Name_1)', 'Overwrite the one in the target', 'Skip it'}, ...
        'ItemsData', {'rename', 'overwrite', 'skip'}, ...
        'Value', 'rename', ...
        'BackgroundColor', [0.997 0.998 0.999], ...
        'Tooltip', ['What to do when the target module already has a parameter of the same name. ' ...
                    'Overwrite gives the existing parameter the source''s settings and keeps the expressions that name it. ' ...
                    'A name used anywhere else in the protocol is always renamed, because compiling needs ' ...
                    'every parameter name to be unique.'], ...
        'ValueChangedFcn', @(~, ~) obj.refreshTransferPreview());

    uibutton(dialog, 'push', ...
        'Text', 'Tick All', ...
        'Position', [20 540 90 26], ...
        'Tooltip', 'Tick every parameter of the source module.', ...
        'ButtonPushedFcn', @(~, ~) localTickAll_(obj, true));
    uibutton(dialog, 'push', ...
        'Text', 'Tick None', ...
        'Position', [116 540 90 26], ...
        'Tooltip', 'Untick every parameter of the source module.', ...
        'ButtonPushedFcn', @(~, ~) localTickAll_(obj, false));

    obj.TransferSummary = uilabel(dialog, ...
        'Text', '', ...
        'Position', [222 532 578 42], ...
        'FontWeight', 'bold', ...
        'WordWrap', 'on', ...
        'FontColor', labelColor);

    obj.TransferTable = uitable(dialog, ...
        'Position', [20 268 780 256], ...
        'ColumnName', {'', 'Parameter', 'Type', 'Value', 'New Name', 'Action', 'Notes'}, ...
        'ColumnWidth', {28, 130, 74, 90, 130, 70, 240}, ...
        'RowName', {}, ...
        'ColumnEditable', [true false false false false false false], ...
        'ColumnFormat', {'logical', 'char', 'char', 'char', 'char', 'char', 'char'}, ...
        'ColumnSortable', false, ...
        'Tooltip', 'Tick the parameters to transfer. Click a row to read its notes in full below.', ...
        'CellEditCallback', @(~, evt) localOnCellEdit_(obj, evt), ...
        'CellSelectionCallback', @(~, evt) localOnCellSelected_(obj, evt));

    % Full notes for the clicked row; the Notes column is too narrow for them.
    detail = uitextarea(dialog, ...
        'Position', [20 220 780 40], ...
        'Editable', 'off', ...
        'Value', {''}, ...
        'BackgroundColor', [0.985 0.988 0.993], ...
        'FontColor', [0.36 0.43 0.52]);
    obj.TransferTable.UserData = struct('RowParams', hw.Parameter.empty(1, 0), ...
        'Detail', detail, 'DetailParam', hw.Parameter.empty(1, 0));

    obj.TransferRewriteLabel = uilabel(dialog, ...
        'Text', '', ...
        'Position', [20 190 780 22], ...
        'FontWeight', 'bold', ...
        'FontColor', labelColor);
    obj.TransferRewriteTable = uitable(dialog, ...
        'Position', [20 66 780 120], ...
        'ColumnName', {'Module', 'Parameter', 'Current Expression', 'New Expression'}, ...
        'ColumnWidth', {200, 130, 215, 215}, ...
        'RowName', {}, ...
        'ColumnEditable', false, ...
        'ColumnSortable', true);

    uilabel(dialog, ...
        'Text', ['Expressions are rewritten so every reference still names the same parameter; ' ...
                 'a group transferred together stays wired together.'], ...
        'Position', [20 22 520 36], ...
        'FontAngle', 'italic', ...
        'WordWrap', 'on', ...
        'FontColor', [0.36 0.43 0.52]);

    obj.TransferApply = uibutton(dialog, 'push', ...
        'Text', 'Copy', ...
        'Position', [560 24 120 32], ...
        'FontWeight', 'bold', ...
        'Enable', 'off', ...
        'Tooltip', 'Apply every previewed row whose action is not Skip.', ...
        'ButtonPushedFcn', @(~, ~) localApply_(obj));

    uibutton(dialog, 'push', ...
        'Text', 'Close', ...
        'Position', [690 24 110 32], ...
        'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~, ~) delete(dialog));

    obj.refreshTransferPreview();
end


function params = localSelectedParameters_(obj)
% Parameters behind the selected rows of the main table, in row order.
    params = hw.Parameter.empty(1, 0);
    selection = obj.TableParams.Selection;
    if isempty(selection)
        rows = obj.SelectedParamRow;
    elseif strcmp(obj.TableParams.SelectionType, 'cell')
        rows = unique(selection(:, 1), 'stable')';
    elseif strcmp(obj.TableParams.SelectionType, 'row')
        rows = reshape(selection, 1, []);
    else
        rows = obj.SelectedParamRow;
    end

    for row = rows(rows >= 1 & rows <= numel(obj.ParameterHandles))
        params(end + 1) = obj.ParameterHandles{row};
    end
end


function localTickAll_(obj, tf)
    rowParams = obj.TransferTable.UserData.RowParams;
    checked = obj.TransferChecked;
    isRow = arrayfun(@(p) any(rowParams == p), checked);
    if tf
        checked = [checked(~isRow), rowParams];
    else
        checked = checked(~isRow);
    end
    obj.TransferChecked = checked;
    obj.refreshTransferPreview();
end


function localOnCellEdit_(obj, evt)
    rowParams = obj.TransferTable.UserData.RowParams;
    row = evt.Indices(1);
    if evt.Indices(2) ~= 1 || row > numel(rowParams)
        return
    end

    parameter = rowParams(row);
    obj.TransferChecked = obj.TransferChecked(obj.TransferChecked ~= parameter);
    if evt.NewData
        obj.TransferChecked(end + 1) = parameter;
    end
    obj.refreshTransferPreview();
end


function localOnCellSelected_(obj, evt)
    if isempty(evt.Indices)
        return
    end
    state = obj.TransferTable.UserData;
    row = evt.Indices(1, 1);
    if row > numel(state.RowParams)
        return
    end
    state.DetailParam = state.RowParams(row);
    obj.TransferTable.UserData = state;
    obj.refreshTransferPreview();
end


function localApply_(obj)
% Re-plan against the protocol as it is now, confirm overwrites, apply, then
% close the dialog and report the outcome in the main window. Left open, the
% dialog re-rendered the next plan for the still-ticked rows and looked exactly
% as if the click had done nothing.
    obj.refreshTransferPreview();
    plan = obj.TransferPlan;
    if isempty(fieldnames(plan)) || isempty(plan.Entries)
        return
    end
    statuses = {plan.Entries.Status};
    actionCount = sum(~strcmp(statuses, 'skip'));
    overwriteCount = sum(strcmp(statuses, 'overwrite'));
    if actionCount == 0
        return
    end

    if overwriteCount > 0
        choice = uiconfirm(obj.TransferFigure, ...
            sprintf(['%d existing parameter(s) in %s will take the settings of the parameter they ' ...
                     'replace. Their current settings cannot be restored.'], ...
                     overwriteCount, plan.TargetLocation), ...
            'Overwrite Parameters', ...
            'Options', {'Overwrite', 'Cancel'}, ...
            'DefaultOption', 'Cancel', ...
            'CancelOption', 'Cancel', ...
            'Icon', 'warning');
        if ~strcmp(choice, 'Overwrite')
            return
        end
    end

    if strcmp(plan.Mode, 'move')
        action = 'Move';
        verb = 'Moved';
    else
        action = 'Copy';
        verb = 'Copied';
    end

    failure = [];
    transferred = hw.Parameter.empty(1, 0);
    problems = {};
    try
        [transferred, problems] = obj.applyParameterTransfer(plan);
    catch ME
        vprintf(0, 1, ME);
        failure = ME;
    end

    delete(obj.TransferFigure);
    figure(obj.Figure);

    if ~isempty(failure)
        % A stale plan is refused before anything changes; any other error may
        % have stopped part way.
        if strcmp(failure.identifier, 'epsych:ProtocolDesigner:StalePlan')
            lead = sprintf('Nothing was %s.', lower(verb));
        else
            lead = sprintf(['The %s stopped with an error, so some parameters may already have been %s. ' ...
                'Check the parameter table before trying again.'], lower(action), lower(verb));
        end
        obj.setStatus(sprintf('%s failed: %s', action, failure.message), ...
            'Reopen Copy / Move... and try again.');
        uialert(obj.Figure, sprintf('%s\n\n%s', lead, failure.message), ...
            sprintf('%s Failed', action), 'Icon', 'error');
        return
    end

    applied = plan.Entries(~strcmp({plan.Entries.Status}, 'skip'));
    skipped = plan.Entries(strcmp({plan.Entries.Status}, 'skip'));

    lines = {sprintf('%s %d parameter(s) to %s.', verb, numel(transferred), plan.TargetLocation)};
    lines = [lines, localCapped_(arrayfun(@localDescribeApplied_, applied, 'UniformOutput', false))];
    if ~isempty(plan.Rewrites)
        lines{end + 1} = sprintf('Updated %d other expression(s) that named a moved parameter.', ...
            numel(plan.Rewrites));
    end
    if ~isempty(skipped)
        lines{end + 1} = sprintf('Skipped %d:', numel(skipped));
        lines = [lines, localCapped_(arrayfun(@(e) sprintf('    %s: %s', e.OldName, e.Message), ...
            skipped, 'UniformOutput', false))];
    end
    if ~isempty(problems)
        lines{end + 1} = sprintf('%d need attention:', numel(problems));
        lines = [lines, localCapped_(strcat({'    '}, problems))];
    end

    status = sprintf('%s %d parameter(s) to %s', verb, numel(transferred), plan.TargetLocation);
    if ~isempty(skipped)
        status = sprintf('%s; %d skipped', status, numel(skipped));
    end
    if isempty(problems)
        obj.setStatus(status, 'Check the transferred rows, then compile to confirm the trial set.');
        icon = 'success';
    else
        obj.setStatus(sprintf('%s; %d problem(s) found', status, numel(problems)), ...
            'Fix the highlighted rows, then compile to confirm the trial set.');
        icon = 'warning';
    end
    if ~isempty(skipped)
        icon = 'warning';
    end
    uialert(obj.Figure, strjoin(lines, newline), sprintf('Parameters %s', verb), 'Icon', icon);
end


function line = localDescribeApplied_(entry)
    switch entry.Status
        case 'overwrite'
            line = sprintf('    %s (replaced the existing one)', entry.NewName);
        otherwise
            if strcmp(entry.OldName, entry.NewName)
                line = sprintf('    %s', entry.NewName);
            else
                line = sprintf('    %s %s %s', entry.OldName, char(8594), entry.NewName);
            end
    end
end


function lines = localCapped_(lines)
% Keep a long list from running the alert off the screen.
    MAX_LINES = 15;
    lines = reshape(lines, 1, []);
    if numel(lines) > MAX_LINES
        lines = [lines(1:MAX_LINES), {sprintf('    ...and %d more', numel(lines) - MAX_LINES)}];
    end
end
