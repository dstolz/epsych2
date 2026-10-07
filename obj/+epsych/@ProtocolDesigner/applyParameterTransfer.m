function [transferred, problems] = applyParameterTransfer(obj, plan)
% [transferred, problems] = applyParameterTransfer(obj, plan)
% Apply the copy or move plan produced by planParameterTransfer.
%
% Entries whose Status is 'skip' are left alone, so a plan with conflicts can
% still be applied for the parts that are safe.
%
% How each entry lands decides what survives of the original handle, because
% hw.Parameter.Parent (the interface) is immutable:
%	- A move within one interface re-homes the SAME handle into the target
%	  module, so anything holding it keeps working.
%	- A copy, or a move to another interface, builds a new parameter on the
%	  target interface from the source's toStruct; a move then removes the
%	  source from its module.
%	- An overwrite writes the source's settings onto the existing target
%	  parameter, keeping that handle and the expressions that name it.
% On a hardware target each entry's HardwareName becomes UserData.HardwareName
% when it differs from the new name (and is cleared when it does not), so a
% renamed copy still writes the device tag its source wrote.
% Values are restored after every parameter is in place, under
% epsych.Protocol.linkInterfacesForValueRestore, so an expression naming a
% parameter on another interface (or another parameter of the same transfer)
% resolves whatever order the entries are in.
%
% The plan is checked against the protocol before anything changes: a plan
% made before the protocol was edited throws epsych:ProtocolDesigner:StalePlan
% rather than half-applying.
%
% Parameters:
%	plan	- Struct from planParameterTransfer.
%
% Returns:
%	transferred	- hw.Parameter array now holding the transferred settings
%			  (new copies, moved handles, overwritten targets), in plan
%			  order.
%	problems	- cellstr, one sentence per transferred parameter that
%			  landed but is not right yet: a value that could not be
%			  restored, or an expression that does not evaluate in its
%			  new home. Empty when everything is clean.
%
% See also: planParameterTransfer, onCopyMoveParameters
    arguments
        obj
        plan (1,1) struct
    end

    transferred = hw.Parameter.empty(1, 0);
    problems = {};
    entries = plan.Entries(~strcmp({plan.Entries.Status}, 'skip'));
    if isempty(entries)
        return
    end

    localAssertCurrent_(obj, plan, entries);

    targetModule = plan.TargetModule;
    targetInterface = targetModule.parent;
    isMove = strcmp(plan.Mode, 'move');

    restoreParams = hw.Parameter.empty(1, 0);
    restoreStructs = {};
    for k = 1:numel(entries)
        entry = entries(k);
        source = entry.Parameter;
        S = source.toStruct();
        S.Name = entry.NewName;
        S.Expression = string(entry.NewExpression);
        S.UserData = localWithHardwareName_(S.UserData, entry);

        if strcmp(entry.Status, 'overwrite')
            destination = entry.Existing;
            destination.fromStruct(S, false);
            restoreParams(end + 1) = destination;
            restoreStructs{end + 1} = S;
        elseif isMove && source.Parent == targetInterface
            sourceModule = entry.SourceModule;
            sourceModule.Parameters = sourceModule.Parameters(sourceModule.Parameters ~= source);
            source.Name = entry.NewName;
            source.Expression = string(entry.NewExpression);
            source.UserData = S.UserData;
            source.Module = targetModule;
            targetModule.Parameters(end + 1) = source;
            destination = source;
        else
            destination = hw.Parameter(targetInterface);
            destination.Module = targetModule;
            destination.fromStruct(S, false);
            targetModule.Parameters(end + 1) = destination;
            restoreParams(end + 1) = destination;
            restoreStructs{end + 1} = S;
        end
        transferred(end + 1) = destination;
    end

    % Sources a move did not re-home leave their modules now that the copies exist.
    if isMove
        for k = 1:numel(entries)
            sourceModule = entries(k).SourceModule;
            source = entries(k).Parameter;
            if source.Module == sourceModule && any(sourceModule.Parameters == source)
                sourceModule.Parameters = sourceModule.Parameters(sourceModule.Parameters ~= source);
            end
        end
    end

    for k = 1:numel(plan.Rewrites)
        plan.Rewrites(k).Parameter.Expression = string(plan.Rewrites(k).NewExpression);
    end

    % A value that cannot be restored here (an expression the new home cannot
    % evaluate yet) is not fatal: refreshParameterTab re-evaluates and flags it.
    restoreLink = obj.Protocol.linkInterfacesForValueRestore();
    for k = 1:numel(restoreParams)
        try
            restoreParams(k).fromStruct(restoreStructs{k});
        catch ME
            vprintf(1, 'Transferred %s without restoring its value: %s', ...
                restoreParams(k).Name, ME.message);
            problems{end + 1} = sprintf('%s: value not restored (%s).', restoreParams(k).Name, ME.message);
        end
    end
    delete(restoreLink)

    obj.IsModified_ = true;
    for k = 1:numel(transferred)
        obj.ensureParameterNameVisible(transferred(k).Name, targetModule.Name);
    end
    obj.refreshParameterTab();

    % refreshParameterTab has re-evaluated every expression; report the ones
    % the transfer left unable to evaluate.
    for k = 1:numel(transferred)
        message = obj.getExpressionErrorMessage(transferred(k));
        if ~isempty(message)
            problems{end + 1} = message;
        end
    end
    for k = 1:numel(plan.Rewrites)
        message = obj.getExpressionErrorMessage(plan.Rewrites(k).Parameter);
        if ~isempty(message)
            problems{end + 1} = message;
        end
    end
