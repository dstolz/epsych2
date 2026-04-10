function refreshExpressionValues(obj)
    parameters = obj.getAllParameters();
    expressionParameters = parameters(arrayfun(@(p) obj.hasParameterExpression(p), parameters));
    if isempty(expressionParameters)
        pairErrors = obj.validatePairedParameterLengths();
        obj.setExpressionErrors(pairErrors);
        if ~isempty(pairErrors)
            obj.setStatus(pairErrors(1).message, ...
                'Fix the highlighted parameter values or expressions, then compile again.');
        end
        return
    end

    pending = expressionParameters;
    maxPasses = max(1, numel(pending));
    lastErrors = struct('parameter', {}, 'message', {});

    for passIdx = 1:maxPasses
        nextPending = hw.Parameter.empty(1, 0);
        progressMade = false;
        currentErrors = struct('parameter', {}, 'message', {});

        for paramIdx = 1:numel(pending)
            parameter = pending(paramIdx);
            expressionText = obj.getParameterExpression(parameter);
            try
                obj.evaluateAndApplyParameterExpression(parameter, expressionText);
                progressMade = true;
            catch ME
                nextPending(end + 1) = parameter; %#ok<AGROW>
                currentErrors(end + 1).parameter = parameter; %#ok<AGROW>
                currentErrors(end).message = sprintf('Expression error for %s: %s', parameter.Name, ME.message);
            end
        end

        if isempty(nextPending)
            pairErrors = obj.validatePairedParameterLengths();
            obj.setExpressionErrors(pairErrors);
            if ~isempty(pairErrors)
                obj.setStatus(pairErrors(1).message, ...
                    'Fix the highlighted parameter values or expressions, then compile again.');
            end
            return
        end
        if ~progressMade
            obj.setExpressionErrors(currentErrors);
            if ~isempty(currentErrors)
                obj.setStatus(currentErrors(1).message, ...
                    'Fix the highlighted parameter values or expressions, then compile again.');
            end
            return
        end
        pending = nextPending;
        lastErrors = currentErrors;
    end

    obj.setExpressionErrors(lastErrors);
    if ~isempty(lastErrors)
        obj.setStatus(lastErrors(1).message, ...
            'Fix the highlighted parameter values or expressions, then compile again.');
    end
end

