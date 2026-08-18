function fromStruct(obj, struct_in)
    % fromStruct(obj, struct_in)
    %
    % Restore protocol state from struct (inverse of toStruct).
    % Called by load().
    %
    % Parameters:
    %   obj - epsych.Protocol instance to populate
    %   struct_in - Struct with serialized protocol data
    
    arguments
        obj
        struct_in struct
    end

    % Restore options and info
    if isfield(struct_in, 'Options')
        obj.Options = struct_in.Options;
    end
    
    if isfield(struct_in, 'Info')
        obj.Info = struct_in.Info;
    end
    
    if isfield(struct_in, 'COMPILED')
        compiled = struct_in.COMPILED;
        % parameters holds hw.Parameter handles; not serialized — reset to empty
        compiled.parameters = [];
        obj.COMPILED = compiled;
    end
    
    % Restore metadata
    if isfield(struct_in, 'formatVersion')
        obj.meta.formatVersion = struct_in.formatVersion;
    end
    if isfield(struct_in, 'epsychVersion')
        obj.meta.epsychVersion = struct_in.epsychVersion;
    end
    if isfield(struct_in, 'createdDate')
        obj.meta.createdDate = struct_in.createdDate;
    end
    if isfield(struct_in, 'lastModified')
        obj.meta.lastModified = struct_in.lastModified;
    end
    if isfield(struct_in, 'protocolVersion')
        obj.meta.protocolVersion = struct_in.protocolVersion;
    end
    
    % Restore interfaces
    obj.Interfaces = hw.Interface.empty();
    obj.SoftwareModule = hw.Software();

    if isfield(struct_in, 'InterfaceData') && ~isempty(struct_in.InterfaceData)
        pendingParams = hw.Parameter.empty(1, 0);
        pendingStructs = {};
        for ifaceIdx = 1:length(struct_in.InterfaceData)
            ifaceStruct = struct_in.InterfaceData{ifaceIdx};
            if isempty(ifaceStruct)
                continue
            end
            [restoredInterface, ifaceParams, ifaceStructs] = obj.createInterfaceFromStruct_(ifaceStruct);
            obj.Interfaces(end + 1) = restoredInterface;
            if isa(restoredInterface, 'hw.Software')
                obj.SoftwareModule = restoredInterface;
            end
            pendingParams = [pendingParams, ifaceParams];
            pendingStructs = [pendingStructs, ifaceStructs];
        end

        % Restore parameter Values only after every interface, module, and
        % parameter exists. Value assignment evaluates each parameter's
        % Expression, which may reference parameters on *other* interfaces
        % (e.g. "RespWinDelay = StimDelay + StimDur - Params.RespWinPreStim"
        % where the parameters live on different hardware interfaces), so the
        % restore pass runs with this Protocol standing in as the interfaces'
        % Runtime.
        restoreLink = obj.linkInterfacesForValueRestore();
        localRestoreValues(pendingParams, pendingStructs);
        delete(restoreLink)

        vprintf(3, 'Protocol loaded with %d interface(s): ', length(obj.Interfaces))
        for ifaceIdx = 1:length(obj.Interfaces)
            vprintf(3, '\t%d. %s', ifaceIdx, class(obj.Interfaces(ifaceIdx)));
        end

    elseif isfield(obj.COMPILED, 'writeparams') && ~isempty(obj.COMPILED.writeparams)
        recoveredInterface = obj.createRecoveredInterfaceFromCompiled_();
        obj.Interfaces = recoveredInterface;
        if isa(recoveredInterface, 'hw.Software')
            obj.SoftwareModule = recoveredInterface;
        end
        vprintf(3, 'Protocol interfaces recovered from compiled data');
    else
        obj.Interfaces = obj.SoftwareModule;
    end

    % Rebuild COMPILED.parameters from restored interfaces when serialized
    % data omitted handle objects.
    if isfield(obj.COMPILED, 'writeparams') && ~isempty(obj.COMPILED.writeparams)
        if ~isfield(obj.COMPILED, 'parameters') || isempty(obj.COMPILED.parameters)
            obj.COMPILED.parameters = obj.resolveCompiledParameters_();
        end
    end
end


function localRestoreValues(params, structs)
    % Restore parameter Values, tolerating dependency order. A parameter's
    % Expression may reference other parameters (siblings, other modules, or
    % other interfaces) that are restored later, so re-evaluate the
    % expression-bearing parameters until their Values stop changing. Plain
    % parameters (and StimType parameters without an expression) are restored
    % once. The pass count is bounded by the number of parameters, so
    % evaluation terminates even if expressions form a cycle.
    isExprDeferred = arrayfun(@(p) strlength(p.Expression) > 0 ...
        && (~isequal(p.Type, 'StimType') || hw.Parameter.expressionSelectsIndex(p.Type)), params);

    % First pass restores every parameter once, making leaf values available.
    % An expression that reads a not-yet-restored parameter can fail outright
    % here — an index-selecting expression rejects the empty result rather
    % than storing it — so defer those failures to the passes below instead of
    % aborting the load.
    for k = 1:numel(params)
        if isExprDeferred(k)
            try
                params(k).fromStruct(structs{k});
            catch
            end
        else
            params(k).fromStruct(structs{k});
        end
    end

    % Subsequent passes re-evaluate only expression parameters until stable.
    exprIdx = reshape(find(isExprDeferred), 1, []);
    lastError = [];
    for pass = 2:max(2, numel(exprIdx))
        changed = false;
        for k = exprIdx
            % A write-only parameter cannot be probed for convergence:
            % get.Value logs a critical record and returns NaN, which is
            % never isequal to itself, so it would both spam the log and
            % defeat the early exit. Its inputs are the other expression
            % parameters, so it has settled whenever they all have.
            isProbeable = ~isequal(params(k).Access, 'Write');
            if isProbeable
                before = params(k).Value;
            end
            try
                params(k).fromStruct(structs{k});
            catch ME
                lastError = ME;
                continue
            end
            if isProbeable && ~isequal(before, params(k).Value)
                changed = true;
            end
        end
        if ~changed
            break
        end
    end

    % A still-failing expression is a protocol defect, not a load failure:
    % report it and leave validate() / Check Calculations to explain it.
    if ~isempty(lastError)
        vprintf(0, 1, 'Could not evaluate every parameter expression while loading: %s', lastError.message);
    end
end
