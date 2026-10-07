function plan = planParameterTransfer(obj, parameters, targetModule, options)
% plan = planParameterTransfer(obj, parameters, targetModule, Mode=, OnConflict=)
% Work out what copying or moving parameters into a module would do, without
% touching the protocol. The Copy / Move Parameters dialog previews this plan
% and then hands it to applyParameterTransfer.
%
% The target may be another module on the same interface, a module on a
% different interface, or (for a copy) the parameters' own module.
%
% Expressions are rewritten so that every reference keeps naming the parameter
% it names now, because hw.Parameter.resolveExpressionContext reads a bare name
% as a sibling in the owner's module and Module.Parameter by module name:
%	- A reference to another parameter in the same transfer follows it to its
%	  new module and name, so a group copied together stays wired together.
%	- A bare sibling name that would stop being a sibling is qualified as
%	  Module.Parameter, so a copy elsewhere still reads the original.
%	- On a move, expressions elsewhere in the protocol that named a moved
%	  parameter are repointed at its new home; those are listed in Rewrites.
% A copy changes nothing outside the new parameters.
%
% Names follow two rules. A clash inside the target module is the caller's
% choice (OnConflict). A name used anywhere else in the protocol is always
% renamed, because epsych.Protocol.compile refuses duplicate parameter names
% across the whole protocol -- which means a copy into another module is
% always renamed, since its original keeps the name. A move frees the names it
% takes away, so a moved parameter keeps its name wherever it can.
%
% Renaming must not change which device tag a hardware parameter addresses,
% so on a target interface other than hw.Software each entry records its tag
% in HardwareName, which applyParameterTransfer stores as
% UserData.HardwareName (read by hw.Interface.getHardwareParameterName) when it
% differs from the new name. An overwrite keeps the existing parameter's tag.
%
% Parameters:
%	parameters	- hw.Parameter array to copy or move; may span modules.
%	targetModule	- hw.Module in this protocol that receives them.
%	options.Mode	- 'copy' (default) or 'move'.
%	options.OnConflict	- When the target module already has a parameter
%			  of the same name: 'rename' (default; the new one becomes
%			  Name_1, Name_2, ...), 'overwrite' (the existing parameter
%			  takes the source's settings and keeps its handle, so its
%			  own references survive), or 'skip'.
%
% Returns:
%	plan	- Scalar struct:
%		.Mode, .OnConflict, .TargetModule, .TargetLocation
%		.Entries	One row per parameter: Parameter, SourceModule,
%				SourceLocation, OldName, NewName, Status ('copy',
%				'move', 'overwrite', or 'skip'), Existing (the
%				parameter an overwrite replaces, else []),
%				HardwareName (device tag on a hardware target, else
%				''), OldExpression, NewExpression, Message.
%		.Rewrites	Other parameters whose expressions a move updates:
%				Parameter, Location, OldExpression, NewExpression.
%		.Warnings	cellstr of cautions that apply to the whole plan.
%
% Example:
%	plan = designer.planParameterTransfer([pA pB], targetModule, Mode='move');
%	designer.applyParameterTransfer(plan);
%
% See also: applyParameterTransfer, onCopyMoveParameters
    arguments
        obj
        parameters hw.Parameter
        targetModule (1,1) hw.Module
        options.Mode (1,:) char {mustBeMember(options.Mode, {'copy', 'move'})} = 'copy'
        options.OnConflict (1,:) char {mustBeMember(options.OnConflict, {'rename', 'overwrite', 'skip'})} = 'rename'
    end

    [modules, labels] = obj.getModuleChoices();
    targetIdx = find(modules == targetModule, 1);
    if isempty(targetIdx)
        error('epsych:ProtocolDesigner:ModuleNotInProtocol', ...
            'Target module %s is not part of this protocol.', targetModule.Name);
    end

    entries = struct('Parameter', {}, 'SourceModule', {}, 'SourceLocation', {}, ...
        'OldName', {}, 'NewName', {}, 'Status', {}, 'Existing', {}, 'HardwareName', {}, ...
        'OldExpression', {}, 'NewExpression', {}, 'Message', {});
    rewrites = struct('Parameter', {}, 'Location', {}, 'OldExpression', {}, 'NewExpression', {});
    warnings = {};

    parameters = localUniqueHandles_(reshape(parameters, 1, []));
    isMove = strcmp(options.Mode, 'move');
    targetIsHardware = ~isa(targetModule.parent, 'hw.Software');
    allParams = obj.getAllParameters();

    % Names in the target module (the only ones an overwrite can replace), names
    % used anywhere else (always renamed around; a move frees its own), and
    % names this plan has already handed out.
    existingNames = arrayfun(@(p) p.Name, targetModule.Parameters, 'UniformOutput', false);
    isElsewhere = arrayfun(@(p) p.Module ~= targetModule, allParams);
    if isMove
        isElsewhere = isElsewhere & ~arrayfun(@(p) any(parameters == p), allParams);
    end
    elsewhereNames = arrayfun(@(p) p.Name, allParams(isElsewhere), 'UniformOutput', false);
    claimedNames = {};

    for k = 1:numel(parameters)
        parameter = parameters(k);
        sourceModule = parameter.Module;
        sourceIdx = [];
        if isa(sourceModule, 'hw.Module')
            sourceIdx = find(modules == sourceModule, 1);
        end
        if isempty(sourceIdx) || ~any(sourceModule.Parameters == parameter)
            error('epsych:ProtocolDesigner:ParameterNotInProtocol', ...
                'Parameter %s does not belong to a module of this protocol.', parameter.Name);
        end

        entry = struct( ...
            'Parameter', parameter, ...
            'SourceModule', sourceModule, ...
            'SourceLocation', labels{sourceIdx}, ...
            'OldName', parameter.Name, ...
            'NewName', '', ...
            'Status', 'skip', ...
            'Existing', [], ...
            'HardwareName', '', ...
            'OldExpression', obj.getParameterExpression(parameter), ...
            'NewExpression', '', ...
            'Message', '');

        takenNames = [existingNames, elsewhereNames, claimedNames];
        isExisting = strcmp(existingNames, parameter.Name);
        if isMove && sourceModule == targetModule
            entry.Message = 'Already in the target module.';
        elseif any(strcmp(claimedNames, parameter.Name))
            if strcmp(options.OnConflict, 'rename')
                entry.NewName = localUniqueName_(parameter.Name, takenNames);
                entry.Status = options.Mode;
                entry.Message = sprintf('Renamed: another selected parameter is already named %s.', parameter.Name);
            else
                entry.Message = sprintf('Another selected parameter is already named %s.', parameter.Name);
            end
        elseif any(isExisting)
            existing = targetModule.Parameters(find(isExisting, 1));
            switch options.OnConflict
                case 'rename'
                    entry.NewName = localUniqueName_(parameter.Name, takenNames);
                    entry.Status = options.Mode;
                    entry.Message = sprintf('Renamed: the target module already has %s.', parameter.Name);
                case 'overwrite'
                    if existing == parameter
                        entry.Message = 'A parameter cannot overwrite itself.';
                    else
                        entry.NewName = parameter.Name;
                        entry.Status = 'overwrite';
                        entry.Existing = existing;
                        entry.Message = sprintf('Replaces the settings of the existing %s.', parameter.Name);
                    end
                otherwise
                    entry.Message = sprintf('The target module already has %s.', parameter.Name);
            end
        elseif any(strcmp(elsewhereNames, parameter.Name))
            entry.NewName = localUniqueName_(parameter.Name, takenNames);
            entry.Status = options.Mode;
            entry.Message = sprintf(['Renamed: %s is already used elsewhere in the protocol, ' ...
                'and parameter names must be unique across it to compile.'], parameter.Name);
        else
            entry.NewName = parameter.Name;
            entry.Status = options.Mode;
        end

        if ~strcmp(entry.Status, 'skip')
            claimedNames{end + 1} = entry.NewName;
            if targetIsHardware
                entry = localAssignHardwareName_(entry, targetModule);
            end
        end
        entries(end + 1) = entry;
    end

    % Where each transferred parameter will live, for the reference rewrites.
    ctx.AllParams = allParams;
    ctx.TransferParams = hw.Parameter.empty(1, 0);
    ctx.TransferNames = {};
    for k = 1:numel(entries)
        if ~strcmp(entries(k).Status, 'skip')
            ctx.TransferParams(end + 1) = entries(k).Parameter;
            ctx.TransferNames{end + 1} = entries(k).NewName;
        end
    end
    ctx.TargetModule = targetModule;

    qualifiedTo = hw.Module.empty(1, 0);
    for k = 1:numel(entries)
        entry = entries(k);
        if strcmp(entry.Status, 'skip')
            entries(k).NewExpression = entry.OldExpression;
            continue
        end

        [newText, notes, usedModules] = localRewrite_(entry.OldExpression, ...
            entry.Parameter, entry.SourceModule, targetModule, ctx);
        qualifiedTo = [qualifiedTo, usedModules];
        entries(k).NewExpression = newText;

        if ~isempty(entry.Message)
            notes = [{entry.Message}, notes];
        end
        if ~strcmp(newText, entry.OldExpression)
            notes{end + 1} = sprintf('Expression becomes %s.', newText);
        end
        if strcmp(entry.Status, 'copy')
            notes = [notes, localRovingNotes_(entry.Parameter, ...
                obj.getParameterPair(entry.Parameter), ~isempty(entry.OldExpression))];
        end
        entries(k).Message = strjoin(notes, ' ');
    end

    % A move takes parameters out from under every expression that named them.
    if isMove && ~isempty(ctx.TransferParams)
        for moduleIdx = 1:numel(modules)
            module = modules(moduleIdx);
            for paramIdx = 1:numel(module.Parameters)
                parameter = module.Parameters(paramIdx);
                if any(ctx.TransferParams == parameter)
                    continue
                end
                expressionText = obj.getParameterExpression(parameter);
                if isempty(expressionText)
                    continue
                end

                [newText, notes, usedModules] = localRewrite_(expressionText, ...
                    parameter, module, module, ctx);
                warnings = [warnings, notes];
                if strcmp(newText, expressionText)
                    continue
                end
                qualifiedTo = [qualifiedTo, usedModules];
                rewrites(end + 1) = struct( ...
                    'Parameter', parameter, ...
                    'Location', labels{moduleIdx}, ...
                    'OldExpression', expressionText, ...
                    'NewExpression', newText);
            end
        end
    end

    % Module.Parameter resolves to the first module with that name, and module
    % names are unique only within an interface.
    moduleNames = arrayfun(@(m) m.Name, modules, 'UniformOutput', false);
    for module = localUniqueHandles_(qualifiedTo)
        if sum(strcmp(moduleNames, module.Name)) > 1
            warnings{end + 1} = sprintf(['More than one interface has a module named %s; ' ...
                'a %s.Parameter reference resolves to the first of them.'], module.Name, module.Name);
        end
    end

    plan = struct( ...
        'Mode', options.Mode, ...
        'OnConflict', options.OnConflict, ...
        'TargetModule', targetModule, ...
        'TargetLocation', labels{targetIdx}, ...
        'Entries', entries, ...
        'Rewrites', rewrites, ...
        'Warnings', {unique(warnings, 'stable')});
