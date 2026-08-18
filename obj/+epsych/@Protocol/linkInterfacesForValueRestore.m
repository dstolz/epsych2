function restoreLink = linkInterfacesForValueRestore(obj, extraInterfaces)
% restoreLink = linkInterfacesForValueRestore(obj)
% restoreLink = linkInterfacesForValueRestore(obj, extraInterfaces)
% Temporarily present this Protocol as the interfaces' Runtime so that
% assigning hw.Parameter.Value can resolve cross-interface Expression
% references.
%
% hw.Parameter.set.Value evaluates the parameter's Expression, and the
% resolver finds parameters outside the owning interface through
% iface.Runtime.Interfaces, falling back to the owning interface alone when
% no Runtime is registered. Design-time code (protocol load, ProtocolDesigner
% module and interface edits) runs before any epsych.Runtime exists, so an
% expression such as "StimDelay + StimDur - Params.RespWinPreStim" -- where
% Params is a module on a different interface -- would be left unresolved and
% the assignment would throw. epsych.Protocol exposes .Interfaces, which is
% all the resolver reads, so it stands in for the duration of the restore.
%
% Only interfaces with no Runtime are linked: one already registered with a
% real epsych.Runtime can already see every interface. Keep restoreLink alive
% for the whole restore pass; the link is detached when it is cleared, even
% on error, so the interfaces present as unregistered until a real
% epsych.Runtime claims them.
%
%   restoreLink = protocol.linkInterfacesForValueRestore();
%   for k = 1:numel(parameters)
%       parameters(k).fromStruct(paramStructs{k});
%   end
%
% Parameters:
%   extraInterfaces - Additional hw.Interface objects to link that are not
%                     (yet) in obj.Interfaces, e.g. a replacement interface
%                     being populated before it is swapped into the protocol.
%
% Returns:
%   restoreLink - onCleanup object that detaches the link when destroyed.
%
% See also: hw.Parameter.resolveExpressionContext, epsych.Protocol.fromStruct

arguments
    obj (1,1) epsych.Protocol
    extraInterfaces (1,:) hw.Interface = hw.Interface.empty(1, 0)
end

candidates = [obj.Interfaces, extraInterfaces];
linked = hw.Interface.empty(1, 0);
for k = 1:numel(candidates)
    if isvalid(candidates(k)) && isempty(candidates(k).Runtime)
        candidates(k).Runtime = obj;
        linked(end + 1) = candidates(k);
    end
end

restoreLink = onCleanup(@() localDetachRuntime_(linked));

end


function localDetachRuntime_(interfaces)
for k = 1:numel(interfaces)
    if isvalid(interfaces(k))
        interfaces(k).Runtime = [];
    end
end
end
