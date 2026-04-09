
function fromStruct(obj, S, options)
% fromStruct(obj, S)
% Apply a decoded serialized struct to this hw.Parameter object.
%
% Used to restore parameter state from a struct, typically decoded from JSON. Updates all relevant fields, including metadata, callbacks, flags, bounds, value, timestamp, and user data.
%
% Parameters:
%   obj (1,1) hw.Parameter
%       The parameter object to update.
%   S (1,1) struct
%       Struct decoded from JSON with serialized parameter fields.
%
% Returns:
%   None. Updates the parameter object in-place.
%
% See also: writeParametersJSON, readParametersJSON, jsondecode


arguments
    obj (1,1) hw.Parameter
    S (1,1) struct
    options.UpdateValue (1,1) logical = true % Whether to update the Value field or leave it unchanged (useful for preserving current value when loading metadata changes)
    %options.AddParameterIfMissing (1,1) logical = true % If true, will add a new parameter if the struct references a parameter name that doesn't exist in the current module. Use with caution as this may have unintended consequences.
end

%{
% If AddParameterIfMissing is true, check if parameter exists in parent module, and add if missing
if options.AddParameterIfMissing

    % Check if parameter exists on module
    x = obj.Module.find_parameter(S.Name,silenceParameterNotFound=true);
    
    if isempty(x)
        % Add parameter to parent module
        obj.Module.add_parameter(S.Name, S.Value);
    end
end
%}


% Metadata
obj.Name = char(S.Name);
obj.Description = string(S.Description);
obj.Unit = char(S.Unit);
obj.Access = normalizeLegacyAccess(char(S.Access));
obj.Type = char(S.Type);
obj.Format = char(S.Format);
obj.Visible = logical(S.Visible);

%{
% Callbacks
obj.PreUpdateFcn = obj.strToFcn_(S.PreUpdateFcn);
obj.EvaluatorFcn = obj.strToFcn_(S.EvaluatorFcn);
obj.PostUpdateFcn = obj.strToFcn_(S.PostUpdateFcn);


obj.PreUpdateFcnArgs = obj.strToFcnArgs_(S.PreUpdateFcnArgs);
obj.EvaluatorFcnArgs = obj.strToFcnArgs_(S.EvaluatorFcnArgs);
obj.PostUpdateFcnArgs = obj.strToFcnArgs_(S.PostUpdateFcnArgs);

obj.PreUpdateFcnEnabled = logical(S.PreUpdateFcnEnabled);
obj.EvaluatorFcnEnabled = logical(S.EvaluatorFcnEnabled);
obj.PostUpdateFcnEnabled = logical(S.PostUpdateFcnEnabled);
%}

% Flags
obj.isArray = logical(S.isArray);
obj.isTrigger = logical(S.isTrigger);

% Bounds
obj.Min = obj.safeToNumeric_(S.Min);
obj.Max = obj.safeToNumeric_(S.Max);
obj.isRandom = logical(S.isRandom);

% Value (set after Type/bounds so validation context is correct)
if options.UpdateValue
    obj.Value = obj.safeToNumeric_(S.Value);
end

end


function access = normalizeLegacyAccess(access)
if isequal(access, 'Read / Write')
    access = 'Any';
end
end

