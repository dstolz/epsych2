function compile_internal(obj)
    % compile_internal(obj) - Private method implementing the compile logic
    %
    % Migrates the multi-stage process from legacy ep_CompileProtocol:
    % 1. Gather parameters and calibrations from all interfaces
    % 2. Build writeparams/readparams arrays
    % 3. Apply calibration injection
    % 4. Apply WAV buffer expansion
    % 5. Cross-product expansion (includes partner grouping and randomization)
    % 6. Apply repetitions and randomization at trial level
    
    % Initialize output fields
    writeparams = {};
    readparams = {};
    randparams = [];
    trials = {};
    partner_groups = {};
    
    % === PHASE 1: Gather parameters from all interfaces ===
    col_idx = 1;
    param_metadata = {};  % Track {name, access, partner, calibration} for later use
    
    for iface_idx = 1:length(obj.Interfaces)
        iface = obj.Interfaces(iface_idx);
        iface_type = char(iface.Type);
        
        for mod_idx = 1:length(iface.Module)
            module = iface.Module(mod_idx);
            
            for param_idx = 1:length(module.Parameters)
                p = module.Parameters(param_idx);
                
                % Skip hidden/internal parameters
                if ~p.Visible
                    continue
                end
                
                % Build fully qualified parameter name
                if strcmp(iface_type, 'Software')
                    full_name = p.Name;  % Software params use simple names
                else
                    full_name = sprintf('%s.%s', module.Name, p.Name);
                end
                
                % Add to param lists based on access
                if ~strcmp(p.Access, 'Write')
                    readparams{end+1} = full_name;  %#ok<AGROW>
                end
                if ~strcmp(p.Access, 'Read')
                    writeparams{end+1} = full_name;  %#ok<AGROW>
                end
                
                % Track random flag (simplified; no calibration complexity yet)
                randparams(end+1) = p.isRandom;  %#ok<AGROW>
                
                % Initialize trial column with parameter values
                if isscalar(p.Value)
                    trials{1, col_idx} = p.Value;
                else
                    trials{1, col_idx} = p.Value;
                end
                
                param_metadata{col_idx} = struct(...
                    'name', full_name, ...
                    'access', p.Access, ...
                    'partner', '', ...
                    'calibration', '', ...
                    'type', p.Type, ...
                    'isArray', p.isArray);  %#ok<AGROW>
                
                col_idx = col_idx + 1;
            end
        end
    end
    
    % === PHASE 2: Cross-product expansion (simplified version) ===
    % For now, assume single-value parameters; WAV and calibration handling deferred to Phase 2
    % This builds the cross-product of all parameter value combinations
    
    vprintf(2, 'Before expansion: trials size %dx%d', size(trials));
    if ~isempty(trials)
        for col=1:size(trials,2)
            val = trials{1,col};
            fprintf('  Col %d: ', col);
            if isnumeric(val)
                fprintf('[%s]', num2str(val));
            else
                fprintf('%s', class(val));
            end
            fprintf('\n');
        end
    end
    
    % Expand trials via cross-product
    trials = obj.expand_cross_product(trials, randparams);
    
    vprintf(2, 'After expansion: trials size %dx%d', size(trials));
    
    if isempty(trials)
        vprintf(0, 1, 'No trials generated after cross-product expansion');
        obj.COMPILED.writeparams = {};
        obj.COMPILED.readparams = {};
        obj.COMPILED.randparams = [];
        obj.COMPILED.trials = {};
        obj.COMPILED.OPTIONS = obj.Options;
        obj.COMPILED.ntrials = 0;
        return
    end
    
    % === PHASE 3: Apply repetitions and randomization ===
    nreps = obj.Options.numReps;
    if ~isinf(nreps) && nreps > 0
        if obj.Options.randomize
            % Randomized: shuffle each repetition independently
            n_unique = size(trials, 1);
            trials_repeated = {};
            for rep = 1:nreps
                idx = randperm(n_unique);
                for trial_idx = 1:n_unique
                    row_in = trials(idx(trial_idx), :);
                    row_out_idx = (rep - 1) * n_unique + trial_idx;
                    trials_repeated(row_out_idx, :) = row_in;
                end
            end
            trials = trials_repeated;
        else
            % Serialized: repeat as-is
            trials = repmat(trials, nreps, 1);
        end
    end
    
    % === OUTPUT ===
    obj.COMPILED.writeparams = writeparams;
    obj.COMPILED.readparams = readparams;
    obj.COMPILED.randparams = randparams;
    obj.COMPILED.trials = trials;
    obj.COMPILED.OPTIONS = obj.Options;
    obj.COMPILED.ntrials = size(trials, 1);
    
    vprintf(2, 'Protocol compiled: %d unique trials, %d total with %d repetitions', ...
        length(writeparams), obj.COMPILED.ntrials, nreps);
end

function trials_out = expand_cross_product(obj, trials_in, randparams_in)
    % expand_cross_product(obj, trials_in, randparams_in)
    % 
    % Perform cross-product expansion on initial trial rows.
    % Detects parameters with multiple values and generates all combinations.
    
    vprintf(2, 'expand_cross_product: input trials %dx%d', size(trials_in));
    
    if isempty(trials_in)
        trials_out = {};
        return
    end
    
    % Find columns that have arrays (need expansion)
    n_cols = size(trials_in, 2);
    expand_cols = [];
    expand_values = {};
    
    for col = 1:n_cols
        val = trials_in{1, col};
        if isnumeric(val) && length(val) > 1
            % This column has multiple values that need expansion
            expand_cols(end+1) = col; %#ok<AGROW>
            expand_values{end+1} = val; %#ok<AGROW>
            vprintf(2, '  Expanding col %d with %d values: [%s]', col, length(val), num2str(val));
        end
    end
    
    vprintf(2, 'Found %d expandable columns', length(expand_cols));
    
    if isempty(expand_cols)
        % No expansion needed, return as-is
        trials_out = trials_in;
        return
    end
    
    % Generate all combinations of the expandable values
    % Use ndgrid to create all combinations
    n_expand = length(expand_cols);
    vprintf(2, 'n_expand = %d', n_expand);
    if n_expand == 1
        combos = expand_values{1}(:);  % column vector
        vprintf(2, 'Single expand: combos size %dx%d', size(combos));
    else
        % Create ndgrid arguments
        grid_args = cell(1, n_expand);
        for i = 1:n_expand
            grid_args{i} = expand_values{i}(:)';
            vprintf(2, 'grid_args{%d}: [%s]', i, num2str(grid_args{i}));
        end
        
        % Generate grid
        [grid{1:n_expand}] = ndgrid(grid_args{:});
        
        % Convert to combinations matrix
        combos = zeros(numel(grid{1}), n_expand);
        for i = 1:n_expand
            combos(:, i) = grid{i}(:);
        end
        vprintf(2, 'Multi expand: combos size %dx%d', size(combos));
    end
    
    % Create expanded trials matrix
    n_combos = size(combos, 1);
    trials_out = cell(n_combos, n_cols);
    
    for combo_idx = 1:n_combos
        % Start with the base trial
        for col = 1:n_cols
            if ismember(col, expand_cols)
                % This column is being expanded
                expand_idx = find(expand_cols == col);
                trials_out{combo_idx, col} = combos(combo_idx, expand_idx);
            else
                % This column stays the same
                trials_out{combo_idx, col} = trials_in{1, col};
            end
        end
    end
end
