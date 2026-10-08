function [code, info] = generate_(study, keys, kind, options)
% [code, info] = behavior.ScriptWriter.generate_(study, keys, kind, Name = Value)
% The one generator behind session() and compare(): the script, section by
% section, for the given sessions of a study.
%
% Every session is analysed in the script by behavior.Session.analyze with
% the study's settings and the session's own window -- the call
% behavior.Study.result makes -- so the script and the window cannot compute
% a result two ways. What the study holds for each session is recorded in the
% script as `expected` and compared with what the script gets.
%
% Parameters:
%   study - behavior.Study
%   keys  - session keys (one for "session")
%   kind  - "session" | "compare"
%   options - Title, Figures, Export, OutFolder, EPsychRoot, and for
%             "compare" Value, GroupBy, ColorBy, Kind, ColorMap, ShowMean,
%             Spread (see compare)
%
% Returns:
%   code - cellstr, one line of source each
%   info - struct Kind, Keys, SettingsHash, Expected, Title, NumLines
%
% See also: behavior.ScriptWriter.session, behavior.ScriptWriter.compare

arguments
    study (1,1) behavior.Study
    keys (1,:) string {mustBeNonempty}
    kind (1,1) string {mustBeMember(kind, ["session" "compare"])}
    options.Title (1,1) string = ""
    options.Figures (1,1) logical = true
    options.Export (1,1) logical = true
    options.OutFolder (1,1) string = ""
    options.EPsychRoot (1,1) string = ""
    options.Value (1,1) string = ""
    options.GroupBy (1,1) string = ""
    options.ColorBy (1,1) string = ""
    options.XAxis (1,1) string = ""
    options.Kind (1,1) string = ""
    options.ColorMap (1,1) string = ""
    options.ShowMean (1,1) logical
    options.Spread (1,1) string = ""
end

settings = study.Settings;
n = numel(keys);

% Each session is read once, up front: its catalog row (the identity the
% browser showed), its window override, and the result the study holds --
% the numbers the script will be checked against.
rows = cell(1, n);
R0 = cell(1, n);
win = strings(1, n);
for k = 1:n
    rows{k} = localIdentity(study.Catalog.session(keys(k)));
    keys(k) = rows{k}.Key;
    win(k) = study.windowFor(keys(k));
    R0{k} = study.result(keys(k));
end
expected = cellfun(@localRecorded, R0);

g = struct('Settings', settings, 'Hash', settings.hash(), 'Keys', keys, ...
    'Rows', {rows}, 'Windows', win, 'Expected', expected, 'Kind', kind, ...
    'Figures', options.Figures, 'Export', options.Export, ...
    'OutFolder', options.OutFolder, 'EPsychRoot', options.EPsychRoot, ...
    'Root', study.Root, 'Facets', []);
if g.EPsychRoot == ""
    g.EPsychRoot = string(epsych_path());
end
if kind == "compare"
    g.Facets = localFacets(study, R0, options);
end

if options.Title ~= ""
    g.Title = options.Title;
elseif kind == "session"
    r = rows{1};
    g.Title = "Replicate: " + r.Label;
else
    g.Title = sprintf("Replicate: comparison of %d sessions", n);
end
g.Title = strtrim(regexprep(g.Title, '[\r\n]+', ' '));

perSession = cell(1, n);
for k = 1:n
    perSession{k} = localSession(g, k);
end
code = [localHeader(g), localSetup(g), localSettings(g), perSession{:}, localTables(g)];
if g.Figures
    code = [code, localFigures(g)];
end
if g.Export
    code = [code, localExport()];
end
if kind == "compare"
    code = [code, localSummary()];
end
code = [code, {'%% Local functions'}, behavior.ScriptWriter.checkFunction()];

info = struct('Kind', kind, 'Keys', keys, 'SettingsHash', g.Hash, ...
    'Expected', expected, 'Title', g.Title, 'NumLines', numel(code));

end



% ================================================================== sections
function L = localHeader(g)
n = numel(g.Keys);
if n == 1
    what = "Reproduces the analysis of 1 session under";
else
    what = sprintf("Reproduces the analysis of %d sessions under", n);