end


function [newText, notes, qualifiedTo] = localRewrite_(text, owner, oldModule, newModule, ctx)
% Rewrite one expression so each reference names, after the transfer, the
% parameter it names now. The owner lives in oldModule today and in newModule
% afterwards (the same module for an expression the transfer only affects).
%
% Recognition mirrors hw.Parameter.resolveExpressionContext pass for pass:
% Module.Param.Prop, then sibling Param.Prop, then Module.Param, then a bare
% sibling name.
    newText = text;
    notes = {};
    qualifiedTo = hw.Module.empty(1, 0);
    if isempty(text)
        return
    end

    siblings = oldModule.Parameters(oldModule.Parameters ~= owner);
    siblingNames = arrayfun(@(p) matlab.lang.makeValidName(p.Name), siblings, 'UniformOutput', false);

    % Dotted identifier chains, handled right to left so earlier offsets hold.
    [chains, starts] = regexp(text, '(?<![\w.])[A-Za-z]\w*(\.[A-Za-z]\w*)*', 'match', 'start');
    for k = numel(chains):-1:1
        parts = strsplit(chains{k}, '.');
        [referenced, consumed, isBare] = localResolve_(parts, siblings, siblingNames, ctx.AllParams);
        if isempty(referenced)
            continue
        end

        [destModule, destName] = localDestination_(referenced, ctx);
        if isBare && destModule == newModule
            replacement = matlab.lang.makeValidName(destName);
        elseif ~isBare && destModule == referenced.Module && strcmp(destName, referenced.Name)
            continue  % an explicit reference to something that stays put
        elseif localIsIdentifier_(destModule.Name) && localIsIdentifier_(destName)
            replacement = [destModule.Name '.' destName];
            qualifiedTo(end + 1) = destModule;
        else
            notes{end + 1} = sprintf(['%s.%s cannot be written as a Module.Parameter reference; ' ...
                'check the expression of %s.'], destModule.Name, destName, owner.Name);
            continue
        end

        original = strjoin(parts(1:consumed), '.');
        if ~strcmp(replacement, original)
            newText = [newText(1:starts(k) - 1), replacement, newText(starts(k) + numel(original):end)];
        end
    end
