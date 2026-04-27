function compile_internal(obj)
% compile_internal(obj)
%
% Private implementation of protocol compilation. Gathers hw.Parameter handles from
% all visible, non-read-only parameters across all interfaces. Builds the COMPILED
% struct containing the hw.Parameter handle array, the cross-product trial table, and
% metadata. Invariant checks are performed inline before storing results.
%
% Called by compile(). Do not call directly.

parameters = hw.Parameter.empty(1, 0);
trials = cell(1, 0);
colIdx = 1;
paramMetadata = {};

for iface_idx = 1:length(obj.Interfaces)
    iface = obj.Interfaces(iface_idx);
    iface_type = char(iface.Type);

    for mod_idx = 1:length(iface.Module)
        module = iface.Module(mod_idx);

        for param_idx = 1:length(module.Parameters)
            p = module.Parameters(param_idx);

            if ~p.Visible
                continue
            end

            if strcmp(p.Access, 'Read')
                continue
            end

            assert(~isempty(p.Values), 'epsych:Protocol:EmptyValues', ...
                'Parameter "%s" has no Values defined. Set values before compiling.', p.Name);

            parameters(end+1) = p;
            trials{1, colIdx} = p.Values;
            paramMetadata{colIdx} = struct( ...
                'name', p.validName, ...
                'pair', obj.getParameterPairName_(p));

            colIdx = colIdx + 1;
        end
    end
end

if isempty(parameters)
    obj.COMPILED.parameters = hw.Parameter.empty(1, 0);
    obj.COMPILED.trials     = {};
    obj.COMPILED.OPTIONS    = obj.Options;
    obj.COMPILED.ntrials    = 0;
    return
end

trials = obj.expand_cross_product(trials, paramMetadata);
if isempty(trials)
    vprintf(0, 1, 'No trials generated after paired expansion');
    obj.COMPILED.parameters = parameters;
    obj.COMPILED.trials     = {};
    obj.COMPILED.OPTIONS    = obj.Options;
    obj.COMPILED.ntrials    = 0;
    return
end

uniqueTrialCount = size(trials, 1);
nreps = obj.Options.numReps;
if ~isinf(nreps) && nreps > 0
    trials = repmat(trials, nreps, 1);
end

% Inline invariant checks
assert(size(trials, 2) == length(parameters), ...
    'epsych:Protocol:ColumnMismatch', ...
    'Trial column count (%d) does not match parameter count (%d).', ...
    size(trials, 2), length(parameters));

names = {parameters.Name};
assert(length(unique(names)) == length(names), ...
    'epsych:Protocol:DuplicateParameterNames', ...
    'Duplicate parameter names found in compiled protocol.');

obj.COMPILED.parameters = parameters;
obj.COMPILED.trials     = trials;
obj.COMPILED.OPTIONS    = obj.Options;
obj.COMPILED.ntrials    = size(trials, 1);

vprintf(2, 'Protocol compiled: %d unique trials, %d total with %d repetitions', ...
    uniqueTrialCount, obj.COMPILED.ntrials, nreps);
end
