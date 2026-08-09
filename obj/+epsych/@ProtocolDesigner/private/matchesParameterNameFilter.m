function tf = matchesParameterNameFilter(~, parameterName, moduleName, filterText)
% tf = matchesParameterNameFilter(obj, parameterName, moduleName, filterText)
% Test one parameter name against the Find box text.
%
% Matching is case-insensitive and substring-based so a partial name is enough.
% A filter containing '.' is matched against the qualified ModuleName.ParamName
% form, which is how expressions name cross-module parameters. When the filter
% contains '*' or '?' it becomes a whole-name wildcard match instead.
%
% Parameters:
%	parameterName	- Name of the parameter under test.
%	moduleName	- Name of the module owning the parameter.
%	filterText	- Active Find box text; empty matches everything.
%
% Returns:
%	tf		- True when the parameter should stay visible.
    filterText = strtrim(char(string(filterText)));
    tf = true;
    if isempty(filterText)
        return
    end

    parameterName = char(string(parameterName));
    if contains(filterText, '.')
        candidate = sprintf('%s.%s', char(string(moduleName)), parameterName);
    else
        candidate = parameterName;
    end

    if contains(filterText, '*') || contains(filterText, '?')
        pattern = ['^' regexptranslate('wildcard', filterText) '$'];
        tf = ~isempty(regexpi(candidate, pattern, 'once'));
        return
    end

    tf = contains(candidate, filterText, 'IgnoreCase', true);
end