end


function [referenced, consumed, isBare] = localResolve_(parts, siblings, siblingNames, allParams)
% Identify the parameter a dotted chain names, and how many of its parts name it.
    ALLOWED_PROPS = {'Min', 'Max', 'Values', 'Value'};
    referenced = [];
    consumed = 0;
    isBare = false;

    if numel(parts) >= 3 && ismember(parts{3}, ALLOWED_PROPS)
        referenced = localQualified_(parts{1}, parts{2}, allParams);
        if ~isempty(referenced)
            consumed = 2;
            return
        end
    end

    siblingIdx = find(strcmp(siblingNames, parts{1}), 1);
    if numel(parts) >= 2 && ismember(parts{2}, ALLOWED_PROPS) && ~isempty(siblingIdx)
        referenced = siblings(siblingIdx);
        consumed = 1;
        isBare = true;
        return
    end

    if numel(parts) >= 2
        referenced = localQualified_(parts{1}, parts{2}, allParams);
        if ~isempty(referenced)
            consumed = 2;
            return
        end
    end

    if ~isempty(siblingIdx)
        referenced = siblings(siblingIdx);
        consumed = 1;
        isBare = true;
    end
end


function parameter = localQualified_(moduleName, paramName, allParams)
% First parameter matching Module.Param, as the runtime resolver chooses.
    parameter = [];
    for idx = 1:numel(allParams)
        if strcmp(allParams(idx).Module.Name, moduleName) && strcmp(allParams(idx).Name, paramName)
            parameter = allParams(idx);
            return
        end
    end
