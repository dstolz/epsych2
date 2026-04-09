function report = validate_internal(obj)
    % validate_internal(obj)
    %
    % Validate protocol for structural and logical errors.
    % Returns a struct array with validation results.
    %
    % Report fields:
    %   field    - Name of field/parameter with issue
    %   message  - Human-readable error/warning message
    %   severity - 0 = info, 1 = warning, 2 = error
    
    report = struct('field', {}, 'message', {}, 'severity', {});
    idx = 1;
    
    % === Check: No interfaces ===
    if isempty(obj.Interfaces)
        report(idx).field = 'Interfaces';
        report(idx).message = 'No interfaces defined';
        report(idx).severity = 2;  % error
        idx = idx + 1;
    end
    
    % === Check: No writable parameters ===
    write_param_count = 0;
    for iface_idx = 1:length(obj.Interfaces)
        iface = obj.Interfaces(iface_idx);
        for mod_idx = 1:length(iface.Module)
            for param_idx = 1:length(iface.Module(mod_idx).Parameters)
                p = iface.Module(mod_idx).Parameters(param_idx);
                if p.Visible && ~strcmp(p.Access, 'Read')
                    write_param_count = write_param_count + 1;
                end
            end
        end
    end
    
    if write_param_count == 0
        report(idx).field = 'Parameters';
        report(idx).message = 'No writable parameters defined';
        report(idx).severity = 2;  % error
        idx = idx + 1;
    end
    
    % === Check: Options ===
    if ~isfinite(obj.Options.ISI) || obj.Options.ISI <= 0
        report(idx).field = 'Options.ISI';
        report(idx).message = sprintf('ISI must be positive (got %.1f)', obj.Options.ISI);
        report(idx).severity = 2;
        idx = idx + 1;
    end
    
    if ~isfinite(obj.Options.numReps) || (obj.Options.numReps < 1 && ~isinf(obj.Options.numReps))
        report(idx).field = 'Options.numReps';
        report(idx).message = sprintf('numReps must be >= 1 (got %.1f)', obj.Options.numReps);
        report(idx).severity = 2;
        idx = idx + 1;
    end
    
    % === Check: Trial selection function ===
    if ~isempty(obj.Options.trialFunc) && ~isempty(obj.Options.trialFunc)
        if ischar(obj.Options.trialFunc)
            try
                func_handle = str2func(obj.Options.trialFunc);
                % Try to get function info; if it fails, mark as error
                finfo = functions(func_handle);
                if isempty(finfo)
                    report(idx).field = 'Options.trialFunc';
                    report(idx).message = sprintf('Trial function "%s" not found on path', obj.Options.trialFunc);
                    report(idx).severity = 2;
                    idx = idx + 1;
                end
            catch
                report(idx).field = 'Options.trialFunc';
                report(idx).message = sprintf('Trial function "%s" not accessible', obj.Options.trialFunc);
                report(idx).severity = 2;
                idx = idx + 1;
            end
        end
    end
    
    % === Check: Parameter bounds ===
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
                
                full_name = sprintf('%s.%s.%s', iface_type, module.Name, p.Name);
                
                % Check Min <= Max
                if p.Min > p.Max
                    report(idx).field = full_name;
                    report(idx).message = sprintf('Min (%.2f) > Max (%.2f)', p.Min, p.Max);
                    report(idx).severity = 2;
                    idx = idx + 1;
                end

                if p.isRandom && (~isfinite(p.Min) || ~isfinite(p.Max))
                    report(idx).field = full_name;
                    report(idx).message = 'Random parameters must have finite Min and Max values';
                    report(idx).severity = 2;
                    idx = idx + 1;
                end
                
                % Check value within bounds (if scalar)
                if isnumeric(p.Value) && isscalar(p.Value)
                    if p.Value < p.Min || p.Value > p.Max
                        report(idx).field = full_name;
                        report(idx).message = sprintf('Value %.2f outside bounds [%.2f, %.2f]', ...
                            p.Value, p.Min, p.Max);
                        report(idx).severity = 1;  % warning
                        idx = idx + 1;
                    end
                end
            end
        end
    end
    
    % Return empty if no issues
    if idx == 1
        report = struct('field', {}, 'message', {}, 'severity', {});
    end
end
