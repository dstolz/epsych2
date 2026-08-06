function populateModuleParametersFromDescriptor(obj, module, descriptorLines, options)
% populateModuleParametersFromDescriptor(obj, module, descriptorLines, Name=Value)
% Convert the firmware's DESC? reply into hw.Parameter objects on a module.
%
% This is the single populate helper shared by setup_interface (discovery at
% connect) and readHardwareParameters (ProtocolDesigner's "Read HW Params"),
% the structure the interface tutorial recommends so both paths cannot drift.
%
% Each descriptor line has the form
%   P <name> <access> <type> <flags> <min> <max> <unit>
% where access is R | W | RW, type is F | I | B | S | BUF, and flags is a
% concatenation of T (trigger), H (hidden), A (array), or - for none.
%
% Parameters:
%   obj             - hw.Teensy instance that owns the module.
%   module          - hw.Module to populate.
%   descriptorLines - Cell array of DESC? body lines.
%   options.Mode    - 'merge' (default) appends only parameters whose hardware
%                     name is not already present, so a repeat read is
%                     idempotent and hand edits survive. 'replace' rebuilds
%                     module.Parameters purely from the descriptor.
%
% See also: hw.Teensy.readHardwareParameters, hw.TDT_RPcox.populateModuleParametersFromTags

arguments
    obj
    module (1,1) hw.Module
    descriptorLines cell
    options.Mode (1,:) char {mustBeMember(options.Mode, {'merge', 'replace'})} = 'merge'
end

if strcmp(options.Mode, 'replace')
    module.Parameters = hw.Parameter.empty(1, 0);
    existingNames = {};
else
    existingNames = arrayfun(@hw.Interface.getHardwareParameterName, ...
        module.Parameters, UniformOutput = false);
end

for k = 1:numel(descriptorLines)
    tok = strsplit(strtrim(descriptorLines{k}));
    if numel(tok) < 4 || ~strcmp(tok{1}, 'P')
        continue
    end

    name = tok{2};

    % '%' marks a firmware-internal name that is never exposed as a parameter,
    % matching the RPvds convention in hw.TDT_RPcox.
    if name(1) == '%'
        continue
    end

    if ismember(name, existingNames)
        continue
    end

    P = hw.Parameter(obj);
    P.Name = name;
    obj.setHardwareParameterName(P, name);

    P.Type = local_epsychType(tok{4});

    flags = '';
    if numel(tok) >= 5
        flags = upper(tok{5});
    end

    % A trigger is whatever the firmware flags as one, or whatever carries the
    % repository's '!' prefix.
    P.isTrigger = contains(flags, 'T') || name(1) == '!';
    P.isArray = contains(flags, 'A');

    % Hidden if the firmware says so, or by the repository's name-prefix
    % convention. '~' additionally makes gui.BoxGUI render a toggle rather
    % than a momentary button.
    P.Visible = ~contains(flags, 'H') && ~any(name(1) == '_~#');

    % Access deliberately ignores a 'W' descriptor for triggers.
    % epsych.Runtime resolves the required x_NewTrial_/x_ResetTrig_ triggers
    % through all_parameters, whose default Access='Read' filter drops
    % write-only parameters — a 'Write' trigger is simply never found and the
    % session aborts with epsych:RunExpt:MissingTrigger.
    if P.isTrigger
        P.Access = 'Any';
    else
        P.Access = local_epsychAccess(tok{3});
    end

    if numel(tok) >= 7
        lo = str2double(tok{6});
        hi = str2double(tok{7});
        if ~isnan(lo), P.Min = lo; end
        if ~isnan(hi), P.Max = hi; end
    end

    if numel(tok) >= 8 && ~strcmp(tok{8}, '-')
        P.Unit = tok{8};
    end

    P.Module = module;
    module.Parameters(end + 1) = P;
    existingNames{end + 1} = name;
end

end


function t = local_epsychType(code)
% t = local_epsychType(code)
% Map a firmware type code onto the hw.Parameter Type vocabulary.
switch upper(char(code))
    case 'F'
        t = 'Float';
    case 'I'
        t = 'Integer';
    case 'B'
        t = 'Boolean';
    case 'S'
        t = 'String';
    case 'BUF'
        t = 'Buffer';
    otherwise
        t = 'Undefined';
end
end


function a = local_epsychAccess(code)
% a = local_epsychAccess(code)
% Map a firmware access code onto the hw.Parameter Access vocabulary.
switch upper(char(code))
    case 'R'
        a = 'Read';
    case 'W'
        a = 'Write';
    otherwise
        a = 'Any';
end
end
