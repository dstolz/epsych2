function snap = runtimeSnapshot(obj) %#ok<STOUT,INUSD>
% snap = runtimeSnapshot(obj)
% Legacy compatibility stub for removed runtime snapshot access.
%
% This method always errors because runtime data should be read from COMPILED directly.

error('epsych:Protocol:Removed', ...
    'runtimeSnapshot is removed. Read COMPILED.parameters and COMPILED.trials directly.');
end
