function issues = expressionIssues_(obj, analysis)
% issues = expressionIssues_(obj, analysis)
%
% Map analyzeExpressions() findings to validate()-style issue entries
% {field, message, severity}. Shared by validate_internal (so compile blocks
% on expressions guaranteed to fail at runtime) and dryRunExpressions (so the
% Check Calculations tool shows the same findings).
%
% Severity: 2 for conditions that abort trial dispatch at runtime, 1 for
% silent-surprise hazards, 0 for informational notes.

arguments
    obj (1,1) epsych.Protocol
    analysis struct = obj.analyzeExpressions()
end

issues = struct('field', {}, 'message', {}, 'severity', {});

for k = 1:numel(analysis)
    a = analysis(k);
    % Dormant or Read-only expressions never evaluate at runtime, so even
    % fatal syntax problems are downgraded to warnings for them.
    willRun = ~a.multiLevelDormant && ~a.onReadParam;

    if a.hasSemicolon || a.hasAssignment
        if a.hasAssignment
            msg = 'Expression contains an assignment; expressions must be a single statement whose result becomes the value';
        else
            msg = 'Expression contains '';''; expressions must be a single statement';
        end
        issues(end+1) = localIssue_(a.fullName, msg, localSeverity_(willRun));
    end

    if a.bareSelfRef && willRun
        issues(end+1) = localIssue_(a.fullName, ...
            sprintf('Expression references its own name "%s", which is undefined at runtime and causes an evaluation error', a.param.Name), 2);
    end

    if a.onReadParam
        issues(end+1) = localIssue_(a.fullName, ...
            'Expression on a Read-access parameter never evaluates (read-only parameters cannot be assigned)', 1);
    end

    if a.qualifiedSelfRef
        issues(end+1) = localIssue_(a.fullName, ...
            'Expression references itself via Module.Name syntax; at runtime this silently reads its own previous value', 1);
    end

    for u = 1:numel(a.unresolvedRefs)
        issues(end+1) = localIssue_(a.fullName, ...
            sprintf('Reference "%s" does not match any parameter and will likely cause an evaluation error at runtime', a.unresolvedRefs{u}), 1);
    end

    for r = 1:numel(a.refs)
        if a.refs(r).ambiguous
            issues(end+1) = localIssue_(a.fullName, ...
                sprintf('Reference "%s" matches more than one parameter; the first match is used silently', a.refs(r).token), 1);
        end
        % The runtime dispatches in dependency order (hw.Parameter.
        % orderByDependencies), so a reference dispatched after its reader
        % survives only inside a reference cycle (or when resolution failed);
        % any such ref reads the previous trial's value.
        if a.refs(r).dispatchedAfter
            if a.refs(r).variesAcrossTrials
                issues(end+1) = localIssue_(a.fullName, ...
                    sprintf('References %s, which is dispatched later each trial and varies across trials; the expression uses the previous trial''s value', a.refs(r).targetFullName), 1);
            else
                issues(end+1) = localIssue_(a.fullName, ...
                    sprintf('References %s, which is dispatched later each trial; if its value changes at runtime (e.g. randomization enabled mid-session) the expression uses the previous trial''s value', a.refs(r).targetFullName), 0);
            end
        end
    end

    if ~isempty(a.cycleWith)
        issues(end+1) = localIssue_(a.fullName, ...
            sprintf('Expression reference cycle with %s; values depend on evaluation order', strjoin(a.cycleWith, ', ')), 1);
    end

    if a.multiLevelDormant
        issues(end+1) = localIssue_(a.fullName, ...
            'Multi-level parameter: the expression acted as a design-time level generator and is skipped at runtime', 1);
    end

    if a.selectsIndex
        if a.itemCount == 0
            issues(end+1) = localIssue_(a.fullName, ...
                sprintf('Expression selects an item by index, but %s has no items in its Value list', a.param.Name), ...
                localSeverity_(willRun));
        else
            issues(end+1) = localIssue_(a.fullName, ...
                sprintf(['Expression selects one of %d item(s) by index; the result must be a whole number ' ...
                'from 1 to %d (wrap fractional results in round() or fix())'], a.itemCount, a.itemCount), 0);
        end
    end

    if ~isempty(a.resolveError) && ~(a.hasSemicolon || a.hasAssignment)
        issues(end+1) = localIssue_(a.fullName, ...
            sprintf('Reference resolution failed: %s', a.resolveError), 1);
    end

    if ~a.isDispatched && ~a.onReadParam && ~a.multiLevelDormant
        if a.param.SetOnce
            issues(end+1) = localIssue_(a.fullName, ...
                'Set once at session start (Set Once is on); the expression evaluates at the first trial dispatch and when the parameter is set manually', 0);
        else
            issues(end+1) = localIssue_(a.fullName, ...
                'Not dispatched every trial (UpdateEveryTrial is off); the expression evaluates only when the parameter is set manually', 0);
        end
    end
end
end


function issue = localIssue_(field, message, severity)
issue = struct('field', field, 'message', message, 'severity', severity);
end


function sev = localSeverity_(willRun)
if willRun
    sev = 2;
else
    sev = 1;
end
end
