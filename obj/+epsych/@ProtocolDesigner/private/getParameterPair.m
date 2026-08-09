function pairName = getParameterPair(~, parameter)
    pairName = '';
    userData = parameter.UserData;
    if ~isstruct(userData)
        return
    end

    if isfield(userData, 'Pair') && ~isempty(userData.Pair)
        pairName = strtrim(char(string(userData.Pair)));
    elseif isfield(userData, 'Buddy') && ~isempty(userData.Buddy)
        pairName = strtrim(char(string(userData.Buddy)));
    end
end