end
L = [{char("%% " + g.Title)}, ...
    {char("% " + what)}, ...
    {char("%   " + g.Root)}, ...
    localComment("with settings " + g.Hash + ": " + g.Settings.describe()), ...
    localComment("Written by " + localWriter() + " on MATLAB " + string(version) ...
        + " on " + string(datetime("now"), "yyyy-MM-dd HH:mm") + "."), ...
    {'%'}];
if g.Export
    L = [L, {'% ROOT (the data) and OUTFOLDER (the export) are assigned below only when undefined:', ...
        '% set either before run(<this file>) to read from or write to somewhere else.'}];
else
    L = [L, {'% ROOT (the data) is assigned below only when undefined: set it before', ...
        '% run(<this file>) to read the sessions from somewhere else.'}];
end
L = [L, {''}];
end


function L = localSetup(g)
L = [{'%% Setup'}, ...
    localStatement('EPSYCHROOT = ', lit(g.EPsychRoot), ';'), ...
    localStatement('if ~exist(''ROOT'', ''var''), ROOT = ', lit(g.Root), '; end')];
if g.Export
    if g.OutFolder == ""
        L = [L, {['if ~exist(''OUTFOLDER'', ''var''), OUTFOLDER = fullfile(tempdir, ' ...
            '"epsych_replication_" + string(datetime("now"), "yyMMdd''T''HHmmss")); end']}];
    else
        L = [L, localStatement('if ~exist(''OUTFOLDER'', ''var''), OUTFOLDER = ', lit(g.OutFolder), '; end')];
    end
end
L = [L, {'addpath(EPSYCHROOT);', 'epsych_startup(EPSYCHROOT, false);'}];
if g.Settings.Fit.Enabled && g.Settings.Fit.Engine == "psignifit"
    % The fits came from psignifit, which EPsych does not ship: name the
    % folder and the commit used, and find it the way the window did when
    % that folder is not here.
    P = behavior.fit.Psignifit.locate();
    used = "psignifit (" + behavior.fit.Psignifit.URL + ")";
    if P.Version ~= "", used = used + ", commit " + P.Version; end
    L = [L, localComment("The fits were made with " + used + "."), ...
        localStatement('PSIGNIFITROOT = ', lit(P.Folder), ';'), ...
        {'if ~behavior.fit.Psignifit.available() && isfolder(PSIGNIFITROOT)', ...
         '    behavior.fit.Psignifit.setFolder(PSIGNIFITROOT, Remember = false);', ...
         'end', ...
         'assert(behavior.fit.Psignifit.available(), ''behavior:ScriptWriter:psignifit'', ''%s'', ...', ...
         '    behavior.fit.Psignifit.whyUnavailable());'}];
end
L = [L, {sprintf('replicated = false(1, %d);', numel(g.Keys)), ''}];
end


function L = localSettings(g)
% Every setting, defaults included, so a later change to a default cannot
% change what the script computes.
st = g.Settings.toStruct();
names = setdiff(string(fieldnames(st)), "SettingsVersion", 'stable');
L = {'%% Settings', ...
    '% Every setting is written out, defaults included, so that a later change to a', ...
    '% default cannot change what this script computes.', ...
    'cfg = behavior.Settings( ...'};
parts = cell(1, numel(names));
for i = 1:numel(names)
    prefix = '    ' + names(i) + ' = ';
    if i < numel(names), suffix = ', ...'; else, suffix = ');'; end
    parts{i} = localStatement(char(prefix), lit(st.(names(i)), 8, strlength(prefix)), suffix);
end
L = [L, parts{:}, {sprintf('assert(cfg.hash() == "%s", ''behavior:ScriptWriter:settingsHash'', ...', g.Hash), ...
    '    ''These settings no longer hash as the results did: this EPsych reads a setting differently.'');', ''}];
end


function L = localSession(g, k)
r = g.Rows{k};
n = numel(g.Keys);
if isempty(r.Tags), tagText = "no tags"; else, tagText = "tags " + strjoin(r.Tags, " "); end
L = [{sprintf('%%%% Session %d of %d: %s', k, n, r.Key)}, ...
    localComment(sprintf('%s (%s), %s, started %s, %s trials.', r.Subject, r.Project, ...
        tagText, r.StartText, r.TrialsText)), ...
    localStatement('key = ', lit(r.Key), ';'), ...
    {'sess = behavior.Session.load(fullfile(ROOT, key), Root = ROOT);', ...
     ['R = sess.analyze(cfg' localWindowArg(g.Windows(k)) ');']}];
