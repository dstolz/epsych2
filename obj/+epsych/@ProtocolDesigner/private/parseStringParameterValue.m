function [value, isArrayValue] = parseStringParameterValue(~, rawValue)
    if isstring(rawValue)
        if ~isscalar(rawValue)
            [value, isArrayValue] = localFinalize_(cellstr(rawValue(:).'));
            return
        end
        rawValue = char(rawValue);
    end

    if ischar(rawValue)
        text = strtrim(rawValue);

        % Recognize a MATLAB-style list of quoted strings, optionally wrapped
        % in [] or {}, e.g. ["Stim","Catch"], {'a','b'}, or "a","b". Users
        % naturally type array literals here, so split them into discrete
        % values instead of storing the whole literal as one string.
        tokens = regexp(text, '(["''])(.*?)\1', 'tokens');
        residue = regexprep(text, '(["''])(.*?)\1', '');
        residue = regexprep(residue, '[\[\]{},;\s]', '');
        if ~isempty(tokens) && isempty(residue)
            parts = cellfun(@(t) t{2}, tokens, 'UniformOutput', false);
            parts = parts(~cellfun(@isempty, parts));
            [value, isArrayValue] = localFinalize_(parts);
            return
        end

        normalizedText = strrep(rawValue, sprintf('\r\n'), sprintf('\n'));
        normalizedText = strrep(normalizedText, sprintf('\r'), sprintf('\n'));
        parts = regexp(normalizedText, '\s*(?:;|\n)\s*', 'split');
        parts = parts(~cellfun(@isempty, parts));
        [value, isArrayValue] = localFinalize_(parts);
        return
    end

    if iscell(rawValue)
        values = cellfun(@(item) char(string(item)), rawValue(:).', 'UniformOutput', false);
        values = values(~cellfun(@isempty, values));
        [value, isArrayValue] = localFinalize_(values);
        return
    end

    value = char(string(rawValue));
    isArrayValue = false;
end

function [value, isArrayValue] = localFinalize_(parts)
    if isempty(parts)
        value = '';
        isArrayValue = false;
    elseif numel(parts) == 1
        value = parts{1};
        isArrayValue = false;
    else
        value = parts;
        isArrayValue = true;
    end
end
