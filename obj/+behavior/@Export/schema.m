function S = schema()
% S = behavior.Export.schema()
% Every column of every export table, in order: the single source of truth
% tables() builds from and dictionary() describes.
%
% Returns:
%   S - table Table, Column, Type, Unit, Meaning (all string). Type is
%       "string", "double", "logical" or "datetime". The dynamic columns are
%       placeholders: tag_<k> and group_<name>.

R = {
    % --- sessions: one row per session ----------------------------------------
    'sessions', 'session_key',       'string',   '',        'Session file path relative to the data root, forward slashes; the key every table joins on'
    'sessions', 'file',              'string',   '',        'Session file name'
    'sessions', 'project',           'string',   '',        'Project folder'
    'sessions', 'project_path',      'string',   '',        'Folders between the data root and the project folder (A/B); empty when the project sits at the root'
    'sessions', 'subject',           'string',   '',        'Subject, from the folder the file is in'
    'sessions', 'tags',              'string',   '',        'File-name tags after the timestamp, joined with |'
    'sessions', 'tag_<k>',           'string',   '',        'Tag k of the file name; (none) where the session has fewer'
    'sessions', 'start_time',        'datetime', '',        'Session start, ISO 8601'
    'sessions', 'date',              'datetime', '',        'Session start day (midnight), ISO 8601'
    'sessions', 'box',               'double',   '',        'Box the session ran in'
    'sessions', 'paradigm',          'string',   '',        'Paradigm (trial function) the session ran'
    'sessions', 'protocol_version',  'string',   '',        'Version of the protocol file the session ran'
    'sessions', 'trials',            'double',   'trials',  'Trials recorded in the file'
    'sessions', 'trials_included',   'double',   'trials',  'Trials left in after the trial window and exclusions'
    'sessions', 'window',            'string',   '',        'Trial window analysed (all, last 100, 3-83, 20+)'
    'sessions', 'is_test',           'logical',  '',        'True when the session was a Preview (test) run'
    'sessions', 'hidden',            'logical',  '',        'True when the analyst hid the session'
    'sessions', 'hidden_reason',     'string',   '',        'Why the session was hidden, when recorded'
    'sessions', 'sex',               'string',   '',        'Subject sex as the session file or roster records it'
    'sessions', 'species',           'string',   '',        'Subject species as the session file or roster records it'
    'sessions', 'group_<name>',      'string',   '',        'Level of the manual grouping <name> this session belongs to; (none) when unassigned'
    'sessions', 'qc_flags',          'string',   '',        'Quality-control flags joined with |; empty when none'
    'sessions', 'comment',           'string',   '',        'Analyst comment on the session'
    'sessions', 'settings_hash',     'string',   '',        'Hash of the analysis settings the numbers were made with'
    % --- subjects: one row per subject ----------------------------------------
    'subjects', 'subject',           'string',   '',        'Subject'
    'subjects', 'project',           'string',   '',        'Project folder the subject is under'
    'subjects', 'n_sessions',        'double',   'sessions','Sessions of the subject in this export'
    'subjects', 'first_session',     'datetime', '',        'Start of the subject''s earliest session, ISO 8601'
    'subjects', 'last_session',      'datetime', '',        'Start of the subject''s latest session, ISO 8601'
    'subjects', 'sex',               'string',   '',        'Subject sex'
    'subjects', 'species',           'string',   '',        'Subject species'
    'subjects', 'roster_known',      'logical',  '',        'True when the subject roster knows the subject'
    'subjects', 'roster_projects',   'string',   '',        'Projects the roster lists the subject under'
    'subjects', 'roster_last_protocol', 'string','',        'Protocol the roster last recorded for the subject'
    'subjects', 'group_<name>',      'string',   '',        'Level of the manual grouping <name> when every session of the subject agrees, else empty'
    'subjects', 'comment',           'string',   '',        'Analyst comment on the subject'
    % --- thresholds: one row per session --------------------------------------
    'thresholds', 'session_key',     'string',   '',        'Session key (see sessions)'
    'thresholds', 'subject',         'string',   '',        'Subject'
    'thresholds', 'project',         'string',   '',        'Project folder'
    'thresholds', 'tag_<k>',         'string',   '',        'Tag k of the file name; (none) where the session has fewer'
    'thresholds', 'start_time',      'datetime', '',        'Session start, ISO 8601'
    'thresholds', 'parameter',       'string',   '',        'Parameter tracked by the staircase'
    'thresholds', 'unit',            'string',   '',        'Unit of the parameter; empty when unknown'
    'thresholds', 'threshold',       'double',   'parameter unit', 'Reversal threshold; empty when none could be computed'
    'thresholds', 'threshold_std',   'double',   'parameter unit', 'Standard deviation of the reversals the threshold averages'
    'thresholds', 'n_reversals',     'double',   'reversals','Reversals the staircase made'
    'thresholds', 'block_threshold_min',    'double', 'parameter unit', 'Smallest threshold over the sliding blocks of reversals'
    'thresholds', 'block_threshold_median', 'double', 'parameter unit', 'Median threshold over the sliding blocks of reversals'
    'thresholds', 'block_threshold_mean',   'double', 'parameter unit', 'Mean threshold over the sliding blocks of reversals'
    'thresholds', 'block_threshold_max',    'double', 'parameter unit', 'Largest threshold over the sliding blocks of reversals'
    'thresholds', 'weighted_threshold',     'double', 'parameter unit', 'Threshold corrected for asymmetric steps; empty unless the correction is on'
    'thresholds', 'n_included',      'double',   'trials',  'Trials included in the analysis'
    'thresholds', 'n_stimulus',      'double',   'trials',  'Included stimulus trials'
    'thresholds', 'n_catch',         'double',   'trials',  'Included catch trials'
    'thresholds', 'window',          'string',   '',        'Trial window analysed'
    'thresholds', 'settings_hash',   'string',   '',        'Hash of the analysis settings'
    % --- fits: one row per session --------------------------------------------
    'fits', 'session_key',           'string',   '',        'Session key (see sessions)'
    'fits', 'engine',                'string',   '',        'Fitting engine'
    'fits', 'shape',                 'string',   '',        'Psychometric function shape'
    'fits', 'threshold_fit',         'double',   'parameter unit', 'Level at the fit criterion; empty when the fit failed'
    'fits', 'alpha',                 'double',   'parameter unit', 'Location parameter of the fitted function'
    'fits', 'beta',                  'double',   '',        'Slope parameter of the fitted function'
    'fits', 'gamma',                 'double',   'proportion','Guess rate (lower asymptote)'
    'fits', 'lambda',                'double',   'proportion','Lapse rate (distance of the upper asymptote from 1)'
    'fits', 'converged',             'logical',  '',        'True when the optimizer converged'
    'fits', 'identifiable',          'logical',  '',        'True when the data could support the fit'
    'fits', 'n_levels',              'double',   'levels',  'Distinct stimulus levels fitted'
    'fits', 'n_scored',              'double',   'trials',  'Scored trials over all levels'
    'fits', 'ci_lo',                 'double',   'parameter unit', 'Lower bound of the threshold confidence interval'
    'fits', 'ci_hi',                 'double',   'parameter unit', 'Upper bound of the threshold confidence interval'
    'fits', 'message',               'string',   '',        'Why the fit is missing or doubtful; empty when fine'
    % --- metrics: one row per session -----------------------------------------
    'metrics', 'session_key',        'string',   '',        'Session key (see sessions)'
    'metrics', 'n_total',            'double',   'trials',  'Trials in the metrics window'
    'metrics', 'n_stimulus',         'double',   'trials',  'Stimulus trials'
    'metrics', 'n_catch',            'double',   'trials',  'Catch trials'
    'metrics', 'n_hit',              'double',   'trials',  'Hits'
    'metrics', 'n_miss',             'double',   'trials',  'Misses'
    'metrics', 'n_fa',               'double',   'trials',  'False alarms'
    'metrics', 'n_cr',               'double',   'trials',  'Correct rejections'
    'metrics', 'n_abort',            'double',   'trials',  'Aborted trials'
    'metrics', 'hit_rate',           'double',   'proportion','Hit rate'
    'metrics', 'fa_rate',            'double',   'proportion','False-alarm rate'
    'metrics', 'cr_rate',            'double',   'proportion','Correct-rejection rate'
    'metrics', 'abort_rate',         'double',   'proportion','Aborted trials over all trials'
    'metrics', 'd_prime',            'double',   'z',       'Sensitivity d prime'
    'metrics', 'a_prime',            'double',   '',        'Nonparametric sensitivity A prime'
    'metrics', 'criterion',          'double',   'z',       'Response criterion c'
    'metrics', 'b_prime_prime',      'double',   '',        'Nonparametric bias B double prime'
    % --- reversals: one row per reversal --------------------------------------
    'reversals', 'session_key',      'string',   '',        'Session key (see sessions)'
    'reversals', 'reversal_index',   'double',   '',        'Position of the reversal within its session, from 1'
    'reversals', 'trial_index',      'double',   '',        'Trial of the session the reversal happened on'
    'reversals', 'value',            'double',   'parameter unit', 'Parameter value at the reversal'
    % --- notes: one row per session with notes ---------------------------------
    'notes', 'session_key',          'string',   '',        'Session key (see sessions)'
    'notes', 'text',                 'string',   '',        'The operator''s notes for the session, one line per note'
    };

S = cell2table(R, 'VariableNames', {'Table', 'Column', 'Type', 'Unit', 'Meaning'});
for v = S.Properties.VariableNames
    S.(v{1}) = string(S.(v{1}));
end
end
