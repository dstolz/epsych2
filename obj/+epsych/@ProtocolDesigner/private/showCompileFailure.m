function showCompileFailure(obj, compileError, alertTarget)
    % showCompileFailure(obj, compileError, alertTarget)
    % Report a compile failure with validation context and preview guidance.
    %
    % Parameters:
    % 	compileError	- MException raised during protocol compilation.
    % 	alertTarget	- Figure used for the compile failure alert.
    if nargin < 3 || isempty(alertTarget)
        alertTarget = obj.Figure;
    end

    details = localBuildCompileFailureDetails_(obj, compileError);

    if ~isempty(obj.LabelCompileSummary) && isvalid(obj.LabelCompileSummary)
        obj.LabelCompileSummary.Text = details.summaryText;
    end

    obj.setStatus(details.statusMessage, details.nextStep);

    if ~isempty(alertTarget) && isvalid(alertTarget)
        uialert(alertTarget, details.alertMessage, 'Compile Failed');
    end
end

function details = localBuildCompileFailureDetails_(obj, compileError)
    compileMessage = strtrim(char(string(compileError.message)));
    if isempty(compileMessage)
        compileMessage = 'Unknown compile error.';
    end

    duplicateSection = '';
    duplicateNamePreview = '';
    duplicateLines = localFindDuplicateCompiledParameterNames_(obj.Protocol);
    if ~isempty(duplicateLines)
        duplicateSection = sprintf('\n\nDuplicated compiled parameter names:\n- %s', strjoin(duplicateLines, '\n- '));
        duplicateNamePreview = localBuildDuplicateNamePreview_(duplicateLines);
    end

    validationReport = obj.Protocol.validate();
    issueLines = localFormatValidationIssues_(validationReport);

    details = struct();
    if isempty(duplicateNamePreview)
        details.statusMessage = sprintf('Compile failed: %s', compileMessage);
    else
        details.statusMessage = sprintf('Compile failed: Duplicate parameter names (%s).', duplicateNamePreview);
    end
    details.nextStep = 'Review the compile details, fix the reported parameters or options, then compile again.';

    if isempty(obj.Protocol.COMPILED.parameters)
        details.summaryText = 'Compile failed. No compiled preview available.';
    else
        details.summaryText = 'Compile failed. Preview shows the last successful compile.';
    end

    if isempty(issueLines)
        details.alertMessage = sprintf('Compile failed:\n%s%s', compileMessage, duplicateSection);
        return
    end

    previewCount = min(4, numel(issueLines));
    details.alertMessage = sprintf('Compile failed:\n%s%s\n\nLikely issues to fix:\n- %s', ...
        compileMessage, duplicateSection, strjoin(issueLines(1:previewCount), '\n- '));
end

function duplicateLines = localFindDuplicateCompiledParameterNames_(protocol)
    duplicateLines = {};
    names = {};
    locations = {};

    for ifaceIdx = 1:numel(protocol.Interfaces)
        iface = protocol.Interfaces(ifaceIdx);
        interfaceType = char(iface.Type);

        for moduleIdx = 1:numel(iface.Module)
            module = iface.Module(moduleIdx);

            for paramIdx = 1:numel(module.Parameters)
                parameter = module.Parameters(paramIdx);
                if ~parameter.Visible || strcmp(parameter.Access, 'Read')
                    continue
                end

                names{end + 1} = parameter.Name;
                locations{end + 1} = sprintf('%s.%s (interface: %s)', module.Name, parameter.Name, interfaceType);
            end
        end
    end

    if isempty(names)
        return
    end

    [uniqueNames, ~, groupIdx] = unique(names);
    counts = accumarray(groupIdx(:), 1);
    duplicateGroupIdx = find(counts > 1);
    for idx = 1:numel(duplicateGroupIdx)
        group = duplicateGroupIdx(idx);
        name = uniqueNames{group};
        matchIdx = find(groupIdx == group);
        duplicateLines{end + 1} = sprintf('%s (%d): %s', ...
            name, numel(matchIdx), strjoin(locations(matchIdx), '; '));
    end
end

function previewText = localBuildDuplicateNamePreview_(duplicateLines)
    names = cell(1, numel(duplicateLines));
    for idx = 1:numel(duplicateLines)
        line = duplicateLines{idx};
        sep = strfind(line, ' (');
        if isempty(sep)
            names{idx} = line;
        else
            names{idx} = line(1:sep(1)-1);
        end
    end

    maxShown = min(3, numel(names));
    shown = names(1:maxShown);
    if numel(names) > maxShown
        previewText = sprintf('%s, +%d more', strjoin(shown, ', '), numel(names) - maxShown);
    else
        previewText = strjoin(shown, ', ');
    end
end

function issueLines = localFormatValidationIssues_(validationReport)
    issueLines = {};
    if isempty(validationReport)
        return
    end

    severities = [validationReport.severity];
    order = [find(severities >= 2), find(severities == 1), find(severities == 0)];
    order = unique(order, 'stable');
    for idx = order
        fieldName = strtrim(char(string(validationReport(idx).field)));
        message = strtrim(char(string(validationReport(idx).message)));
        if isempty(fieldName)
            issueLines{end + 1} = message; %#ok<AGROW>
        else
            issueLines{end + 1} = sprintf('%s: %s', fieldName, message); %#ok<AGROW>
        end
    end
end