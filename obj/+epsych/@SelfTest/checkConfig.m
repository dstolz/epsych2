function results = checkConfig(self)
% results = checkConfig(self)
% Verify the session's subject configuration: subjects are complete, box IDs
% are usable, names are safe to build filenames from, and each subject's
% protocol file is still where the session says it is.
%
% Returns:
%	results	- Result struct array; see epsych.SelfTest.result.
%
% See also: epsych.SelfTest.run, epsych.Subject.isValid
arguments
    self
end

GROUP = "Config";
results = epsych.SelfTest.result();

if isempty(self.RunExpt) || ~isvalid(self.RunExpt)
    results = epsych.SelfTest.result("D0_NoSession", GROUP, "Configuration", "skip", ...
        'No RunExpt session is open.');
    return
end

CONFIG = self.RunExpt.CONFIG;
nSubjects = numel(CONFIG);
hasSubjects = nSubjects > 0 && isfield(CONFIG, 'SUBJECT') && ~isempty(CONFIG(1).SUBJECT);

if ~hasSubjects
    results = epsych.SelfTest.result("D0_NoConfig", GROUP, "Configuration", "skip", ...
        'The session has no subjects; add checked subjects from Subjects & Projects first.');
    return
end

% --- D1: subject completeness -----------------------------------------
t = tic;
problems = strings(1,0);
detail   = strings(1,0);

for i = 1:nSubjects
    S = CONFIG(i).SUBJECT;
    if ~isa(S, 'epsych.Subject')
        problems(end+1) = sprintf("CONFIG(%d).SUBJECT is a %s, not an epsych.Subject.", i, class(S));
        continue
    end

    if S.isValid()
        detail(end+1) = sprintf("%d. %s (box %d, %s %s)", i, string(S.Name), S.BoxID, ...
            string(S.Species), string(S.Sex));
    else
        try
            S.validate();
        catch ME
            problems(end+1) = sprintf("CONFIG(%d): %s", i, ME.message);
        end
    end
end

if isempty(problems)
    r = epsych.SelfTest.result("D1_Subjects", GROUP, "Subject records", "pass", ...
        sprintf('All %d subject(s) are complete.', nSubjects), ...
        Detail = detail);
