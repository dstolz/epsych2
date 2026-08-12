function [parameters, trials, writeparams, writeParamIdx] = compiledTrialColumns(compiled)
% [parameters, trials, writeparams, writeParamIdx] = epsych.Runtime.compiledTrialColumns(compiled)
% Trial table and the column map that names its columns, from a compiled protocol.
%
% These four fields of TRIALS are only meaningful together: writeparams is
% the column-ordered list of writable parameter valid-names, writeParamIdx
% maps each of those names to its column of trials, and parameters is the
% matching hw.Parameter handle array. epsych.Protocol.compile guarantees the
% three are column-aligned; this function is how that alignment reaches
% TRIALS, in one call, so no caller can install a new trial table and forget
% the map that indexes it.
%
% Forgetting it is not a cosmetic bug. Every consumer of writeParamIdx
% (gui.Parameter_Update, Runtime.updateTrialsFromParameters,
% gui.eval_staircase_training_mode, gui.NextTrial) reads or WRITES a trial
% column by name, so a stale map silently reads one parameter's value under
% another's label and commits operator edits into the wrong column. A
% recompile that adds or removes a parameter -- an operator recompile, a
% phase load, or a trial selector that creates its own runtime parameters --
% shifts every column after the change.
%
% Parameters:
%   compiled - epsych.Protocol.COMPILED struct (parameters, trials, writeparams).
%
% Returns:
%   parameters    - hw.Parameter handles, one per trial-table column.
%   trials        - Compiled trial table, trials x parameters.
%   writeparams   - Column-ordered cell of writable parameter valid-names.
%   writeParamIdx - Struct mapping each valid-name to its column index.
%
% Example:
%   [T.parameters, T.trials, T.writeparams, T.writeParamIdx] = ...
%       epsych.Runtime.compiledTrialColumns(PROTOCOL.COMPILED);
%
% See also epsych.Protocol.compile, runtime/timerfcns/ep_TimerFcn_Start.m,
% runtime/timerfcns/ep_TimerFcn_RunTime.m,
% documentation/epsych/epsych_TrialLifecycle.md

arguments
    compiled (1,1) struct
end

parameters  = compiled.parameters;
trials      = compiled.trials;
writeparams = compiled.writeparams;

% A live compile names columns by hw.Parameter.validName, which is always a
% valid identifier. Legacy compiled protocols can carry 'Module.Param'
% names, which cannot be struct fields; those columns simply have no
% by-name lookup rather than blocking the session from starting.
writeParamIdx = struct();
for w = 1:numel(writeparams)
    name = char(string(writeparams{w}));
    if isvarname(name)
        writeParamIdx.(name) = w;
    else
        vprintf(2, 'Trial column %d ("%s") is not addressable by name', w, name);
    end
end

% A mismatch means the compile produced a table its own name list cannot
% index. Report it rather than throwing: this runs inside the session timer,
% where preserving the last valid runtime state beats stopping the session.
if ~isempty(trials) && size(trials, 2) ~= numel(writeparams)
    vprintf(0, 1, ['Compiled trial table has %d columns but %d write parameters; ' ...
        'parameter lookups by name will be wrong'], size(trials, 2), numel(writeparams));
end
