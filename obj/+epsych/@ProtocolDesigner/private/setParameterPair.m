function setParameterPair(~, parameter, pairName)
    pairName = strtrim(char(string(pairName)));
    userData = parameter.UserData;
    if isempty(userData) || ~isstruct(userData)
        userData = struct();
    end

    if isfield(userData, 'Buddy')
        userData = rmfield(userData, 'Buddy');
    end

    if isempty(pairName)
        if isfield(userData, 'Pair')
            userData = rmfield(userData, 'Pair');
        end
    else
        userData.Pair = pairName;
    end

    parameter.UserData = userData;
end