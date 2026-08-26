function entries = discoveredEntries_(knownClasses, knownTypes)
% entries = gui.BehaviorBuilder.discoveredEntries_(knownClasses, knownTypes)
% Palette entries for components in the gui.components package that the
% hand-written catalog rows do not already cover.
%
% This is what makes adding a component free: drop a class into
% gui.components with a getComponentSpec (or a recognizable constructor) and
% it appears on the palette, gets its options from the spec, and is emitted
% by generateCode's generic branch. Nothing here needs editing.
%
% Entries whose class or type a catalog row already claims are skipped, so
% the legacy rows keep their option vocabulary and their bespoke dialogs.
%
% See also gui.BehaviorBuilder.componentCatalog, gui.ComponentSpec

arguments
    knownClasses cell
    knownTypes cell
end

proto = struct('Type','','Display','','Category','','Description','', ...
    'NeedsPsych',false,'Poppable',false,'HasOptions',false,'EmitClass','');
proto.PsychTypes = {}; % assigned separately: struct('f',{{}}) makes an empty ARRAY
entries = repmat(proto, 1, 0);

specs = gui.ComponentSpec.empty(1,0);
try
    specs = gui.ComponentSpec.packageSpecs('gui.components');
catch ME
    % A palette that cannot enumerate is still a usable palette.
    vprintf(2, 'gui.BehaviorBuilder: component discovery failed (%s)', ME.message)
    return
end

knownClasses = knownClasses(~cellfun(@isempty, knownClasses));
for k = 1:numel(specs)
    s = specs(k);
    if any(strcmp(knownClasses, s.className)), continue; end
    if any(strcmp(knownTypes,   s.type)),      continue; end
    entries(end+1) = s.toCatalogEntry(); %#ok<AGROW>
end
end