end


function userData = localWithHardwareName_(userData, entry)
% Point UserData.HardwareName at the entry's device tag; a tag equal to the
% name is the default and is stored as no field at all.
    if isempty(entry.HardwareName)
        return
    end

    if strcmp(entry.HardwareName, entry.NewName)
        if isstruct(userData) && isfield(userData, 'HardwareName')
            userData = rmfield(userData, 'HardwareName');
            if isempty(fieldnames(userData))
                userData = [];
            end
        end
        return
    end

    if isempty(userData) || ~isstruct(userData)
        userData = struct();
    end
    userData.HardwareName = entry.HardwareName;
end


function localAssertCurrent_(obj, plan, entries)
% Refuse a plan whose parameters or modules have moved on since it was made.
    modules = obj.getModuleChoices();
    if ~any(modules == plan.TargetModule)
        localStale_('the target module is no longer part of the protocol');
    end

    % Names a copy or move may not land on: every parameter's except the
    % sources being transferred (a move frees its own name).
    allParams = obj.getAllParameters();
    sources = [entries.Parameter];
    otherNames = arrayfun(@(p) p.Name, allParams(~arrayfun(@(p) any(sources == p), allParams)), ...
        'UniformOutput', false);

    for k = 1:numel(entries)
        entry = entries(k);
        if ~any(modules == entry.SourceModule) ...
                || ~any(entry.SourceModule.Parameters == entry.Parameter)
            localStale_(sprintf('%s is no longer in %s', entry.OldName, entry.SourceModule.Name));
        end
        if ~strcmp(entry.Parameter.Name, entry.OldName)
            localStale_(sprintf('%s has been renamed', entry.OldName));
        end
        if strcmp(entry.Status, 'overwrite')
            if ~any(plan.TargetModule.Parameters == entry.Existing)
                localStale_(sprintf('the %s it would overwrite is gone', entry.NewName));
            end
        elseif any(strcmp(otherNames, entry.NewName))
            localStale_(sprintf('another parameter is now named %s', entry.NewName));
        end
        if ~strcmp(obj.getParameterExpression(entry.Parameter), entry.OldExpression)
            localStale_(sprintf('the expression of %s has changed', entry.OldName));
        end
    end

    for k = 1:numel(plan.Rewrites)
        if ~strcmp(obj.getParameterExpression(plan.Rewrites(k).Parameter), plan.Rewrites(k).OldExpression)
            localStale_(sprintf('the expression of %s has changed', plan.Rewrites(k).Parameter.Name));
        end
    end
end


function localStale_(reason)
    error('epsych:ProtocolDesigner:StalePlan', ...
        'The protocol changed after this copy/move was planned (%s). Review the preview and try again.', reason);
end