end


function [destModule, destName] = localDestination_(parameter, ctx)
% Module and name a parameter will have once the transfer is applied.
    idx = find(ctx.TransferParams == parameter, 1);
    if isempty(idx)
        destModule = parameter.Module;
        destName = parameter.Name;
    else
        destModule = ctx.TargetModule;
        destName = ctx.TransferNames{idx};
    end
end


function notes = localRovingNotes_(parameter, pairName, hasExpression)
% Warn when a copy changes the trial count, since that is easy to miss.
    notes = {};
    levelCount = numel(parameter.Values);
    if levelCount < 2 || strcmp(parameter.Access, 'Read')
        return
    end
    if hw.Parameter.expressionSelectsIndex(parameter.Type) && hasExpression
        return  % Values is a lookup table here, not a set of trial levels
    end

    if isempty(pairName)
        notes{end + 1} = sprintf(['Roves over %d values with no Pair, so the copy multiplies the ' ...
            'trial count by %d; give both the same Pair to vary them together.'], levelCount, levelCount);
    else
        notes{end + 1} = sprintf('Shares Pair %s with the original, so the two vary together.', pairName);
    end
end


function entry = localAssignHardwareName_(entry, targetModule)
% Record the device tag the transferred parameter must keep addressing: the
% source's tag for a copy or move, the existing parameter's for an overwrite.
    if strcmp(entry.Status, 'overwrite')
        entry.HardwareName = hw.Interface.getHardwareParameterName(entry.Existing);
    else
        entry.HardwareName = hw.Interface.getHardwareParameterName(entry.Parameter);
    end

    notes = {};
    if ~isempty(entry.Message)
        notes{end + 1} = entry.Message;
    end
    if ~strcmp(entry.HardwareName, entry.NewName)
        notes{end + 1} = sprintf('Addresses device tag %s.', entry.HardwareName);
    end

    % Two parameters on one module writing one tag is rarely what was meant.
    others = targetModule.Parameters;
    others = others(others ~= entry.Parameter);
    if ~isempty(entry.Existing)
        others = others(others ~= entry.Existing);
    end
    sharing = others(arrayfun(@(p) strcmp(hw.Interface.getHardwareParameterName(p), entry.HardwareName), others));
    if ~isempty(sharing)
        notes{end + 1} = sprintf(['%s in the target module already addresses device tag %s; ' ...
            'Overwrite may be what you want.'], sharing(1).Name, entry.HardwareName);
    end
    entry.Message = strjoin(notes, ' ');
end


function name = localUniqueName_(baseName, takenNames)
% Same suffix scheme as getUniqueParameterName: Name_1, Name_2, ...
    name = baseName;
    suffix = 1;
    while any(strcmp(name, takenNames))
        name = sprintf('%s_%d', baseName, suffix);
        suffix = suffix + 1;
    end
end


function tf = localIsIdentifier_(text)
    tf = ~isempty(regexp(text, '^[A-Za-z]\w*$', 'once'));
end


function handles = localUniqueHandles_(handles)
% Drop repeated handles, keeping first-seen order.
    keep = true(size(handles));
    for k = 2:numel(handles)
        keep(k) = ~any(handles(1:k - 1) == handles(k));
    end
    handles = handles(keep);
end
