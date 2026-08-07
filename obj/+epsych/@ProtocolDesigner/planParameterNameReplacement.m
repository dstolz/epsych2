function changes = planParameterNameReplacement(obj, findText, replaceText, options)
% changes = planParameterNameReplacement(obj, findText, replaceText, options)
% Work out what a find and replace over parameter names would do, without
% touching the protocol. The Find and Replace dialog previews this plan and then
% hands it to applyParameterNameReplacement.
%
% Names that the replacement leaves unchanged are omitted, so an empty result
% means nothing matched.
%
% Parameters:
%	findText	- Text to search for inside each parameter name.
%	replaceText	- Replacement text (default: '', which deletes the match).
%	options.MatchCase	- Compare case-sensitively (default: false).
%	options.WholeName	- Replace only when the whole name equals findText,
%				  rather than every substring occurrence (default: false).
%	options.Scope		- 'all', 'shown', or 'selected' (default: 'all').
%				  See getReplacementCandidates.
%
% Returns:
%	changes	- Struct array with fields Parameter, Module, Location, OldName,
%		  NewName, Status, and Message. Status is 'rename' when the change
%		  is safe to apply, 'conflict' when the new name is already taken in
%		  that module, or 'invalid' when the new name is unusable.
%
% Example:
%	changes = designer.planParameterNameReplacement('Tone', 'Target');
%	designer.applyParameterNameReplacement(changes);
    arguments
        obj
        findText {mustBeTextScalar}
        replaceText {mustBeTextScalar} = ''
        options.MatchCase (1,1) logical = false
        options.WholeName (1,1) logical = false
        options.Scope (1,:) char {mustBeMember(options.Scope, {'all', 'shown', 'selected'})} = 'all'
    end

    changes = struct('Parameter', {}, 'Module', {}, 'Location', {}, ...
        'OldName', {}, 'NewName', {}, 'Status', {}, 'Message', {});

    findText = char(findText);
    replaceText = char(replaceText);
    if isempty(findText)
        return
    end

    candidates = obj.getReplacementCandidates(options.Scope);
    if isempty(candidates)
        return
    end

    % Names already taken in each affected module, updated as the plan is built so
    % that two renames colliding with each other are reported rather than applied.
    takenNames = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for idx = 1:numel(candidates)
        moduleKey = candidates(idx).ModuleKey;
        if ~isKey(takenNames, moduleKey)
            takenNames(moduleKey) = {candidates(idx).Module.Parameters.Name};
        end
    end

    for idx = 1:numel(candidates)
        parameter = candidates(idx).Parameter;
        oldName = parameter.Name;
        newName = obj.replaceInParameterName(oldName, findText, replaceText, ...
            options.MatchCase, options.WholeName);
        newName = strtrim(newName);
        if strcmp(newName, oldName)
            continue
        end

        moduleKey = candidates(idx).ModuleKey;
        moduleNames = takenNames(moduleKey);
        otherNames = moduleNames(~strcmp(moduleNames, oldName));

        if isempty(newName)
            status = 'invalid';
            message = 'Parameter name cannot be empty.';
        elseif any(strcmp(otherNames, newName))
            status = 'conflict';
            message = sprintf('Module %s already has a parameter named %s.', ...
                candidates(idx).Module.Name, newName);
        else
            status = 'rename';
            message = '';
            moduleNames(strcmp(moduleNames, oldName)) = {newName};
            takenNames(moduleKey) = moduleNames;
        end

        changes(end + 1) = struct( ...
            'Parameter', parameter, ...
            'Module', candidates(idx).Module, ...
            'Location', candidates(idx).Location, ...
            'OldName', oldName, ...
            'NewName', newName, ...
            'Status', status, ...
            'Message', message); %#ok<AGROW>
    end
end
