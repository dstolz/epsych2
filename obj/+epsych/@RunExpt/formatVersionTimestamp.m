function commitText = formatVersionTimestamp(~, commitTimestamp)
% commitText = formatVersionTimestamp(self, commitTimestamp)
% Format the latest commit timestamp for display in the version info dialog.
if isdatetime(commitTimestamp)
    if isnat(commitTimestamp)
        commitText = 'Unavailable';
    else
        commitText = datestr(commitTimestamp,'ddd, mmm dd, yyyy HH:MM PM');
    end
    return
end

if ischar(commitTimestamp) || isstring(commitTimestamp)
    commitText = char(string(commitTimestamp));
    return
end

commitText = 'Unavailable';
end
