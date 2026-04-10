function refreshCompiledPreview(obj)
    if isempty(obj.TableCompiled) || ~isvalid(obj.TableCompiled) || isempty(obj.LabelCompileSummary) || ~isvalid(obj.LabelCompileSummary)
        return
    end

    writeParams = obj.Protocol.COMPILED.writeparams;
    trials = obj.Protocol.COMPILED.trials;

    if isempty(writeParams)
        obj.TableCompiled.ColumnName = {'No Compiled Trials'};
        obj.TableCompiled.Data = cell(0, 1);
        obj.LabelCompileSummary.Text = 'Not compiled';
        return
    end

    previewCount = min(size(trials, 1), 200);
    writeParamTypes = obj.getCompiledWriteParamTypes(writeParams);
    previewData = obj.normalizeCompiledPreviewData(trials(1:previewCount, :), writeParamTypes);
    obj.TableCompiled.ColumnName = cellstr(string(writeParams));
    obj.TableCompiled.Data = previewData;
    obj.LabelCompileSummary.Text = sprintf('Showing %d of %d compiled trials', previewCount, obj.Protocol.COMPILED.ntrials);
end

