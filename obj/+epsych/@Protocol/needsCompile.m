function tf = needsCompile(obj)
% tf = needsCompile(obj)
%
% Returns true if the protocol requires (re)compilation before use.
% True when: never compiled (ntrials == 0 or compiledAt is NaT),
% or when the protocol was saved/modified after the last compile.
%
% Returns:
%   tf (logical) - true if compile() should be called

if obj.COMPILED.ntrials == 0
    tf = true;
    return
end

if ~isfield(obj.COMPILED, 'compiledAt') || ...
        isempty(obj.COMPILED.compiledAt) || ...
        isnat(obj.COMPILED.compiledAt)
    tf = true;
    return
end

tf = false;
if ischar(obj.meta.lastModified) && ~isempty(obj.meta.lastModified)
    modTime = datetime(obj.meta.lastModified, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
    tf = modTime > obj.COMPILED.compiledAt;
end
