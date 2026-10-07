function Tbls = tables(T, results, options)
% Tbls = behavior.Export.tables(T, results)
% Tbls = behavior.Export.tables(T, results, Tables = ["sessions" "thresholds"], Subjects = catalog.Subjects)
% Tidy tables of an analysis, one row per observation, snake_case columns,
% built FROM behavior.Export.schema.
%
% Parameters:
%   T        - behavior.Aggregate.thresholds table (one row per session).
%   results  - the matching behavior.Session.analyze results (struct array
%              or cell array, matched to the rows by Key); [] is allowed, in
%              which case the fits and metrics tables carry what T holds and
%              the reversals table is empty.
%   Tables   - which tables to build (default all of behavior.Export.TABLES).
%   Subjects - the catalog's Subjects table; adds sex, species and the
%              roster columns to the subjects table. Optional.
%
% Returns:
%   Tbls - struct with one table per requested name. Every table has exactly
%          the schema's columns (tag_<k> and group_<name> expanded from T),
%          also when it has no rows. A value the sources lack is empty text,
%          NaN, false or NaT.

arguments
    T table
    results = []
    options.Tables (1,:) string {mustBeMember(options.Tables, ["sessions" "subjects" "thresholds" "fits" "metrics" "reversals" "notes"])} = behavior.Export.TABLES
    options.Subjects table = table()
end

n = height(T);
R = localResults(results);
ri = zeros(n, 1);
if ~isempty(R) && n > 0
    [~, ri] = ismember(string(T.Key), reshape(string({R.Key}), [], 1));
end

dyn = localDynamic(T);
S = behavior.Export.schema();
want = behavior.Export.TABLES(ismember(behavior.Export.TABLES, options.Tables));

Tbls = struct();
for name = want
    switch name
        case "sessions",   [src, rows] = localSessions(T, n, dyn);
        case "subjects",   [src, rows] = localSubjects(T, n, dyn, options.Subjects);
        case "thresholds", [src, rows] = localThresholds(T, n, dyn);
        case "fits",       [src, rows] = localFits(T, n, R, ri);
        case "metrics",    [src, rows] = localMetrics(T, n, R, ri);
        case "reversals",  [src, rows] = localReversals(R, ri);
        case "notes",      [src, rows] = localNotes(T, n);
    end
    Tbls.(name) = localAssemble(name, src, rows, dyn, S);
end

end


% --- Assembly from the schema --------------------------------------------------

function X = localAssemble(name, src, n, dyn, S)
% The table's columns, in schema order, placeholders expanded.
rows = S(S.Table == name, :);
X = table();
for i = 1:height(rows)
    col = rows.Column(i);
    type = rows.Type(i);
    if col == "tag_<k>"
        names = "tag_" + (1:dyn.NumTags);
    elseif startsWith(col, "group_<")
        names = "group_" + dyn.Groups;
    else
        names = col;
    end
    for c = reshape(names, 1, [])
        if isfield(src, c)
            v = src.(c);
        else
            v = [];
        end
        X.(c) = localCoerce(v, type, n);
    end
end
if isempty(X.Properties.VariableNames)
    X = table.empty(n, 0);
end
end


function v = localCoerce(v, type, n)
% One column of the schema's type and n rows; [] (absent) is the default.
switch type
    case "string"
        if isempty(v), v = strings(n, 1); end
        if iscell(v)
            v = cellfun(@(x) strjoin(reshape(string(x), 1, []), "|"), v);
        end
        v = string(v);
        v(ismissing(v)) = "";
    case "double"
        if isempty(v), v = nan(n, 1); end
        v = double(v);
    case "logical"
        if isempty(v), v = false(n, 1); end
        v = logical(v);
    case "datetime"
        if isempty(v), v = NaT(n, 1); end
end
v = reshape(v, [], 1);
if numel(v) ~= n
    error('behavior:Export:ColumnLength', ...
        'A source column has %d values for %d rows.', numel(v), n);
end
end


function dyn = localDynamic(T)
% The tag positions and manual groupings T carries.
vars = string(T.Properties.VariableNames);
tagVars = vars(~cellfun(@isempty, regexp(vars, '^Tag\d+$', 'once')));
dyn.NumTags = max(1, numel(tagVars));
groupVars = vars(startsWith(vars, "Group_"));
dyn.GroupVars = groupVars;
dyn.Groups = lower(extractAfter(groupVars, "Group_"));
end


function R = localResults(results)
% The results as one column struct array, whatever shape they came in.
if iscell(results)
    results = results(~cellfun(@isempty, results));
    if isempty(results)
        R = struct([]);
    else
        R = [results{:}];
    end
