function report = validate_internal(obj)
% report = validate_internal(obj)
%
% Internal validation implementation. Checks protocol structure and
% parameter settings for errors and warnings.
%
% Returns:
%   report - struct array with fields:
%              field    - Name of field/parameter with issue
%              message  - Human-readable description
%              severity - 0=info, 1=warning, 2=error

report = struct('field', {}, 'message', {}, 'severity', {});
idx = 1;
pairGroups = struct('name', {}, 'members', {}, 'valueCounts', {});

if isempty(obj.Interfaces)
    report(idx).field = 'Interfaces';
    report(idx).message = 'No interfaces defined';
    report(idx).severity = 2;
    idx = idx + 1;
end

writeParamCount = 0;
for ifaceIdx = 1:length(obj.Interfaces)
    iface = obj.Interfaces(ifaceIdx);
    for modIdx = 1:length(iface.Module)
        for paramIdx = 1:length(iface.Module(modIdx).Parameters)
            p = iface.Module(modIdx).Parameters(paramIdx);
            if p.Visible && ~strcmp(p.Access, 'Read')
                writeParamCount = writeParamCount + 1;
            end
        end
    end
end

if writeParamCount == 0
    report(idx).field = 'Parameters';
    report(idx).message = 'No writable parameters defined';
    report(idx).severity = 2;
    idx = idx + 1;
end

if ~isempty(obj.Options.trialFunc)
    if ischar(obj.Options.trialFunc)
        try
            funcHandle = str2func(obj.Options.trialFunc);
            info = functions(funcHandle);
            if isempty(info.file)
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
    elseif isa(obj.Options.trialFunc, 'function_handle')
        info = functions(obj.Options.trialFunc);
        if isempty(info.file)
            report(idx).field = 'Options.trialFunc';
            report(idx).message = 'Trial function handle refers to an unresolved or anonymous function';
            report(idx).severity = 1;
            idx = idx + 1;
        end
    end
end

for ifaceIdx = 1:length(obj.Interfaces)
    iface = obj.Interfaces(ifaceIdx);
    ifaceType = char(iface.Type);
    for modIdx = 1:length(iface.Module)
        module = iface.Module(modIdx);
        for paramIdx = 1:length(module.Parameters)
            p = module.Parameters(paramIdx);
            if ~p.Visible
                continue
            end

            fullName = sprintf('%s.%s.%s', ifaceType, module.Name, p.Name);

            if ~strcmp(p.Access, 'Read') && isempty(p.Values)
                report(idx).field = fullName;
                report(idx).message = sprintf('Parameter "%s" has no Values defined', p.Name);
                report(idx).severity = 2;
                idx = idx + 1;
                continue
            end

            if p.Min > p.Max
                report(idx).field = fullName;
                report(idx).message = sprintf('Min (%.2f) > Max (%.2f)', p.Min, p.Max);
                report(idx).severity = 2;
                idx = idx + 1;
            end

            if p.isRandom && (~isfinite(p.Min) || ~isfinite(p.Max))
                report(idx).field = fullName;
                report(idx).message = 'Random parameters must have finite Min and Max values';
                report(idx).severity = 2;
                idx = idx + 1;
            end

            if isequal(p.Type, 'File')
                % All levels in Values must be file path strings
                validFileValues = all(cellfun(@(v) ischar(v) || (isstring(v) && isscalar(v)), p.Values));
                if isempty(p.Values) || ~validFileValues
                    report(idx).field = fullName;
                    report(idx).message = 'File parameters must contain a file path or a cell array of file paths';
                    report(idx).severity = 2;
                    idx = idx + 1;
                end
            else
                % Check all numeric levels are within [Min, Max]
                numericLevels = p.Values(cellfun(@(v) isnumeric(v) && isscalar(v), p.Values));
                for lvl = numericLevels
                    v = lvl{1};
                    if v < p.Min || v > p.Max
                        report(idx).field = fullName;
                        report(idx).message = sprintf('Value %.2f outside bounds [%.2f, %.2f]', v, p.Min, p.Max);
                        report(idx).severity = 1;
                        idx = idx + 1;
                    end
                end
            end

            if strcmp(p.Access, 'Read')
                continue
            end

            pairName = obj.getParameterPairName_(p);
            if isempty(pairName)
                continue
            end

            valueCount = numel(p.Values);
            groupIdx = find(strcmp({pairGroups.name}, pairName), 1);
            if isempty(groupIdx)
                pairGroups(end + 1).name = pairName; %#ok<AGROW>
                pairGroups(end).members = {fullName};
                pairGroups(end).valueCounts = valueCount;
            else
                pairGroups(groupIdx).members{end + 1} = fullName;
                pairGroups(groupIdx).valueCounts(end + 1) = valueCount;
            end
        end
    end
end

for groupIdx = 1:numel(pairGroups)
    valueCounts = pairGroups(groupIdx).valueCounts;
    if any(valueCounts ~= valueCounts(1))
        memberNames = cellfun(@(name) char(string(name)), pairGroups(groupIdx).members, 'UniformOutput', false);
        memberSummary = arrayfun(@(i) sprintf('%s (%d)', memberNames{i}, double(valueCounts(i))), ...
            1:numel(memberNames), 'UniformOutput', false);
        report(idx).field = sprintf('Pair.%s', pairGroups(groupIdx).name);
        report(idx).message = sprintf('Paired parameters must have the same number of values: %s', ...
            strjoin(memberSummary, ', '));
        report(idx).severity = 2;
        idx = idx + 1;
    end
end

if idx == 1
    report = struct('field', {}, 'message', {}, 'severity', {});
end
end
