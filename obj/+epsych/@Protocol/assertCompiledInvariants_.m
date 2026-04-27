function assertCompiledInvariants_(obj)
% assertCompiledInvariants_(obj)
%
% Assert structural invariants on the COMPILED struct. Called internally
% after compile_internal() and before runtimeSnapshot() to guarantee
% schema integrity. Errors hard on any violation.

compiled = obj.COMPILED;
nWrite = length(compiled.writeparams);
nCols  = size(compiled.trials, 2);

assert(nWrite == nCols, ...
    'epsych:Protocol:ColumnMismatch', ...
    'COMPILED writeparams count (%d) does not match trial matrix width (%d). Recompile the protocol.', ...
    nWrite, nCols);

if nWrite > 0
    [~, ia] = unique(compiled.writeparams, 'stable');
    if length(ia) ~= nWrite
        duplicates = compiled.writeparams(setdiff(1:nWrite, ia));
        error('epsych:Protocol:DuplicateParameters', ...
            'COMPILED writeparams contains duplicate identifiers: %s', ...
            strjoin(duplicates, ', '));
    end
end

nRand = length(compiled.randparams);
assert(nRand == nWrite, ...
    'epsych:Protocol:RandParamsMismatch', ...
    'COMPILED randparams length (%d) does not match writeparams count (%d). Recompile the protocol.', ...
    nRand, nWrite);
end
