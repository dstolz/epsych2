function proceed = confirmDiscardChanges(obj)
% proceed = confirmDiscardChanges(obj)
% Prompt the user to save or discard unsaved changes before continuing.
% Returns true immediately when no unsaved changes exist.
% Selecting "Save Changes" invokes onSave; if the save is completed the
% function returns true, otherwise false (treating a cancelled save dialog
% as a cancel of the original action).
%
% Returns:
%   proceed - true if it is safe to continue, false to cancel.
    if ~obj.IsModified_
        proceed = true;
        return
    end

    answer = uiconfirm(obj.Figure, ...
        'The current protocol has unsaved changes.', ...
        'Unsaved Changes', ...
        'Options', {'Save Changes', 'Discard Changes', 'Cancel'}, ...
        'DefaultOption', 'Save Changes', ...
        'CancelOption', 'Cancel', ...
        'Icon', 'warning');

    switch answer
        case 'Save Changes'
            obj.onSave();
            % If the user cancelled the save dialog, IsModified_ is still
            % true, so treat that as a cancel of the original action.
            proceed = ~obj.IsModified_;
        case 'Discard Changes'
            proceed = true;
        otherwise
            proceed = false;
    end
end