if k == 1
    L = [L, {'results = R;'}];
else
    L = [L, {sprintf('results(%d) = R;', k)}];
end
L = [L, localStatement('expected = ', lit(g.Expected(k), 4, 11), ';'), ...
    localGot(), ...
    localStatement(sprintf('replicated(%d) = compareWithRecorded(got, expected, ', k), lit(r.Label), ');'), ...
    {''}];
end


function L = localTables(g)
L = {'%% Tables', 'T = behavior.Aggregate.thresholds(results);'};
if g.Kind == "compare"
    F = g.Facets;
    if ~isempty(F.Columns)
        parts = cell(1, numel(F.Columns));
        for c = 1:numel(F.Columns)
            parts{c} = localStatement(char("T." + F.Columns(c) + " = "), lit(F.ColumnValues{c}, 4, 8), ';');
        end
        L = [L, {'% Columns the facets read that no session file carries, as the study had them.'}, parts{:}];
    end
end
L = [L, {'disp(T(:, ["Subject" "TagText" "Parameter" "Window" "Threshold" "FitThreshold" "DPrime" "NumIncluded"]))'}];
if g.Kind == "compare"
    F = g.Facets;
    L = [L, localStatement('groupBy = behavior.Facet.fromText(', lit(F.GroupBy), ');'), ...
        localStatement('colorBy = behavior.Facet.fromText(', lit(F.ColorBy), ');'), ...
        localStatement('xAxis = behavior.Facet.fromText(', lit(F.XAxis), ');'), ...
        localStatement('D = behavior.Stats.describe(T, ', lit(F.Value), ...
            [', GroupBy = groupBy, BootstrapCI = cfg.Compare.BootstrapCI, ...' newline ...
             '    ConfidenceLevel = cfg.Compare.ConfidenceLevel, NumBoot = cfg.Compare.NumBoot);']), ...
        {'disp(D)', 'disp(behavior.Stats.sentence(D))'}];
end
L = [L, {''}];
end


function L = localFigures(g)
L = [{'%% Figures'}, ...
    localStatement('fig = uifigure(Name = ', lit(g.Title), ', Tag = "EPsychBehaviorScript");'), ...
    {'g = uigridlayout(fig, [1 2]);'}];
if g.Kind == "session"
    if g.Settings.Fit.Engine == "psignifit"
        fitPlot = 'behavior.fit.PsignifitPlot.psych(uiaxes(g), R.Fit, Unit = R.Unit, Parameter = R.Parameter);';
    else
        fitPlot = 'behavior.Plot.psychometric(uiaxes(g), R.Fit, Unit = R.Unit);';
    end
    L = [L, {'ax = uiaxes(g);', ...
        ['S = sess.staircase(cfg' localWindowArg(g.Windows(1)) ');'], ...
        'S.Plot(ax);', ...
        fitPlot}];
else
    F = g.Facets;
    % The mean and spread as the Compare tab draws them; an "auto" spread
    % reads the CI setting here as it does there.
    summary = [', ShowMean = ' lit(F.ShowMean) ', Spread = ' lit(F.Spread) ', ...' newline ...
        '    ShowCI = cfg.Compare.BootstrapCI, ConfidenceLevel = cfg.Compare.ConfidenceLevel, ' ...
        'NumBoot = cfg.Compare.NumBoot);'];
    if F.Kind == "lines"
        L = [L, localStatement('behavior.Plot.subjectLines(uiaxes(g), T, ', lit(F.Value), ...
            [', XAxis = xAxis, ColorBy = colorBy' summary])];
    else
        plotKind = F.Kind;
        if plotKind == "overlay", plotKind = "box"; end
        L = [L, localStatement('behavior.Plot.groupComparison(uiaxes(g), T, ', lit(F.Value), ...
            [', GroupBy = groupBy, ColorBy = colorBy, Kind = ' lit(plotKind) summary])];
    end
    L = [L, localStatement('behavior.Plot.staircaseOverlay(uiaxes(g), results, T, ColorBy = colorBy, ColorMap = ', ...
        lit(F.ColorMap), ');')];
