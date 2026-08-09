function v = randomize_value(obj,value)
if ~obj.isRandom
    v = value;
    return
end

if isequal(obj.Type, 'StimType')
    if isempty(obj.Values)
        error('hw:Parameter:RandomStimTypeNeedsValues', ...
            'StimType parameter "%s" has isRandom=true but Values is empty.', obj.Name);
    end
    v = obj.Values{randi(numel(obj.Values))};
    vprintf(3,'Randomized StimType parameter "%s" to: %s', obj.Name, v.DisplayName)
    return
end

try
    v = randi([obj.Min obj.Max]);
    vprintf(3,'Randomized parameter "%s" to value: %g',obj.Name,v)
catch e
    vprintf(0,1,'Error randomizing parameter "%s": %s',obj.Name,getReport(e,'basic'))
end
