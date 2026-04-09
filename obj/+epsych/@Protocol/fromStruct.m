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
    
    % Restore interfaces from JSON data
    if isfield(struct_in, 'InterfaceData')
        for i = 1:length(struct_in.InterfaceData)
            ifdata = struct_in.InterfaceData{i};
            iface_type = ifdata.Type;
            
            % Reconstruct appropriate interface based on type
            % For now, skip interface reconstruction; assume interfaces
            % will be added separately or reconstructed elsewhere
            vprintf(3, 'Protocol loaded with %d interfaces', length(struct_in.InterfaceData));
        end
    end
end