elseif isstruct(results)
    R = results;
else
    R = struct([]);
end
R = reshape(R, [], 1);
end


function v = localGet(T, name, type, ~)
% T.(name) as its column, [] when T lacks it (localCoerce supplies the default).
v = [];
if ismember(name, T.Properties.VariableNames)
    v = T.(name);
    if strcmp(type, 'datetime') && ~isdatetime(v)
        v = [];
    end
end
end


function x = localNum(s, f)
% One double from a struct field, NaN when absent or empty.
x = NaN;
if isstruct(s) && isscalar(s) && isfield(s, f)
    v = s.(f);
    if ~isempty(v) && (isnumeric(v) || islogical(v))
        x = double(v(1));
    end
end
end


function src = localTagsAndGroups(src, T, dyn)
% tag_k and group_<name> columns from Tag<k> and Group_<Name>.
for k = 1:dyn.NumTags
    src.("tag_" + k) = localGet(T, "Tag" + k, 'string', height(T));
end
for g = 1:numel(dyn.GroupVars)
    src.("group_" + dyn.Groups(g)) = T.(dyn.GroupVars(g));
end
end


% --- One builder per table: returns the source columns and the row count -----------

function [src, n] = localSessions(T, n, dyn)
g = @(name, type) localGet(T, name, type, n);
key = g('Key', 'string');
src.session_key = key;
src.file = regexprep(string(key), '^.*[/\\]', '');
src.project = g('Project', 'string');
src.project_path = g('ProjectPath', 'string');
src.subject = g('Subject', 'string');
src.tags = g('TagText', 'string');
src = localTagsAndGroups(src, T, dyn);
src.start_time = g('Start', 'datetime');
src.date = g('Date', 'datetime');
src.box = g('BoxID', 'double');
src.paradigm = g('Paradigm', 'string');
src.protocol_version = g('ProtocolVersion', 'string');
src.trials = g('Trials', 'double');
src.trials_included = g('NumIncluded', 'double');
src.window = g('Window', 'string');
qcFile = g('QCFile', 'string');
if isempty(qcFile), qcFile = strings(n, 1); end
src.is_test = contains(reshape(string(qcFile), [], 1), "test_mode");
src.hidden = g('Hidden', 'logical');
src.hidden_reason = g('HiddenReason', 'string');
src.sex = g('SubjectSex', 'string');
src.species = g('SubjectSpecies', 'string');
src.qc_flags = g('QC', 'string');
src.comment = g('Comment', 'string');
src.settings_hash = g('SettingsHash', 'string');
end


function [src, rows] = localSubjects(T, n, dyn, Sub)
% One row per (Project, Subject) in T, in order of first appearance.
rows = 0;
src = struct();
if n == 0, return, end
project = reshape(string(T.Project), [], 1);
subject = reshape(string(T.Subject), [], 1);
[~, ia, grp] = unique(project + char(31) + subject, 'stable');
rows = numel(ia);

start = localGet(T, 'Start', 'datetime', n);
if isempty(start), start = NaT(n, 1); end
sex = localGet(T, 'SubjectSex', 'string', n);
species = localGet(T, 'SubjectSpecies', 'string', n);
comment = localGet(T, 'SubjectComment', 'string', n);
if isempty(sex), sex = strings(n, 1); end
if isempty(species), species = strings(n, 1); end
if isempty(comment), comment = strings(n, 1); end

subKey = strings(0, 1);
if istable(Sub) && height(Sub) > 0 && all(ismember(["Subject" "Project"], Sub.Properties.VariableNames))
    subKey = string(Sub.Project) + char(31) + string(Sub.Subject);
end

src.subject = subject(ia);
src.project = project(ia);
nSess = zeros(rows, 1);
first = NaT(rows, 1);
last = NaT(rows, 1);
sx = strings(rows, 1);
sp = strings(rows, 1);
cm = strings(rows, 1);
known = false(rows, 1);
rproj = strings(rows, 1);
rlast = strings(rows, 1);
groups = struct();
for g = 1:numel(dyn.GroupVars)
    groups.(dyn.Groups(g)) = strings(rows, 1);
