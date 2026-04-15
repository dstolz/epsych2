function struct_out = toStruct(obj)
    % struct_out = toStruct(obj)
    %
    % Convert protocol to a serializable struct. Called by save().
    %
    % Returns:
    %   struct_out - Struct with fields: Options, Info, COMPILED, meta, InterfaceData
    
    % Start with basic metadata
    struct_out = struct();
    struct_out.formatVersion = obj.meta.formatVersion;
    struct_out.epsychVersion = obj.meta.epsychVersion;
    struct_out.createdDate = datestr(now);
    struct_out.lastModified = datestr(now);
    
    % Protocol options and info
    struct_out.Options = obj.Options;
    struct_out.Info = obj.Info;
    struct_out.COMPILED = obj.COMPILED;
    
    % For now, serialize interfaces as a simple cell array
    struct_out.InterfaceCount = length(obj.Interfaces);
    struct_out.InterfaceData = {};
    
end
