function appliedCount = applyParameterNameReplacement(obj, changes)
% appliedCount = applyParameterNameReplacement(obj, changes)
% Apply the rename plan produced by planParameterNameReplacement.
%
% Entries whose Status is not 'rename' are skipped, so a plan containing
% conflicts can still be applied for the parts that are safe. Expressions that
% referenced a renamed parameter are rewritten as part of each rename.
%
% Parameters:
%	changes		- Struct array from planParameterNameReplacement.
%
% Returns:
%	appliedCount	- Number of parameters actually renamed.
    appliedCount = 0;

    for idx = 1:numel(changes)
        if ~strcmp(changes(idx).Status, 'rename')
            continue
        end

        obj.renameParameterInPlace(changes(idx).Parameter, changes(idx).Module, changes(idx).NewName);
        appliedCount = appliedCount + 1;
    end

    if appliedCount == 0
        return
    end

    obj.IsModified_ = true;
    obj.refreshExpressionValues();
    obj.refreshParameterTable();
end
