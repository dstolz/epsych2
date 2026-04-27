function compile_internal(obj)
% compile_internal(obj)
%
% Private implementation of protocol compilation. Gathers parameters from
% all interfaces, builds writeparams/readparams arrays, expands parameter
% values via cross-product (preserving paired groups), and applies
% repetitions.
%
% Called by compile(). Do not call directly.

writeparams = {};
readparams = {};
randparams = [];
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

            full_name = obj.getCompiledParameterName_(p, iface_type, module);
            if ~strcmp(p.Access, 'Write')
                readparams{end+1} = full_name; %#ok<AGROW>
            end

            if strcmp(p.Access, 'Read')
                continue
            end

            writeparams{end+1} = full_name; %#ok<AGROW>
            randparams(end+1) = p.isRandom; %#ok<AGROW>

            trials{1, colIdx} = p.Value;
            paramMetadata{colIdx} = struct( ...
                'name', full_name, ...
                'pair', obj.getParameterPairName_(p)); %#ok<AGROW>

            colIdx = colIdx + 1;
        end
    end
end

if isempty(writeparams)
    obj.COMPILED.writeparams = {};
    obj.COMPILED.readparams = readparams;
    obj.COMPILED.randparams = [];
    obj.COMPILED.trials = {};
    obj.COMPILED.OPTIONS = obj.Options;
    obj.COMPILED.ntrials = 0;
    return
end

trials = obj.expand_cross_product(trials, paramMetadata);
if isempty(trials)
    vprintf(0, 1, 'No trials generated after paired expansion');
    obj.COMPILED.writeparams = writeparams;
    obj.COMPILED.readparams = readparams;
    obj.COMPILED.randparams = randparams;
    obj.COMPILED.trials = {};
    obj.COMPILED.OPTIONS = obj.Options;
    obj.COMPILED.ntrials = 0;
    return
end

uniqueTrialCount = size(trials, 1);
nreps = obj.Options.numReps;
if ~isinf(nreps) && nreps > 0
    trials = repmat(trials, nreps, 1);
end

obj.COMPILED.writeparams = writeparams;
obj.COMPILED.readparams = readparams;
obj.COMPILED.randparams = randparams;
obj.COMPILED.trials = trials;
obj.COMPILED.OPTIONS = obj.Options;
obj.COMPILED.ntrials = size(trials, 1);

obj.assertCompiledInvariants_();

vprintf(2, 'Protocol compiled: %d unique trials, %d total with %d repetitions', ...
    uniqueTrialCount, obj.COMPILED.ntrials, nreps);
end
