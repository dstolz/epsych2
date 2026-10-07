function modules = discoverModules_(obj, api)
% modules = discoverModules_(obj, api)
% Build one hw.Module for every Synapse object that exposes API parameters.
%
% getGizmoNames lists everything in the experiment's processing tree:
% gizmos, and the processors themselves. A processor in legacy mode is the
% interesting case -- it carries the RPvdsEx circuit's parameter tags
% directly, under its own name ('RZ6(1)'), with category 'Legacy' and no
% parent -- but the rule is the same for every entry: it is a module if it
% answers getParameterNames with something EPsych can use. A processor in
% its normal mode usually answers with nothing (its gizmos hold the
% parameters) and is passed over, as is a gizmo with no API-enabled
% parameter.
%
% Parameters:
%   api - SynapseAPI client, already in a runtime mode.
%
% Returns:
%   modules - 1xN hw.Module array, each populated, labelled with the
%             Synapse name and indexed by position.
%
% Throws hw:TDT_Synapse:NoGizmos when the server reports no experiment, and
% hw:TDT_Synapse:NoApiParameters when nothing in it is addressable.
%
% See also: hw.TDT_Synapse.bindModules_, hw.TDT_Synapse.populateModuleParametersFromGizmo

names = local_cellstr(api.getGizmoNames());
if isempty(names)
    error('hw:TDT_Synapse:NoGizmos', ...
        ['Synapse at %s reports no gizmos. Load an experiment -- for legacy mode, a rig whose ' ...
        'processor is set to Legacy with a circuit file -- before connecting.'], obj.Server);
end

rates = local_samplingRates(api);

modules = hw.Module.empty(1, 0);
for k = 1:numel(names)
    gizmo = names{k};
    module = hw.Module(obj, gizmo, local_moduleName(gizmo), uint8(numel(modules) + 1));
    module.Info = struct('SynapseName', gizmo);

    nAdded = obj.populateModuleParametersFromGizmo(module, api);
    if nAdded == 0
        vprintf(3,'Synapse object "%s" exposes no API parameters; not a module', gizmo)
        continue
    end

    obj.bindGizmoInfo_(api, module, rates);
    modules(end+1) = module;

    vprintf(2,'Synapse module "%s": %d parameter(s) @ %g Hz%s', ...
        gizmo, nAdded, module.Fs, local_legacyTag(module))
end

if isempty(modules)
    error('hw:TDT_Synapse:NoApiParameters', ...
        ['None of the %d object(s) in the Synapse experiment at %s exposes an API parameter ' ...
        '(%s). Enable API access on the gizmos you need, or set the processor to legacy mode ' ...
        'with a circuit that has parameter tags.'], ...
        numel(names), obj.Server, strjoin(names, ', '));
end

end


function c = local_cellstr(v)
% The client answers an empty list as [] and a single name as char.
if isempty(v)
    c = {};
elseif ischar(v) || isstring(v)
    c = cellstr(v);
else
    c = reshape(v, 1, []);
end
end


function rates = local_samplingRates(api)
% Rates are only ever advisory here: a module whose rate cannot be read is
% still a module, and bindGizmoInfo_ reports the gap.
rates = struct();
try
    rates = api.getSamplingRates();
catch ME
    vprintf(2,'Could not read sampling rates from Synapse: %s', ME.message)
end
if ~isstruct(rates)
    rates = struct();
end
end


function name = local_moduleName(gizmo)
% 'RZ6(1)' -> 'RZ6'; a gizmo name without an instance suffix is its own.
name = regexprep(gizmo, '\(\d+\)$', '');
if isempty(name)
    name = gizmo;
end
end


function s = local_legacyTag(module)
if isfield(module.Info, 'Legacy') && isequal(module.Info.Legacy, true)
    s = ' [legacy]';
else
    s = '';
end
end
