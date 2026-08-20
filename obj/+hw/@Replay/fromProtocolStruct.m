function interfaces = fromProtocolStruct(protocolStruct, records)
% interfaces = hw.Replay.fromProtocolStruct(protocolStruct, records)
% Rebuild a protocol's parameter tree as read-only replay backends.
%
% One hw.Replay is created per serialized interface, so a parameter keeps the
% module it belonged to and a paradigm that reaches for a specific interface
% still finds one. Names are restored verbatim -- including the ~/! trigger
% prefixes and ~BoxID box suffixes -- because gui.BehaviorGUI.resolveParameter_
% matches on validName, and a renamed parameter would silently drop the control
% the paradigm asked for.
%
% Parameters:
%   protocolStruct - epsych.Protocol.toStruct() output, from a session snapshot.
%   records        - Saved DATA struct array for the session (optional).
%
% Returns:
%   interfaces - hw.Replay array, empty when the struct names no interfaces.
%
% See also: hw.Replay, epsych.SessionSnapshot, epsych.ReviewSession,
%           epsych.Protocol.createInterfaceFromStruct_

arguments
    protocolStruct (1,1) struct
    records struct = struct.empty(1,0)
end

interfaces = hw.Replay.empty(1,0);

if ~isfield(protocolStruct, 'InterfaceData') || isempty(protocolStruct.InterfaceData)
    vprintf(1, 'hw.Replay: the snapshot names no interfaces; the review has no parameters')
    return
end

ifaceData = protocolStruct.InterfaceData;
if ~iscell(ifaceData), ifaceData = num2cell(ifaceData); end

for i = 1:numel(ifaceData)
    try
        interfaces(end+1) = localBuildOne(ifaceData{i}, records);
    catch ME
        % One unreadable interface must not cost the operator the whole
        % review: the displays that read DATA work regardless, and the
        % parameters of every other interface still resolve.
        vprintf(0, 1, ME)
        vprintf(0, 1, 'hw.Replay: skipping interface %d of the snapshot; its controls will be absent', i)
    end
end

end




function iface = localBuildOne(ifaceStruct, records)
% iface = localBuildOne(ifaceStruct, records)
%
% One hw.Replay carrying the modules and parameters of one serialized
% interface. Mirrors epsych.Protocol.createInterfaceFromStruct_'s module loop,
% but every interface becomes an hw.Replay rather than its original backend --
% a review must not construct a TDT or serial object, and a disconnected real
% backend would answer reads with its design-time value rather than the trial's.

iface = hw.Replay(records);

% Label the replay after what it stands in for, so a monitor or the parameter
% debugger still shows which rig component a parameter came from.
if isfield(ifaceStruct, 'Type') && ~isempty(ifaceStruct.Type)
    sourceType = char(string(ifaceStruct.Type));
else
    sourceType = 'Unknown';
end

modules = hw.Module.empty(1, 0);

if ~isfield(ifaceStruct, 'Modules') || isempty(ifaceStruct.Modules)
    return
end

moduleList = ifaceStruct.Modules;
if ~iscell(moduleList), moduleList = num2cell(moduleList); end

for moduleIdx = 1:numel(moduleList)
    moduleStruct = moduleList{moduleIdx};

    module = hw.Module(iface, char(moduleStruct.Label), char(moduleStruct.Name), ...
        uint8(moduleStruct.Index));
    if isfield(moduleStruct, 'Fs') && ~isempty(moduleStruct.Fs)
        module.Fs = double(moduleStruct.Fs);
    end
    if isfield(moduleStruct, 'Info') && isstruct(moduleStruct.Info)
        module.Info = moduleStruct.Info;
    end
    module.Info.ReplayedFrom = sourceType;

    if isfield(moduleStruct, 'Parameters') && ~isempty(moduleStruct.Parameters)
        paramList = moduleStruct.Parameters;
        if ~iscell(paramList), paramList = num2cell(paramList); end

        for paramIdx = 1:numel(paramList)
            paramStruct = paramList{paramIdx};

            parameter = hw.Parameter(iface);
            parameter.Module = module;

            % Metadata only. Values are deliberately never assigned: set.Value
            % runs randomize_value, Expression evaluation and clamp_value_, so
            % restoring them would re-derive the very numbers being reviewed --
            % and would throw outright on a read-only parameter like RespCode.
            % The design-time value is taken straight from the struct below and
            % kept on the interface as the fallback for anything DATA never
            % recorded.
            parameter.fromStruct(paramStruct, false);

            % A replayed parameter must never re-derive itself. Clearing these
            % keeps a stray write (a control that escaped being disabled, a
            % paradigm hook that fires anyway) from computing a new value on
            % top of the record.
            parameter.Expression = "";
            parameter.isRandom   = false;

            iface.setDefaultValue_(parameter.validName, localDefaultValue(paramStruct));

            module.Parameters(end + 1) = parameter;
        end
    end

    modules(end + 1) = module;
end

iface.set_module(modules);

end




function v = localDefaultValue(paramStruct)
% v = localDefaultValue(paramStruct)
%
% What a parameter should read when the session record has no field for it --
% write-only, invisible and trigger parameters never reach DATA. The saved
% Value first, then the first design-time level, then empty. Read from the
% struct rather than from the parameter, because hw.Parameter.get.Value routes
% through hw.Replay.get_parameter and asking the parameter would recurse.

if isfield(paramStruct, 'Value') && ~isempty(paramStruct.Value)
    v = paramStruct.Value;
    return
end

if isfield(paramStruct, 'Values') && ~isempty(paramStruct.Values)
    values = paramStruct.Values;
    if iscell(values)
        v = values{1};
    else
        v = values(1);
    end
    return
end

v = [];

end
