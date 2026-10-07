function bindGizmoInfo_(obj, api, module, rates)
% bindGizmoInfo_(obj, api, module, rates)
% Record on a module what Synapse knows about its gizmo: category, type,
% parent processor, whether it is a processor in legacy mode, and the
% sample rate it runs at.
%
% The sample rate is the one that matters at runtime -- a stimulus is
% regenerated at the module's Fs before it is written -- and finding it is
% where legacy mode differs. An ordinary gizmo has a parent processor, and
% getSamplingRates is keyed by processor. A legacy processor IS the
% processor: getGizmoParent answers nothing for it, and its rate is filed
% under its own name. A rate that cannot be found leaves Fs at the hw.Module
% default and is reported, since the stimulus would then play at whatever
% rate it was authored with.
%
% Parameters:
%   api    - SynapseAPI client.
%   module - hw.Module whose Label is the Synapse name.
%   rates  - struct from getSamplingRates, keyed by cleaned processor name.
%
% See also: hw.TDT_Synapse.discoverModules_, hw.TDT_Synapse.bindModules_

gizmo = obj.gizmoName_(module);

category = '';
gizmoType = '';
description = '';
try
    g = api.getGizmoInfo(gizmo);
    if isstruct(g)
        category = local_text(g, 'cat');
        gizmoType = local_text(g, 'type');
        description = local_text(g, 'desc');
    end
catch ME
    vprintf(2,'No gizmo info from Synapse for "%s": %s', gizmo, ME.message)
end

legacy = strcmpi(category, obj.LEGACY_CATEGORY);

% A processor-level object -- a legacy processor, or a processor in its
% normal mode -- has no parent, and asking is a 404 the client reports as
% a warning with a stack. Only a gizmo is asked.
parent = '';
if ~any(strcmpi(category, obj.PROCESSOR_CATEGORIES))
    try
        p = api.getGizmoParent(gizmo);
        if (ischar(p) || isstring(p)) && strlength(string(p)) > 0
            parent = char(p);
        end
    catch ME
        vprintf(3,'No parent reported for "%s": %s', gizmo, ME.message)
    end
end

rateKey = parent;
if isempty(rateKey)
    rateKey = local_rateKey(gizmo);
end

Fs = nan;
if isfield(rates, rateKey)
    Fs = double(rates.(rateKey));
end

info = module.Info;
info.Legacy = legacy;
info.Category = category;
info.GizmoType = gizmoType;
info.Description = description;
info.Processor = parent;
module.Info = info;

if isscalar(Fs) && isfinite(Fs) && Fs > 0
    module.Fs = Fs;
else
    vprintf(0,1,['Module "%s": Synapse did not report a sample rate (looked under "%s"); ' ...
        'stimuli will play at the rate they were authored with.'], gizmo, rateKey)
end

end


function s = local_text(g, field)
s = '';
if isfield(g, field) && (ischar(g.(field)) || isstring(g.(field)))
    s = char(g.(field));
end
end


function key = local_rateKey(gizmo)
% The client files 'RZ6(1)' as RZ6_1: parentheses become underscores and a
% trailing one is dropped (SynapseAPI.cleanField).
key = regexprep(gizmo, '[()]', '_');
key = regexprep(key, '_$', '');
end
