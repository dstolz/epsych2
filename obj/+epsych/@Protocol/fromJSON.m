function obj = fromJSON(filename)
% obj = epsych.Protocol.fromJSON(filename)
% Deserialize a protocol from a JSON file (inverse of toJSON).
%
% Parameters:
%   filename (char) - Path to a .json protocol file
%
% Returns:
%   obj - Initialized epsych.Protocol instance

arguments
    filename (1,:) char
end

if ~isfile(filename)
    error('epsych:Protocol:FileNotFound', 'Protocol JSON file not found: %s', filename);
end

json_str = fileread(filename);
struct_in = jsondecode(json_str);

% jsondecode converts JSON arrays of uniform objects to struct arrays;
% fromStruct expects cell arrays for InterfaceData, Modules, and Parameters.
struct_in = normalizeJSONStruct(struct_in);

obj = epsych.Protocol();
obj.fromStruct(struct_in);

fprintf('[INFO] Protocol loaded from JSON: %s\n', filename);
end

% -------------------------------------------------------------------------
function s = normalizeJSONStruct(s)
% Convert struct arrays produced by jsondecode back into cell arrays that
% match the format produced by toStruct / expected by fromStruct.

if isfield(s, 'InterfaceData') && isstruct(s.InterfaceData)
    s.InterfaceData = num2cell(s.InterfaceData);
end

if ~isfield(s, 'InterfaceData') || isempty(s.InterfaceData)
    return
end

for i = 1:numel(s.InterfaceData)
    iface = s.InterfaceData{i};

    if isfield(iface, 'Modules') && isstruct(iface.Modules)
        iface.Modules = num2cell(iface.Modules);
    end

    if isfield(iface, 'Modules') && ~isempty(iface.Modules)
        for j = 1:numel(iface.Modules)
            m = iface.Modules{j};
            if isfield(m, 'Parameters') && isstruct(m.Parameters)
                m.Parameters = num2cell(m.Parameters);
            end
            iface.Modules{j} = m;
        end
    end

    s.InterfaceData{i} = iface;
end
end
