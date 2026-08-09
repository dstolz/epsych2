function idx = parseIndexedLabel(~, label)
    tokens = regexp(label, '^(\d+):', 'tokens', 'once');
    if isempty(tokens)
        idx = 0;
    else
        idx = str2double(tokens{1});
    end
end