end
L = [L, {''}];
end


function L = localExport()
L = {'%% Export', ...
    'Tbls = behavior.Export.tables(T, results);', ...
    'files = behavior.Export.write(Tbls, OUTFOLDER);', ...
    'disp(files)', ''};
end


function L = localSummary()
L = {'%% Summary', ...
    'fprintf(''%d of %d sessions replicated.\n'', nnz(replicated), numel(replicated));', ''};
end



% ================================================================== helpers
function spec = localRecordedSpec()
% The values each session is checked on: name in expected/got, and the path
% to it in a behavior.Session.analyze result. One table, so `expected` (read
% here) and `got` (written into the script) cannot name different things.
spec = {
    'Threshold',     {'Threshold'}
    'ThresholdStd',  {'ThresholdStd'}
    'ReversalCount', {'ReversalCount'}
    'NumIncluded',   {'NumIncluded'}
    'NumStimulus',   {'NumStimulus'}
    'FitThreshold',  {'Fit', 'Threshold'}
    'DPrime',        {'Metrics', 'DPrime'}
    'HitRate',       {'Metrics', 'Rate', 'Hit'}
    'FARate',        {'Metrics', 'Rate', 'FalseAlarm'}
    'AbortRate',     {'Metrics', 'Rate', 'Abort'}
    };
end


function E = localRecorded(R)
% The recorded values of one result; NaN where the result has none.
spec = localRecordedSpec();
E = struct();
for i = 1:size(spec, 1)
    v = R;
    for p = spec{i, 2}
        if isstruct(v) && isscalar(v) && isfield(v, p{1})
            v = v.(p{1});
        else
            v = NaN;
            break
        end
    end
    E.(spec{i, 1}) = v;
end
end


function L = localGot()
% got = struct(...) over the same paths, read from the script's R.
spec = localRecordedSpec();
m = size(spec, 1);
L = [{'got = struct( ...'}, cell(1, m)];
for i = 1:m
    if i < m, suffix = ', ...'; else, suffix = ');'; end
    L{i + 1} = sprintf('    ''%s'', {R.%s}%s', spec{i, 1}, strjoin(spec{i, 2}, '.'), suffix);
end
end


function r = localIdentity(row)
% What the script says about a session, from its catalog row.
r.Key = string(row.Key);
r.Subject = string(row.Subject);
r.Project = string(row.Project);
t = row.Tags;
if iscell(t), t = t{1}; end
r.Tags = reshape(string(t), 1, []);
r.Tags = r.Tags(r.Tags ~= "");
start = row.Start;
if isdatetime(start) && ~isempty(start) && ~isnat(start(1))
    r.StartText = string(start(1), "yyyy-MM-dd HH:mm:ss");
    r.DateText = string(start(1), "yyyy-MM-dd");
else
    r.StartText = "(unknown start)";
    r.DateText = strings(1, 0);
end
trials = double(row.Trials);
if isscalar(trials) && isfinite(trials)
    r.TrialsText = string(trials);
else
    r.TrialsText = "an unknown number of";
end
r.Label = strjoin([r.Subject r.DateText r.Tags], " ");
end


function F = localFacets(study, R0, options)
% The comparison's value, facets and plot kind (the study's when not
% given), and the columns those facets read that analyze cannot supply.
P = study.Project.Facets;
F.Value = localPick(options.Value, P.Value);
values = behavior.Aggregate.valueColumns().Name;
if ~ismember(F.Value, values)
    error('behavior:ScriptWriter:UnknownValue', '"%s" is not a value column (%s).', ...
        F.Value, strjoin(values, ", "));
end
F.GroupBy = behavior.Facet.fromText(localPick(options.GroupBy, P.GroupBy)).toText();
F.ColorBy = behavior.Facet.fromText(localPick(options.ColorBy, P.ColorBy)).toText();
F.XAxis = behavior.Facet.fromText(localPick(options.XAxis, P.XAxis)).toText();
F.Kind = lower(localPick(options.Kind, P.Kind));
F.ColorMap = lower(localPick(options.ColorMap, P.ColorMap));
if ~ismember(F.ColorMap, behavior.Plot.COLOR_MAPS)
    error('behavior:ScriptWriter:UnknownColorMap', '"%s" is not a colour map (%s).', ...
        F.ColorMap, strjoin(behavior.Plot.COLOR_MAPS, ", "));
