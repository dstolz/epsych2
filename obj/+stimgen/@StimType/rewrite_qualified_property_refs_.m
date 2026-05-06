function expressionText = rewrite_qualified_property_refs_(obj, expressionText)
% rewrite_qualified_property_refs_(obj, expressionText)
% Replace ClassName.PropertyName tokens with bare PropertyName when
% PropertyName is a recognized property of this StimType.
mc = metaclass(obj);
validNames = {mc.PropertyList.Name};
[tokens, starts, ends_] = regexp(expressionText, ...
    '(?<!\.)\<([A-Za-z]\w*)\.([A-Za-z]\w*)\>', ...
    'tokens', 'start', 'end');
for k_ = numel(starts):-1:1
    propName = tokens{k_}{2};
    if ismember(propName, validNames)
        expressionText = [expressionText(1:starts(k_)-1), propName, expressionText(ends_(k_)+1:end)];
    end
end
end