end
for i = 1:rows
    in = grp == i;
    nSess(i) = sum(in);
    if any(~isnat(start(in)))
        first(i) = min(start(in));
        last(i) = max(start(in));
    end
    sx(i) = localFirstText(sex(in));
    sp(i) = localFirstText(species(in));
    cm(i) = localFirstText(comment(in));
    r = find(subKey == project(ia(i)) + char(31) + subject(ia(i)), 1);
    if ~isempty(r)
        if sx(i) == "", sx(i) = localSubjectsText(Sub, r, 'Sex'); end
        if sp(i) == "", sp(i) = localSubjectsText(Sub, r, 'Species'); end
        known(i) = ismember('RosterKnown', Sub.Properties.VariableNames) && logical(Sub.RosterKnown(r));
        rproj(i) = localSubjectsText(Sub, r, 'RosterProjects');
        rlast(i) = localSubjectsText(Sub, r, 'RosterLastProtocol');
    end
    for g = 1:numel(dyn.GroupVars)
        levels = unique(string(T.(dyn.GroupVars(g))(in)));
        if isscalar(levels)
            groups.(dyn.Groups(g))(i) = levels;
        end
    end
end
src.n_sessions = nSess;
src.first_session = first;
src.last_session = last;
src.sex = sx;
src.species = sp;
src.roster_known = known;
src.roster_projects = rproj;
src.roster_last_protocol = rlast;
for g = 1:numel(dyn.GroupVars)
    src.("group_" + dyn.Groups(g)) = groups.(dyn.Groups(g));
end
src.comment = cm;
end


function s = localFirstText(v)
% The first non-empty text of a column, "" when there is none.
v = string(v);
v = v(~ismissing(v) & strlength(v) > 0);
if isempty(v), s = ""; else, s = v(1); end
end


function s = localSubjectsText(Sub, r, name)
s = "";
if ismember(name, Sub.Properties.VariableNames)
    s = string(Sub.(name)(r));
    if ismissing(s), s = ""; end
end
end


function [src, n] = localThresholds(T, n, dyn)
g = @(name, type) localGet(T, name, type, n);
src.session_key = g('Key', 'string');
src.subject = g('Subject', 'string');
src.project = g('Project', 'string');
src = localTagsAndGroups(src, T, dyn);
src.start_time = g('Start', 'datetime');
src.parameter = g('Parameter', 'string');
src.unit = g('Unit', 'string');
src.threshold = g('Threshold', 'double');
src.threshold_std = g('ThresholdStd', 'double');
src.n_reversals = g('ReversalCount', 'double');
src.block_threshold_min = g('MinBlockThreshold', 'double');
src.block_threshold_median = g('MedianBlockThreshold', 'double');
src.block_threshold_mean = g('MeanBlockThreshold', 'double');
src.block_threshold_max = g('MaxBlockThreshold', 'double');
src.weighted_threshold = g('WeightedThreshold', 'double');
src.n_included = g('NumIncluded', 'double');
src.n_stimulus = g('NumStimulus', 'double');
src.n_catch = g('NumCatch', 'double');
src.window = g('Window', 'string');
src.settings_hash = g('SettingsHash', 'string');
end


function [src, n] = localFits(T, n, R, ri)
g = @(name, type) localGet(T, name, type, n);
src.session_key = g('Key', 'string');
src.threshold_fit = g('FitThreshold', 'double');
src.alpha = g('FitAlpha', 'double');
src.beta = g('FitBeta', 'double');
src.converged = g('FitConverged', 'logical');
src.ci_lo = g('FitCILo', 'double');
src.ci_hi = g('FitCIHi', 'double');

engine = strings(n, 1); shape = strings(n, 1); message = strings(n, 1);
gamma = nan(n, 1); lambda = nan(n, 1);
identifiable = false(n, 1);
nLevels = nan(n, 1); nScored = nan(n, 1);
for k = 1:n
    if ri(k) == 0, continue, end
    F = R(ri(k)).Fit;
    if ~isstruct(F) || ~isscalar(F), continue, end
    if isfield(F, 'Engine'), engine(k) = string(F.Engine); end
    if isfield(F, 'Shape'), shape(k) = string(F.Shape); end
    if isfield(F, 'Message'), message(k) = strjoin(reshape(string(F.Message), 1, []), " "); end
    gamma(k) = localNum(F, 'Gamma');
    lambda(k) = localNum(F, 'Lambda');
    if isfield(F, 'Identifiable') && isscalar(F.Identifiable)
        identifiable(k) = logical(F.Identifiable);
    end
    if isfield(F, 'Levels') && ~isempty(F.Levels)
        nLevels(k) = numel(F.Levels);
    end
    if isfield(F, 'NumTotal') && ~isempty(F.NumTotal)
        nScored(k) = sum(double(F.NumTotal), 'omitnan');
    end