end
kinds = ["box" "bar" "strip" "lines" "overlay"];
if ~ismember(F.Kind, kinds)
    error('behavior:ScriptWriter:UnknownKind', '"%s" is not a plot kind (%s).', ...
        F.Kind, strjoin(kinds, ", "));
end
if isfield(options, 'ShowMean')
    F.ShowMean = options.ShowMean;
else
    F.ShowMean = logical(P.ShowMean);
end
F.Spread = lower(localPick(options.Spread, P.Spread));
if ~ismember(F.Spread, behavior.Plot.SPREADS)
    error('behavior:ScriptWriter:UnknownSpread', '"%s" is not a spread (%s).', ...
        F.Spread, strjoin(behavior.Plot.SPREADS, ", "));
end

% A facet reading a catalog, roster or project column would find it empty in
% a table built from results alone; those columns travel as literals.
T = behavior.Aggregate.thresholds([R0{:}], study.sessions(IncludeHidden = true));
cols = arrayfun(@(txt) localFacetColumn(behavior.Facet.fromText(txt)), ...
    unique([F.GroupBy F.ColorBy F.XAxis], 'stable'));
cols = unique(cols(cols ~= "" & ismember(cols, string(T.Properties.VariableNames))), 'stable');
F.Columns = reshape(cols, 1, []);
F.ColumnValues = arrayfun(@(c) T.(c), cols, 'UniformOutput', false);
end


function c = localFacetColumn(f)
% The thresholds-table column a facet reads that results alone leave empty.
switch f.Kind
    case "manual",          c = "Group_" + string(matlab.lang.makeValidName(char(f.Name)));
    case "projectpath",     c = "ProjectPath";
    case "sex",             c = "SubjectSex";
    case "species",         c = "SubjectSpecies";
    case "paradigm",        c = "Paradigm";
    case "protocolversion", c = "ProtocolVersion";
    case "box",             c = "BoxID";
    otherwise,              c = "";
end
end


function v = localPick(given, fallback)
if given == "", v = string(fallback); else, v = given; end
end


function a = localWindowArg(w)
if w == "", a = ''; else, a = [', Window = ' lit(w)]; end
end


function txt = localWriter()
% "EPsych v2.4.2 (commit 7e878fb...)", as much of it as is known.
txt = "EPsych";
try
    m = EPsychInfo().meta;
    if (ischar(m.LatestTag) || isstring(m.LatestTag)) && strlength(string(m.LatestTag)) > 0
        txt = txt + " " + string(m.LatestTag);
    end
    if (ischar(m.Checksum) || isstring(m.Checksum)) && strlength(string(m.Checksum)) > 0
        txt = txt + " (commit " + string(m.Checksum) + ")";
    end
catch ME
    vprintf(2, 'behavior.ScriptWriter: no version information (%s)', ME.message)
end
end


function txt = lit(v, indent, used)
% literal(), its continuation lines indented, wrapped to leave room for the
% text already on its first line.
if nargin < 2, indent = 4; end
if nargin < 3, used = 0; end
width = max(48, behavior.ScriptWriter.LineWidth - double(used));
txt = behavior.ScriptWriter.literal(v, Indent = indent, LineWidth = width);
end


function L = localStatement(prefix, body, suffix)
% prefix + body + suffix as lines, where body (and suffix) may span several.
txt = [char(prefix) char(body) char(suffix)];
L = reshape(cellstr(splitlines(string(txt))), 1, []);
end


function L = localComment(txt)
% Text as "% " comment lines wrapped at LineWidth.
width = behavior.ScriptWriter.LineWidth - 2;
words = split(strtrim(string(txt)));
L = cell(1, numel(words));
nl = 0;
line = "";
for w = reshape(words, 1, [])
    if line == ""
        line = w;
    elseif strlength(line) + 1 + strlength(w) <= width
        line = line + " " + w;
    else
        nl = nl + 1;
        L{nl} = char("% " + line);
        line = w;
    end
end
nl = nl + 1;
L{nl} = char("% " + line);
L = L(1:nl);
end
