function R = analyze(sess, settings, options)
% R = analyze(sess, settings)
% R = analyze(sess, settings, Window = "3-83")
% The whole v1 analysis of one session, as one plain struct: the staircase
% threshold, the session metrics, the psychometric fit, and QC flags.
%
% It NEVER THROWS for a bad session. Every stage runs on its own; one that
% cannot (a file that was not read, no parameter, a window that selects
% nothing, a fit that cannot be identified) leaves its numbers NaN, adds a
% sentence to Messages, and the stages after it still run where they can --
% the metrics need no parameter, for instance.
%
% Parameters:
%   settings - behavior.Settings
%   Window   - this session's trial window; "" (default) = settings.Window
%
% Returns:
%   R - struct:
%     Key, Subject, Project, Tags, Start   - the session's identity
%     Parameter     - the DATA field analysed ("" when there was none)
%     ParameterAuto - true when it was chosen from the candidates
%     Unit          - its unit, from the snapshot ("" when unknown)
%     SettingsHash  - settings.hash()
%     Window        - the window used, as TrialWindow.toText
%     Excluded      - (1,n) logical, exclusionMask's answer
%     NumIncluded   - trials left in
%     NumStimulus, NumCatch - included stimulus / catch trials
%     Threshold, ThresholdStd - the staircase's reversal threshold
%     ReversalCount, ReversalIdx, ReversalValues
%     MinBlockThreshold, MedianBlockThreshold, MeanBlockThreshold,
%     MaxBlockThreshold - over the sliding blocks of reversals
%     Weighted      - Results.Weighted ([] unless the correction is on)
%     Track         - struct TrialIndex, Value, Reversal: one entry per
%                     included stimulus trial (the overlay plot's line)
%     Metrics       - psychophysics.SessionMetrics Results
%     MetricsSummary - its summary() table
%     Fit           - common fit struct (behavior.fit.Builtin)
%     QC            - (1,:) string flags: the file's (QCFile) plus
%                     low_trials, high_abort_rate, few_reversals,
%                     no_parameter, fit_failed
%     Messages      - string column, one sentence per problem
%     Elapsed       - seconds taken
%
% See also: behavior.Session.staircase, behavior.Session.fit,
%   behavior.Session.exclusionMask

arguments
    sess (1,1) behavior.Session
    settings (1,1) behavior.Settings
    options.Window (1,1) string = ""
end

t0 = tic;
n = numel(sess.Data);
messages = strings(0, 1);

win = options.Window;
if win == "", win = settings.Window; end

R = struct( ...
    'Key', sess.Key, 'Subject', sess.Subject, 'Project', sess.Project, ...
    'Tags', sess.Tags, 'Start', sess.Start, ...
    'Parameter', "", 'ParameterAuto', false, 'Unit', "", ...
    'SettingsHash', settings.hash(), 'Window', win, ...
    'Excluded', true(1, n), 'NumIncluded', 0, 'NumStimulus', 0, 'NumCatch', 0, ...
    'Threshold', NaN, 'ThresholdStd', NaN, ...
    'ReversalCount', 0, 'ReversalIdx', zeros(1, 0), 'ReversalValues', zeros(1, 0), ...
    'MinBlockThreshold', NaN, 'MedianBlockThreshold', NaN, ...
    'MeanBlockThreshold', NaN, 'MaxBlockThreshold', NaN, ...
    'Weighted', [], ...
    'Track', struct('TrialIndex', zeros(1, 0), 'Value', zeros(1, 0), 'Reversal', false(1, 0)), ...
    'Metrics', [], 'MetricsSummary', table(), ...
    'Fit', behavior.fit.Builtin.empty(), ...
    'QC', strings(1, 0), 'Messages', strings(0, 1), 'Elapsed', 0);

noParameter = false;
ranStaircase = false;

% --- The file ----------------------------------------------------------------
if sess.Error ~= ""
    messages(end+1, 1) = "The file could not be read: " + sess.Error;
end
if settings.Analysis ~= "Staircase"
    messages(end+1, 1) = "Analysis """ + settings.Analysis + """ is not available in this version; the staircase is reported.";
end

% --- Trials ------------------------------------------------------------------
try
    [excl, info] = behavior.Session.exclusionMask(sess.Data, Window = win, ...
        ExcludeTest = settings.ExcludeTest, ExcludeTrialTypes = settings.ExcludeTrialTypes);
    R.Window = info.Window;
    R.Excluded = excl;
    R.NumIncluded = info.NumIncluded;
    if n > 0 && info.NumIncluded == 0
        why = strings(1, 0);
        if info.NumInWindow == 0, why(end+1) = "the window " + info.WindowLabel + " selects none of " + n; end
        if settings.ExcludeTest && info.NumTest > 0, why(end+1) = info.NumTest + " are test trials"; end
        if any(info.NumByType.Excluded), why(end+1) = "excluded trial types remove the rest"; end
        messages(end+1, 1) = "No trial is included (" + strjoin(why, "; ") + ").";
    elseif n == 0 && sess.Error == ""
        messages(end+1, 1) = "The session holds no trials.";
    end
catch ME
    excl = true(1, n);
    messages(end+1, 1) = "Window """ + win + """: " + string(ME.message);
end

% --- Metrics (need no parameter) -----------------------------------------------
try
    margs = settings.metricsArgs();
    M = psychophysics.SessionMetrics(sess.Data, margs{:}, ExcludedTrials = find(excl));
    R.Metrics = M.Results;
    R.MetricsSummary = M.summary();
    R.NumCatch = M.Results.N.Catch;
    R.NumStimulus = M.Results.N.Stimulus;
catch ME
    messages(end+1, 1) = "Session metrics: " + string(ME.message);
    M = psychophysics.SessionMetrics(struct([]));
    R.Metrics = M.Results;
    R.MetricsSummary = M.summary();
end

% --- Parameter -----------------------------------------------------------------
if sess.Error == ""
    [field, auto] = sess.resolveParameter(settings);
    R.Parameter = field;
    R.ParameterAuto = auto;
    if field == ""
        noParameter = true;
        messages(end+1, 1) = "No parameter is named and the session has no candidate field.";
    elseif ~ismember(field, sess.Fields)
        noParameter = true;
        messages(end+1, 1) = "The trial records have no field """ + field + """.";
    else
        R.Unit = sess.parameterMeta(field).Unit;
    end
end

% --- Staircase and fit -------------------------------------------------------
if sess.Error == "" && ~noParameter && any(~excl)
    try
        S = sess.staircase(settings, Window = win);
        ranStaircase = true;
        Z = S.Results;
        v = reshape(double(S.stimulusValues), 1, []);

        R.ReversalCount = Z.ReversalCount;
        R.ReversalIdx = reshape(Z.ReversalIdx, 1, []);
        R.ReversalValues = v(R.ReversalIdx);
        R.Threshold = localScalar(Z.Threshold);
        R.ThresholdStd = localScalar(Z.ThresholdStd);
        R.MinBlockThreshold = localScalar(Z.MinBlockThreshold);
        R.MedianBlockThreshold = localScalar(Z.MedianBlockThreshold);
        R.MeanBlockThreshold = localScalar(Z.MeanBlockThreshold);
        R.MaxBlockThreshold = localScalar(Z.MaxBlockThreshold);
        R.Weighted = Z.Weighted;

        idx = reshape(Z.StimulusTrialIdx, 1, []);
        R.NumStimulus = numel(idx);
        R.Track = struct('TrialIndex', idx, 'Value', v(idx), ...
            'Reversal', ismember(idx, R.ReversalIdx));

        if isnan(R.Threshold)
            if R.ReversalCount == 0
                messages(end+1, 1) = "The staircase has no reversals, so it gives no threshold.";
            elseif settings.Staircase.ApplyWeightedCorrection && ~isempty(Z.Weighted)
                messages(end+1, 1) = "Weighted correction: " + string(Z.Weighted.Message);
            else
                messages(end+1, 1) = "The staircase gives no threshold.";
            end
        end

        R.Fit = sess.fit(S, settings);
        if settings.Fit.Enabled && ~(R.Fit.Converged && R.Fit.Identifiable)
            messages(end+1, 1) = "Fit: " + R.Fit.Message;
        end
    catch ME
        messages(end+1, 1) = "Staircase: " + string(ME.message);
    end
end

R.Messages = messages;
R.QC = sess.qc_(R, settings, noParameter, ranStaircase);
R.Elapsed = toc(t0);

end




function x = localScalar(x)
% A Results number, NaN where the staircase left it [] (no reversals yet).
if isempty(x)
    x = NaN;
else
    x = double(x(1));
end
end
