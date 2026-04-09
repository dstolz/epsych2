function numericValue = coerceNumericValue(~, rawValue, allowEmpty)
    if nargin < 3
        allowEmpty = false;
    end

    if isnumeric(rawValue) || islogical(rawValue)
        numericValue = double(rawValue);
        if isempty(numericValue) && ~allowEmpty
            numericValue = 0;
        end
        return
    end

    if isstring(rawValue)
        if isscalar(rawValue)
            rawValue = char(rawValue);
        else
            rawValue = cellstr(rawValue);
        end
    end

    if ischar(rawValue)
        numericValue = str2num(rawValue); %#ok<ST2NM>
        if isempty(numericValue)
            if allowEmpty
                numericValue = [];
            else
                numericValue = 0;
            end
        end
        return
    end

    if iscell(rawValue)
        numericParts = [];
        for idx = 1:numel(rawValue)
            itemValue = rawValue{idx};
            itemNumeric = [];
            if isnumeric(itemValue) || islogical(itemValue)
                itemNumeric = double(itemValue);
            elseif isstring(itemValue) || ischar(itemValue)
                itemNumeric = str2num(char(string(itemValue))); %#ok<ST2NM>
            end
            if isempty(itemNumeric)
                if allowEmpty
                    numericValue = [];
                else
                    numericValue = 0;
                end
                return
            end
            numericParts = [numericParts, itemNumeric(:).']; %#ok<AGROW>
        end
        numericValue = numericParts;
        if isempty(numericValue) && ~allowEmpty
            numericValue = 0;
        end
        return
    end

    if allowEmpty
        numericValue = [];
    else
        numericValue = 0;
    end
end

