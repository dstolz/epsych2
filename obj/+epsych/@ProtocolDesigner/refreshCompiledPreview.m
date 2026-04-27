function refreshCompiledPreview(obj)
    if isempty(obj.TableCompiled) || ~isvalid(obj.TableCompiled) || isempty(obj.LabelCompileSummary) || ~isvalid(obj.LabelCompileSummary)
        return
    end

    parameters = obj.Protocol.COMPILED.parameters;
    trials = obj.Protocol.COMPILED.trials;

    if isempty(parameters)
        obj.TableCompiled.ColumnName = {'No Compiled Trials'};
        obj.TableCompiled.Data = cell(0, 1);
        obj.LabelCompileSummary.Text = 'Not compiled';
        return
    end

    previewCount = min(size(trials, 1), 200);
    columnTypes = {parameters.Type};
    columnNames = {parameters.Name};
    previewData = obj.normalizeCompiledPreviewData(trials(1:previewCount, :), columnTypes);
    obj.TableCompiled.ColumnName = columnNames;
    obj.TableCompiled.Data = previewData;
    obj.LabelCompileSummary.Text = sprintf('Showing %d of %d compiled trials', previewCount, obj.Protocol.COMPILED.ntrials);
end

