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

    validationReport = obj.Protocol.validate();
    issueLines = localFormatValidationIssues_(validationReport);

    details = struct();
    details.statusMessage = sprintf('Compile failed: %s', compileMessage);
    details.nextStep = 'Review the compile details, fix the reported parameters or options, then compile again.';

    if isempty(obj.Protocol.COMPILED.writeparams)
        details.summaryText = 'Compile failed. No compiled preview available.';
    else
        details.summaryText = 'Compile failed. Preview shows the last successful compile.';
    end

    if isempty(issueLines)
        details.alertMessage = sprintf('Compile failed:\n%s', compileMessage);
        return
    end

    previewCount = min(4, numel(issueLines));
    details.alertMessage = sprintf('Compile failed:\n%s\n\nLikely issues to fix:\n- %s', ...
        compileMessage, strjoin(issueLines(1:previewCount), '\n- '));
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