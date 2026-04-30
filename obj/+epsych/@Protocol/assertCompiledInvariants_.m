function assertCompiledInvariants_(obj) %#ok<INUSD>
% assertCompiledInvariants_(obj)
% Legacy compatibility stub for removed compiled-invariant checks.
%
% This method always errors because invariant checks now run in compile_internal().

error('epsych:Protocol:Removed', ...
    'assertCompiledInvariants_ is removed. Invariants are checked inside compile_internal.');
end
