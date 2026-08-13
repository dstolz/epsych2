function [nAdded, nSkipped] = populateModuleParametersFromTags(obj, module, tags)
% [nAdded, nSkipped] = populateModuleParametersFromTags(obj, module, tags)
% Append hw.Parameter objects to a module for each RPvds parameter tag.
%
% Single source of truth for turning RPvds tag metadata into hw.Parameter
% objects; used by setup_interface, connect, and readHardwareParameters.
%
% Parameters:
%   module - hw.Module receiving the parameters.
%   tags   - struct array shaped like [TDTRP.PARTAG{:}] with fields
%            tag_name, tag_type, and tag_size.
%
% Tags whose hardware name already exists on the module are skipped, so the
% operation is idempotent and preserves user edits.
%
% Returns:
%   nAdded   - Number of parameters appended to module.Parameters.
%   nSkipped - Number of tags skipped because they already exist.
%
% See also: hw.TDT_RPcox.readHardwareParameters, TDTRP

nAdded = 0;
nSkipped = 0;

if isempty(tags)
    return
end

% '%' tags are RPvds-internal and never exposed as parameters
tags(arrayfun(@(a) a.tag_name(1) == '%', tags)) = [];

existingNames = arrayfun(@hw.Interface.getHardwareParameterName, ...
    module.Parameters, 'UniformOutput', false);

for k = 1:length(tags)
    tagName = tags(k).tag_name;
    if any(strcmp(existingNames, tagName))
        nSkipped = nSkipped + 1;
        continue
    end

    P = hw.Parameter(obj);

    P.Name = tagName;
    obj.setHardwareParameterName(P, tagName);
    P.isArray = tags(k).tag_size > 1;

    P.isTrigger = P.Name(1) == '!'; % our convention for a trigger
    P.Visible = ~any(P.Name(1) == '_~#%');

    switch tags(k).tag_type
        case 68
            P.Type = 'Buffer';

        case 73
            P.Type = 'Integer';

        case 78
            P.Type = 'Boolean';

        case 83
            P.Type = 'Float';

        case 80
            P.Type = 'Coefficient Buffer';
            % Coefficient buffers hold session-static data (e.g. calibration
            % filter coefficients): write them on the first trial dispatch
            % only. The Type is assigned after construction here, so the
            % hw.Parameter constructor's Coefficient Buffer default cannot
            % apply; mirror it explicitly.
            P.SetOnce = true;
            P.UpdateEveryTrial = false;

        case 65
            P.Type = 'Undefined';
    end

    P.Module = module;
    module.Parameters(end+1) = P;
    nAdded = nAdded + 1;
end

end
