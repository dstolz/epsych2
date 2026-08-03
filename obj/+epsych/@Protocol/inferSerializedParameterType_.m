function parameterType = inferSerializedParameterType_(~, trials, colIdx)
parameterType = 'String';
if isempty(trials)
    return
end

sampleValue = trials{1, colIdx};
if isa(sampleValue, 'stimgen.StimType')
    parameterType = 'StimType';
elseif isstruct(sampleValue) && isfield(sampleValue, 'Class') && ...
        isConcreteStimType(string(sampleValue.Class))
    parameterType = 'StimType';
elseif islogical(sampleValue)
    parameterType = 'Boolean';
elseif isnumeric(sampleValue)
    if all(abs(sampleValue(:) - round(sampleValue(:))) < 1e-9)
        parameterType = 'Integer';
    else
        parameterType = 'Float';
    end
elseif ischar(sampleValue) || isstring(sampleValue)
    [~, fileName, extension] = fileparts(char(string(sampleValue)));
    if ~isempty(fileName) || ~isempty(extension)
        parameterType = 'File';
    end
elseif iscell(sampleValue)
    parameterType = 'File';
end
