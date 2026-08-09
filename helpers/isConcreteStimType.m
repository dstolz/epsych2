function tf = isConcreteStimType(className)
% tf = isConcreteStimType(className)
% True when className names an instantiable stimgen stimulus class.
%
% stimgen.StimType is declared Hidden, so superclasses() omits it and the
% obvious ismember('stimgen.StimType', superclasses(...)) test returns false
% for every stimulus. meta.class.SuperclassList does report hidden ancestors,
% so walk that tree instead. Resolving through meta.class also covers the case
% where the stimgen submodule is not checked out, and rejects abstract classes
% that reach a caller through stimgen.StimType.list (a filename glob).
%
% Parameters:
%   className - Fully qualified class name, e.g. "stimgen.Tone".
%
% Returns:
%   tf - Scalar logical; false when the class does not resolve or is abstract.
%
% Example:
%   names = stimgen.StimType.list();
%   names = names(cellfun(@(n) isConcreteStimType("stimgen." + n), names));
%
% See also: stimgen.StimType, gui.Parameter_Control, epsych.Protocol

arguments
    className (1,1) string
end

tf = false;

mc = meta.class.fromName(className);
if isempty(mc) || mc.Abstract, return; end

tf = localInheritsFrom(mc, "stimgen.StimType");
end


function tf = localInheritsFrom(mc, targetName)
% Depth-first walk of the meta.class superclass tree.
tf = false;
for k = 1:numel(mc.SuperclassList)
    sup = mc.SuperclassList(k);
    if strcmp(sup.Name, targetName) || localInheritsFrom(sup, targetName)
        tf = true;
        return
    end
end
end
