function report = importSubjects(self, records, options)
% report = importSubjects(self, records)
% report = importSubjects(self, records, ProjectID=pid)
% Bring animals from the lab's subject registry into the roster, linked.
%
% The registry owns an animal's identity and the roster owns how it is run, so
% an import may write identity (Sex, Species) onto a roster subject and never
% touches anything else on it: not its name once chosen, its weight, its
% notes, or any membership's session settings, protocol memory, or parameter
% defaults.
%
% Each record is matched, in order:
%   1. by RegistryID, to the subject already linked to it -- its Sex and
%      Species are brought up to date ("updated", or "unchanged");
%   2. by Name, to an UNLINKED subject of that name -- it is linked
%      ("linked"); a same-named subject linked to another animal is left
%      alone ("skipped"), since two animals cannot share a name here;
%   3. otherwise it is added, named after the registry id unless the record
%      gives a Name ("added").
% With ProjectID, every imported subject not yet in that project is enrolled
% (assign's template stamping applies); a RETIRED member stays retired -- an
% import is not the operator choosing to run that animal again.
%
% All of it is one roster write, so two rigs importing at once cannot
% interleave half an import each.
%
% Parameters:
%   records - struct array; RegistryID required, Name/Sex/Species optional.
%             The epsych.SubjectRegistry findSubjects table converts with
%             table2struct.
%
% Options:
%   ProjectID - roster project (ID or Name) to enrol the subjects in.
%
% Returns:
%   report - struct array, one per record: RegistryID, SubjectID, Name,
%            Action ("added"|"linked"|"updated"|"unchanged"|"skipped"),
%            Enrolled (logical), Reason (why skipped, else "").
%
% Throws:
%   epsych:SubjectRoster:NoSuchProject
%
% See also: epsych.SubjectRegistry, epsych.SubjectRoster.findByRegistryID
arguments
    self
    records struct
    options.ProjectID (1,:) char = ''
end

pid = '';
if ~isempty(options.ProjectID)
    p = self.findProject(options.ProjectID);
    if isempty(p)
        error('epsych:SubjectRoster:NoSuchProject', 'No project matches "%s".', options.ProjectID);
    end
    pid = p.ProjectID;
end

n = numel(records);
report = repmat(struct('RegistryID', "", 'SubjectID', "", 'Name', "", ...
    'Action', "skipped", 'Enrolled', false, 'Reason', ""), 1, n);

% Normalize and check names before taking the lock: a bad name is a property
% of the record, not of what another rig has written since.
want = repmat(struct('RegistryID', '', 'Name', '', 'Sex', '', 'Species', '', ...
    'HasSex', false, 'HasSpecies', false), 1, n);
for i = 1:n
    r = records(i);
    want(i).RegistryID = strtrim(char(string(localField(r, 'RegistryID', ''))));
    nm = strtrim(char(string(localField(r, 'Name', ''))));
    if isempty(nm), nm = want(i).RegistryID; end
    want(i).Name = nm;
    want(i).HasSex = isfield(r, 'Sex') && ~isempty(r.Sex) && ~all(ismissing(string(r.Sex)));
    want(i).HasSpecies = isfield(r, 'Species') && ~isempty(r.Species) && ~all(ismissing(string(r.Species)));
    if want(i).HasSex, want(i).Sex = char(string(r.Sex)); end
    if want(i).HasSpecies, want(i).Species = char(string(r.Species)); end
    report(i).RegistryID = string(want(i).RegistryID);
    report(i).Name = string(nm);
end

if n == 0, return, end

if ~self.mutate_(@applyImport)
    % Unlike the single-record CRUD methods, say so: a report of "added"
    % for animals that never reached the file would be believed.
    [report.Action] = deal("skipped");
    [report.Enrolled] = deal(false);
    [report.Reason] = deal("the roster file could not be written");
    vprintf(0, 1, 'Importing %d registry subject(s) failed: the roster file could not be written.', n);
    return
end

[u, ~, ic] = unique([report.Action]);
c = accumarray(ic(:), 1);
vprintf(1, 'Imported %d registry subject(s): %s.', n, ...
    strjoin(compose("%d %s", c, u(:)), ', '));

    function applyImport(r)
        now_ = datetime('now');
        for j = 1:n
            w = want(j);
            report(j).Action = "skipped";
            report(j).Enrolled = false;
            report(j).Reason = "";
            if isempty(w.RegistryID)
                report(j).Reason = "no registry id";
                continue
            end

            [cur, k] = r.findByRegistryID(w.RegistryID);
            if ~isempty(k)
                action = "unchanged";
            else
                [cur, k] = r.findSubject(w.Name);
                if ~isempty(k)
                    if ~isempty(cur.RegistryID)
                        report(j).Reason = sprintf( ...
                            'the name "%s" belongs to a subject linked to %s', ...
                            cur.Name, cur.RegistryID);
                        continue
                    end
                    cur.RegistryID = w.RegistryID;
                    action = "linked";
                else
                    [ok, why] = epsych.SubjectRoster.isNameSafe(w.Name);
                    if ~ok
                        report(j).Reason = string(why);
                        continue
                    end
                    cur = epsych.SubjectRoster.blankSubject_();
                    cur.SubjectID = epsych.SubjectRoster.newId('S');
                    cur.Name = w.Name;
                    cur.RegistryID = w.RegistryID;
                    cur.Created = now_;
                    action = "added";
                end
            end

            changed = action ~= "unchanged";
            if w.HasSex && ~strcmp(cur.Sex, w.Sex)
                cur.Sex = w.Sex;
                changed = true;
            end
            if w.HasSpecies && ~strcmp(cur.Species, w.Species)
                cur.Species = w.Species;
                changed = true;
            end
            if changed && action == "unchanged"
                action = "updated";
            end
            if changed
                cur.Modified = now_;
                if action == "added"
                    r.Subjects = [r.Subjects, cur];
                else
                    r.Subjects(k) = cur;
                end
            end
            report(j).Action = action;
            report(j).SubjectID = string(cur.SubjectID);
            report(j).Name = string(cur.Name);

            if ~isempty(pid) && isempty(r.findMembership(cur.SubjectID, pid))
                report(j).Enrolled = enrol(r, cur.SubjectID, now_);
            end
        end
    end

    function tf = enrol(r, sid, when)
        % assign's stamping, inline: assign would take the lock again and
        % write once per subject.
        tpl = r.findProject(pid);
        tf = ~isempty(tpl);
        if ~tf, return, end
        m = epsych.SubjectRoster.blankMembership_();
        m.SubjectID = sid;
        m.ProjectID = pid;
        m.Active = true;
        for f = epsych.SubjectRoster.SESSION_FIELDS
            m.(f{1}) = tpl.(f{1});
        end
        m.Added = when;
        m.Modified = when;
        r.Memberships = [r.Memberships, m];
    end

end

% -----------------------------------------------------------------------
function v = localField(s, name, default)
if isfield(s, name) && ~isempty(s.(name)) && ~all(ismissing(string(s.(name))))
    v = s.(name);
else
    v = default;
end
end