else
    r = epsych.SelfTest.result("D1_Subjects", GROUP, "Subject records", "fail", ...
        sprintf('%d subject record(s) are incomplete.', numel(problems)), ...
        Detail = problems, ...
        Remedy = "Fix the subject via Add Subject, or remove and re-add it.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- D2: box IDs -------------------------------------------------------
% SortBoxes indexes CONFIG by box ID, so duplicate or out-of-range IDs
% silently reorder or error rather than reporting anything useful.
t = tic;
ids = nan(1, nSubjects);
for i = 1:nSubjects
    S = CONFIG(i).SUBJECT;
    if isa(S, 'epsych.Subject') && isnumeric(S.BoxID) && isscalar(S.BoxID)
        ids(i) = S.BoxID;
    end
end

problems = strings(1,0);
if any(isnan(ids))
    problems(end+1) = sprintf("%d subject(s) have a non-numeric box ID.", nnz(isnan(ids)));
end
valid = ids(~isnan(ids));
if any(valid < 1) || any(mod(valid,1) ~= 0)
    problems(end+1) = "Box IDs must be positive integers.";
end
dupes = unique(valid(arrayfun(@(x) sum(valid == x) > 1, valid)));
if ~isempty(dupes)
    problems(end+1) = "Duplicate box ID(s): " + strjoin(string(dupes), ", ");
end

if isempty(problems)
    warnSort = strings(1,0);
    if ~isempty(valid) && ~isequal(sort(valid), 1:numel(valid))
        warnSort(end+1) = "Box IDs are not 1..N; the Sort Boxes command indexes by ID and will error on this set.";
    end

    if isempty(warnSort)
        r = epsych.SelfTest.result("D2_BoxIDs", GROUP, "Box IDs", "pass", ...
            sprintf('Box IDs are unique and contiguous: %s.', strjoin(string(valid), ", ")));
    else
        r = epsych.SelfTest.result("D2_BoxIDs", GROUP, "Box IDs", "warn", ...
            sprintf('Box IDs are unique but not contiguous: %s.', strjoin(string(valid), ", ")), ...
            Detail = warnSort, ...
            Remedy = "Renumber the subjects 1..N if you intend to use Sort Boxes.");
    end
else
    r = epsych.SelfTest.result("D2_BoxIDs", GROUP, "Box IDs", "fail", ...
        'Box IDs are not usable.', ...
        Detail = problems, ...
        Remedy = "Give every subject a unique positive integer box ID.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- D3: names are filename-safe --------------------------------------
% Data files are named <Subject>_<timestamp>.mat, so an illegal character
% only fails at the moment the session tries to save.
t = tic;
illegal = '<>:"/\|?*';
problems = strings(1,0);
for i = 1:nSubjects
    S = CONFIG(i).SUBJECT;
    if ~isa(S, 'epsych.Subject'), continue, end
    nm = char(string(S.Name));
    bad = intersect(nm, illegal);
    if ~isempty(bad)
        problems(end+1) = sprintf("'%s' contains %s", nm, strjoin(cellstr(bad'), ' '));
    elseif ~isempty(nm) && (nm(end) == ' ' || nm(end) == '.')
        problems(end+1) = sprintf("'%s' ends with a space or period, which Windows strips", nm);
    end
end

if isempty(problems)
    r = epsych.SelfTest.result("D3_NameSafety", GROUP, "Subject names", "pass", ...
        'All subject names are safe to use in filenames.');
else
    r = epsych.SelfTest.result("D3_NameSafety", GROUP, "Subject names", "fail", ...
        sprintf('%d subject name(s) cannot be used in a filename.', numel(problems)), ...
        Detail = problems, ...
        Remedy = "Rename the subject using letters, digits, hyphens, and underscores only.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- D4: protocol files present ---------------------------------------
t = tic;
missing  = strings(1,0);
embedded = strings(1,0);
present  = strings(1,0);

for i = 1:nSubjects
    S = CONFIG(i).SUBJECT;
    nm = "subject " + i;
    if isa(S, 'epsych.Subject')
        nm = string(S.Name);
    end

    pfn = string(CONFIG(i).protocol_fn);
    if strlength(pfn) == 0
        embedded(end+1) = nm + ": protocol is embedded in the session only";
    elseif isfile(pfn)
        present(end+1) = nm + ": " + pfn;
    else
        missing(end+1) = nm + ": " + pfn;
    end
end

if ~isempty(missing)
    r = epsych.SelfTest.result("D4_ProtocolFiles", GROUP, "Protocol files", "fail", ...
        sprintf('%d protocol file(s) referenced by the session do not exist.', numel(missing)), ...
        Detail = missing, ...
        Remedy = "Right-click the subject and use Change Protocol File..., or restore the missing file.");
elseif ~isempty(embedded)
    r = epsych.SelfTest.result("D4_ProtocolFiles", GROUP, "Protocol files", "warn", ...
        sprintf('%d subject(s) use an embedded protocol with no file on disk.', numel(embedded)), ...
        Detail = [embedded present], ...
        Remedy = "View Trials, Edit Protocol, and Update Protocol all need a file; assign one to enable them.");
else
    r = epsych.SelfTest.result("D4_ProtocolFiles", GROUP, "Protocol files", "pass", ...
        sprintf('All %d protocol file(s) are present.', numel(present)), ...
        Detail = present);
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- D5: can CONFIG hold more than one subject? ------------------------
% AddSubject appends by assigning to CONFIG(numel+1), which a scalar-
% constrained property rejects. Nothing else surfaces this until an operator
% tries to add a second subject and the command fails.
t = tic;
r = localCheckConfigCardinality(GROUP);
results = [results epsych.SelfTest.withTime(r, toc(t))];

end

% -----------------------------------------------------------------------
function r = localCheckConfigCardinality(group)
% Report whether epsych.RunExpt.CONFIG is declared as a scalar struct, which
% caps a session at one subject regardless of what AddSubject attempts.
try
    mc = ?epsych.RunExpt;
    prop = mc.PropertyList(strcmp({mc.PropertyList.Name}, 'CONFIG'));
    if isempty(prop)
        r = epsych.SelfTest.result("D5_ConfigCardinality", group, "Multi-subject capacity", "skip", ...
            'The CONFIG property could not be inspected.');
        return
    end

    sz = prop(1).Validation.Size;
    isScalarConstrained = numel(sz) == 2 && ...
        all(arrayfun(@(d) isa(d, 'meta.FixedDimension') && d.Length == 1, sz));
catch ME
    r = epsych.SelfTest.result("D5_ConfigCardinality", group, "Multi-subject capacity", "skip", ...
        sprintf('The CONFIG property could not be inspected: %s', ME.message));
    return
end

if isScalarConstrained
    r = epsych.SelfTest.result("D5_ConfigCardinality", group, "Multi-subject capacity", "fail", ...
        'CONFIG is declared (1,1), so this session can only ever hold one subject.', ...
        Detail = [ ...
            "epsych.RunExpt.AddSubject appends via CONFIG(numel+1), which a scalar-", ...
            "constrained property rejects with 'Value must be a scalar'.", ...
            "Single-subject sessions are unaffected."], ...
        Remedy = "Declare CONFIG as (1,:) struct in epsych.RunExpt to allow multi-subject sessions.");
else
    r = epsych.SelfTest.result("D5_ConfigCardinality", group, "Multi-subject capacity", "pass", ...
        'CONFIG can hold multiple subjects.');
end
end
