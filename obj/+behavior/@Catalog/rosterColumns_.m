function T = rosterColumns_(T, R)
% T = rosterColumns_(T, R)
%
% The roster's view of each subject, as columns added to the Subjects table T.
% R is an epsych.SubjectRoster or [] (no roster), in which case every column
% is present and says "not known", so a caller never has to test for them.
%
% A subject is matched by its folder name: first against the roster's current
% names (findSubject), then against every NameHistory, since a data folder is
% named after whatever the animal was called when it ran ("former").

n = height(T);
known = false(n, 1);
sex = strings(n, 1);
species = strings(n, 1);
projects = strings(n, 1);
lastProtocol = strings(n, 1);
lastVersion = strings(n, 1);
retired = false(n, 1);
match = strings(n, 1);

if ~isempty(R)
    for i = 1:n
        name = char(T.Subject(i));
        [rec, how] = localFind(R, name);
        if isempty(rec), continue, end

        known(i) = true;
        match(i) = how;
        sex(i) = string(rec.Sex);
        species(i) = string(rec.Species);

        P = R.projectsForSubject(rec.SubjectID);
        if ~isempty(P)
            projects(i) = strjoin(string({P.Name}), ", ");
        end

        m = localMembership(R, rec.SubjectID, T.Project(i));
        retired(i) = logical(rec.Retired);
        if ~isempty(m)
            lastProtocol(i) = string(m.LastProtocol);
            lastVersion(i) = string(m.LastProtocolVersion);
            retired(i) = retired(i) || ~m.Active;
        end
    end
end

T.RosterKnown = known;
T.RosterSex = sex;
T.RosterSpecies = species;
T.RosterProjects = projects;
T.RosterLastProtocol = lastProtocol;
T.RosterLastProtocolVersion = lastVersion;
T.RosterRetired = retired;
T.RosterNameMatch = match;

end




function [rec, how] = localFind(R, name)
% The roster record for a folder name, and whether it matched the current
% name or a former one.
how = "";
rec = R.findSubject(name);
if ~isempty(rec)
    how = "current";
    return
end
for k = 1:numel(R.Subjects)
    if any(strcmpi(string(R.Subjects(k).NameHistory), name))
        rec = R.Subjects(k);
        how = "former";
        return
    end
end
end




function m = localMembership(R, subjectId, projectName)
% The membership whose project carries the folder's project name, else the one
% most recently modified: the protocol a subject last ran is per project.
m = [];
M = R.Memberships;
if isempty(M), return, end
M = M(strcmp({M.SubjectID}, subjectId));
if isempty(M), return, end

for k = 1:numel(M)
    p = R.findProject(M(k).ProjectID);
    if ~isempty(p) && strcmpi(p.Name, projectName)
        m = M(k);
        return
    end
end

modified = NaT(numel(M), 1);
for k = 1:numel(M)
    if isdatetime(M(k).Modified) && ~isempty(M(k).Modified)
        modified(k) = M(k).Modified;
    end
end
[~, k] = max(modified);
if isempty(k) || isnat(modified(k)), k = numel(M); end
m = M(k);
end