end
src.engine = engine;
src.shape = shape;
src.gamma = gamma;
src.lambda = lambda;
src.identifiable = identifiable;
src.n_levels = nLevels;
src.n_scored = nScored;
src.message = message;
end


function [src, n] = localMetrics(T, n, R, ri)
g = @(name, type) localGet(T, name, type, n);
src.session_key = g('Key', 'string');

% What T carries stands in for a row with no result.
nTotal = localOrNaN(g('NumTrials', 'double'), n);
nStim = localOrNaN(g('NumStimulus', 'double'), n);
nCatch = localOrNaN(g('NumCatch', 'double'), n);
nHit = nan(n, 1); nMiss = nan(n, 1); nFA = nan(n, 1); nCR = nan(n, 1); nAbort = nan(n, 1);
hit = localOrNaN(g('HitRate', 'double'), n);
fa = localOrNaN(g('FARate', 'double'), n);
cr = nan(n, 1);
abortRate = localOrNaN(g('AbortRate', 'double'), n);
dprime = localOrNaN(g('DPrime', 'double'), n);
aprime = localOrNaN(g('APrime', 'double'), n);
crit = localOrNaN(g('Criterion', 'double'), n);
bpp = nan(n, 1);
for k = 1:n
    if ri(k) == 0, continue, end
    M = R(ri(k)).Metrics;
    if ~isstruct(M) || ~isscalar(M), continue, end
    if isfield(M, 'N') && isstruct(M.N)
        nTotal(k) = localNum(M.N, 'Total');
        nStim(k) = localNum(M.N, 'Stimulus');
        nCatch(k) = localNum(M.N, 'Catch');
        nHit(k) = localNum(M.N, 'Hit');
        nMiss(k) = localNum(M.N, 'Miss');
        nFA(k) = localNum(M.N, 'FalseAlarm');
        nCR(k) = localNum(M.N, 'CorrectReject');
        nAbort(k) = localNum(M.N, 'Abort');
    end
    if isfield(M, 'Rate') && isstruct(M.Rate)
        hit(k) = localNum(M.Rate, 'Hit');
        fa(k) = localNum(M.Rate, 'FalseAlarm');
        cr(k) = localNum(M.Rate, 'CorrectReject');
        abortRate(k) = localNum(M.Rate, 'Abort');
    end
    dprime(k) = localNum(M, 'DPrime');
    aprime(k) = localNum(M, 'APrime');
    crit(k) = localNum(M, 'Criterion');
    bpp(k) = localNum(M, 'BPrimePrime');
end
src.n_total = nTotal;
src.n_stimulus = nStim;
src.n_catch = nCatch;
src.n_hit = nHit;
src.n_miss = nMiss;
src.n_fa = nFA;
src.n_cr = nCR;
src.n_abort = nAbort;
src.hit_rate = hit;
src.fa_rate = fa;
src.cr_rate = cr;
src.abort_rate = abortRate;
src.d_prime = dprime;
src.a_prime = aprime;
src.criterion = crit;
src.b_prime_prime = bpp;
end


function v = localOrNaN(v, n)
if isempty(v), v = nan(n, 1); end
end


function [src, rows] = localReversals(R, ri)
% One row per reversal of every result that belongs to a row of T.
use = reshape(ri(ri > 0), 1, []);
K = cell(1, numel(use)); I = K; Tr = K; V = K;
for j = 1:numel(use)
    r = use(j);
    t = reshape(double(R(r).ReversalIdx), [], 1);
    v = reshape(double(R(r).ReversalValues), [], 1);
    m = min(numel(t), numel(v));
    if m == 0, continue, end
    K{j} = repmat(string(R(r).Key), m, 1);
    I{j} = (1:m)';
    Tr{j} = t(1:m);
    V{j} = v(1:m);
end
key = vertcat(strings(0, 1), K{:});
idx = vertcat(zeros(0, 1), I{:});
trial = vertcat(zeros(0, 1), Tr{:});
value = vertcat(zeros(0, 1), V{:});
rows = numel(key);
src.session_key = key;
src.reversal_index = idx;
src.trial_index = trial;
src.value = value;
end


function [src, rows] = localNotes(T, n)
text = localGet(T, 'NotesText', 'string', n);
key = localGet(T, 'Key', 'string', n);
if isempty(text) || isempty(key)
    text = strings(0, 1);
    key = strings(0, 1);
else
    text = reshape(string(text), [], 1);
    key = reshape(string(key), [], 1);
    has = ~ismissing(text) & strlength(strtrim(text)) > 0;
    text = text(has);
    key = key(has);
end
rows = numel(key);
src.session_key = key;
src.text = text;
end
