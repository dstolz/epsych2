function P = applyToModule(obj, module, options)
% P = applyToModule(obj, module)
% P = applyToModule(obj, module, Mode="merge")
% Create this program's parameters on an hw.Module.
%
% Parameters
%   module - Target hw.Module, normally the module of a hw.Teensy interface.
%   Mode   - "merge" (default) skips names the module already has, so applying
%       twice is idempotent and hand-edited parameters survive. "replace"
%       removes the module's existing parameters first.
%
% Returns:
%   P - The hw.Parameter array created. Empty when nothing was added.
%
% Example
%   iface = protocol.findInterface('Teensy');
%   P = program.applyToModule(iface.Module(1));
%
% See also: teensy.Program.parameterSpecs, hw.Module.add_parameter

arguments
    obj (1,1) teensy.Program
    module (1,1) hw.Module
    options.Mode (1,1) string {mustBeMember(options.Mode, ["merge","replace"])} = "merge"
end

specs = obj.parameterSpecs();
P = hw.Parameter.empty(1, 0);

if options.Mode == "replace"
    module.Parameters = hw.Parameter.empty(1, 0);
end

existing = strings(1, 0);
if ~isempty(module.Parameters)
    existing = string({module.Parameters.Name});
end

nSkipped = 0;

for i = 1:numel(specs)
    spec = specs(i);

    if any(strcmp(existing, spec.Name))
        nSkipped = nSkipped + 1;
        continue
    end

    nv = namedargs2cell(spec.Options);
    p = module.add_parameter(spec.Name, spec.Value, nv{:});

    % add_parameter has no UpdateEveryTrial option, and setting isTrigger
    % rewrites the flag, so it must be assigned last.
    p.UpdateEveryTrial = spec.UpdateEveryTrial;

    P(end + 1) = p;
    existing(end + 1) = string(spec.Name);
end

vprintf(1, 'teensy.Program: added %d parameter(s) to module "%s"%s', ...
    numel(P), module.Name, localSkipText_(nSkipped));
end


function txt = localSkipText_(nSkipped)
% txt = localSkipText_(nSkipped)
% Trailing clause naming how many names were already present.
if nSkipped == 0
    txt = '';
else
    txt = sprintf(', skipping %d already present', nSkipped);
end
end
