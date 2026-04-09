function columnTypes = getCompiledWriteParamTypes(obj, writeParams)
    columnTypes = repmat({''}, 1, numel(writeParams));
    for idx = 1:numel(writeParams)
        columnTypes{idx} = obj.getCompiledWriteParamType(writeParams{idx});
    end
end

