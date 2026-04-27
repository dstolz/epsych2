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
        obj.COMPILED = struct_in.COMPILED;
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
    
    % Restore interfaces
    obj.Interfaces = hw.Interface.empty();
    obj.SoftwareModule = hw.Software();

    if isfield(struct_in, 'InterfaceData') && ~isempty(struct_in.InterfaceData)
        for ifaceIdx = 1:length(struct_in.InterfaceData)
            ifaceStruct = struct_in.InterfaceData{ifaceIdx};
            if isempty(ifaceStruct)
                continue
            end
            restoredInterface = obj.createInterfaceFromStruct_(ifaceStruct);
            obj.Interfaces(end + 1) = restoredInterface;
            if isa(restoredInterface, 'hw.Software')
                obj.SoftwareModule = restoredInterface;
            end
        end
        vprintf(3, 'Protocol loaded with %d interface(s)', length(obj.Interfaces));
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
end
