function refreshCompiledPreview(obj)
% refreshCompiledPreview(obj)
% Refresh the compiled trial preview table and summary label.
    if isempty(obj.TableCompiled) || ~isvalid(obj.TableCompiled) || isempty(obj.LabelCompileSummary) || ~isvalid(obj.LabelCompileSummary)
        return
    end

    parameters = obj.Protocol.COMPILED.parameters;
    trials = obj.Protocol.COMPILED.trials;

    if isempty(parameters)
        obj.TableCompiled.RowName = 'numbered';
        obj.TableCompiled.ColumnName = {'No Compiled Trials'};
        obj.TableCompiled.Data = cell(0, 1);
        obj.LabelCompileSummary.Text = 'Not compiled';
        return
    end

    previewCount = min(size(trials, 1), 200);
    [columnNames, ~, previewData] = obj.getCompiledPreviewTableData(previewCount);

    isTransposed = ~isempty(obj.CheckTransposePreview) && isvalid(obj.CheckTransposePreview) ...
        && obj.CheckTransposePreview.Value;
    if isTransposed
        obj.TableCompiled.RowName = columnNames;
        obj.TableCompiled.ColumnName = cellstr(compose('Trial %d', 1:previewCount));
        obj.TableCompiled.Data = previewData.';
    else
        obj.TableCompiled.RowName = 'numbered';
        obj.TableCompiled.ColumnName = columnNames;
        obj.TableCompiled.Data = previewData;
    end

    obj.LabelCompileSummary.Text = sprintf('Showing %d of %d compiled trials', previewCount, obj.Protocol.COMPILED.ntrials);
end

