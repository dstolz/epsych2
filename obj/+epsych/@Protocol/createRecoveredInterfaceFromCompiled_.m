function interface = createRecoveredInterfaceFromCompiled_(obj)
% interface = createRecoveredInterfaceFromCompiled_(obj)
%
% Reconstruct an hw.Interface from COMPILED.writeparams and COMPILED.trials
% when InterfaceData is unavailable (legacy file recovery).
%
% Returns:
%   interface - Reconstructed hw.Interface instance (Software or TDT_RPcox)

writeparams = obj.COMPILED.writeparams;
trials = obj.COMPILED.trials;
hasModuleNames = any(contains(string(writeparams), '.'));

if hasModuleNames
    connectionType = 'GB';
    if isfield(obj.Options, 'ConnectionType') && ~isempty(obj.Options.ConnectionType)
        connectionType = char(string(obj.Options.ConnectionType));
    end
    interface = hw.TDT_RPcox({}, {}, {}, Interface = connectionType, Connect = false);
else
    interface = hw.Software();
end

moduleMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
modules = hw.Module.empty(1, 0);

for colIdx = 1:numel(writeparams)
    writeParamName = char(string(writeparams{colIdx}));
    if contains(writeParamName, '.')
        parts = split(string(writeParamName), '.');
        moduleName = char(parts(1));
        parameterName = char(parts(2));
    else
        moduleName = 'Params';
        parameterName = writeParamName;
    end

    if ~isKey(moduleMap, moduleName)
        module = hw.Module(interface, moduleName, moduleName, uint8(length(modules) + 1));
        modules(end + 1) = module; %#ok<AGROW>
        moduleMap(moduleName) = module;
    end
    module = moduleMap(moduleName);

    parameter = hw.Parameter(interface, Type = obj.inferSerializedParameterType_(trials, colIdx));
    parameter.Name = parameterName;
    parameter.Module = module;
    parameter.Value = obj.getRecoveredParameterValue_(trials, colIdx);
    parameter.Access = 'Any';
    parameter.Visible = true;
    parameter.isArray = numel(obj.normalizeRecoveredValue_(parameter.Value)) > 1;
    module.Parameters(end + 1) = parameter; %#ok<AGROW>
end

if isa(interface, 'hw.Software')
    interface.set_module(modules);
else
    interface.setModules(modules);
end
end
