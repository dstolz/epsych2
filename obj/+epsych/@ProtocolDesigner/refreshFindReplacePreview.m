function refreshFindReplacePreview(obj)
% refreshFindReplacePreview(obj)
% Recompute and display the rename plan shown in the Find and Replace dialog.
% Runs on every control change so the preview always matches the current inputs.
    if isempty(obj.FindReplaceFigure) || ~isvalid(obj.FindReplaceFigure)
        return
    end

    changes = obj.planParameterNameReplacement( ...
        obj.FindReplaceFind.Value, ...
        obj.FindReplaceWith.Value, ...
        MatchCase = obj.FindReplaceMatchCase.Value, ...
        WholeName = obj.FindReplaceWholeName.Value, ...
        Scope = obj.FindReplaceScope.Value);

    obj.FindReplaceChanges = changes;

    tableData = cell(numel(changes), 4);
    blockedRows = [];
    for idx = 1:numel(changes)
        switch changes(idx).Status
            case 'rename'
                statusText = 'Rename';
            case 'conflict'
                statusText = 'Name in use';
                blockedRows(end + 1) = idx; %#ok<AGROW>
            otherwise
                statusText = 'Invalid name';
                blockedRows(end + 1) = idx; %#ok<AGROW>
        end
        tableData(idx, :) = {changes(idx).Location, changes(idx).OldName, ...
            changes(idx).NewName, statusText};
    end
    obj.FindReplaceTable.Data = tableData;

    try
        removeStyle(obj.FindReplaceTable);
    catch
    end
    if ~isempty(blockedRows)
        blockedStyle = uistyle('BackgroundColor', [1.0 0.88 0.88], 'FontColor', [0.60 0.00 0.00]);
        addStyle(obj.FindReplaceTable, blockedStyle, 'row', blockedRows);
    end

    renameCount = numel(changes) - numel(blockedRows);
    obj.FindReplaceApply.Enable = obj.onOffForCondition(renameCount > 0);

    if isempty(strtrim(obj.FindReplaceFind.Value))
        obj.FindReplaceSummary.Text = 'Enter text to find.';
    elseif isempty(changes)
        obj.FindReplaceSummary.Text = sprintf('No parameter name contains "%s".', ...
            obj.FindReplaceFind.Value);
    elseif isempty(blockedRows)
        obj.FindReplaceSummary.Text = sprintf('%d parameter(s) will be renamed.', renameCount);
    else
        obj.FindReplaceSummary.Text = sprintf( ...
            '%d parameter(s) will be renamed; %d cannot be (see the highlighted rows).', ...
            renameCount, numel(blockedRows));
    end
end
