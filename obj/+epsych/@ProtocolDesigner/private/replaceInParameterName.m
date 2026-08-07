function newName = replaceInParameterName(~, name, findText, replaceText, matchCase, wholeName)
% newName = replaceInParameterName(obj, name, findText, replaceText, matchCase, wholeName)
% Apply one find/replace to a single parameter name.
%
% Replacement is done with plain string operations rather than regexprep so that
% '$', '\', and other metacharacters in a parameter name are treated literally.
%
% Parameters:
%	name		- Current parameter name.
%	findText	- Text to look for.
%	replaceText	- Text to substitute.
%	matchCase	- True to compare case-sensitively.
%	wholeName	- True to substitute only when the entire name equals findText.
%
% Returns:
%	newName		- Resulting name, unchanged when nothing matched.
    newName = name;
    if isempty(findText)
        return
    end

    if wholeName
        if (matchCase && strcmp(name, findText)) || (~matchCase && strcmpi(name, findText))
            newName = replaceText;
        end
        return
    end

    if matchCase
        newName = strrep(name, findText, replaceText);
        return
    end

    % Case-insensitive substring replacement, walking the name left to right so
    % the replacement text is never rescanned for further matches.
    newName = '';
    remaining = name;
    lowerFind = lower(findText);
    while true
        matchStart = strfind(lower(remaining), lowerFind);
        if isempty(matchStart)
            break
        end

        matchStart = matchStart(1);
        newName = [newName, remaining(1:matchStart - 1), replaceText]; %#ok<AGROW>
        remaining = remaining(matchStart + numel(findText):end);
    end
    newName = [newName, remaining];
end
