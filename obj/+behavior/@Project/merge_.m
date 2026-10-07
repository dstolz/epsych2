function merge_(P, D)
% merge_(P, D)
% Fold the project D (the file as another writer left it) into P.
%
% Records are matched by identity -- session rows by key (keyEquals' rule),
% subject rows by name, presets and groupings by name -- and when both sides
% have one, the later Modified wins (a tie keeps P's). A record only one
% side has is kept, EXCEPT where the merge base (Base_, the identities and
% times P last read or wrote) shows it is a removal rather than an addition:
%   - only P has it, and the base has it with the same Modified: P never
%     touched it and the other writer removed it, so it goes;
%   - only D has it, and the base has it with the same Modified: P removed
%     it and the other writer never touched it, so it stays removed.
% That is what keeps an un-hidden session or a deleted preset from coming
% back out of the other writer's copy. Settings, Facets and Selection are
% wholes, the later Modified winning. Revision becomes the larger of the two.
%
% Parameters:
%   D - behavior.Project read from the same file

B = P.Base_;
nk = @behavior.Project.normKey_;

if localLater(D.SettingsModified, P.SettingsModified)
    P.Settings = D.Settings;
    P.SettingsModified = D.SettingsModified;
end
if localLater(D.Facets.Modified, P.Facets.Modified)
    P.Facets = D.Facets;
end
if localLater(D.Selection.Modified, P.Selection.Modified)
    P.Selection = D.Selection;
end

[mine, disk] = localPick(nk(P.Sessions.Key), P.Sessions.Modified, ...
    nk(D.Sessions.Key), D.Sessions.Modified, B.Sessions);
P.Sessions = [P.Sessions(mine, :); D.Sessions(disk, :)];

[mine, disk] = localPick(nk(P.Subjects.Subject), P.Subjects.Modified, ...
    nk(D.Subjects.Subject), D.Subjects.Modified, B.Subjects);
P.Subjects = [P.Subjects(mine, :); D.Subjects(disk, :)];

[mk, mm] = localIds(P.Presets);
[dk, dm] = localIds(D.Presets);
[mine, disk] = localPick(mk, mm, dk, dm, B.Presets);
P.Presets = [reshape(P.Presets(mine), 1, []), reshape(D.Presets(disk), 1, [])];

[mk, mm] = localIds(P.Groupings);
[dk, dm] = localIds(D.Groupings);
[mine, disk] = localPick(mk, mm, dk, dm, B.Groupings);
P.Groupings = [reshape(P.Groupings(mine), 1, []), reshape(D.Groupings(disk), 1, [])];

P.Revision = max(P.Revision, D.Revision);

end


function tf = localLater(a, b)
% Whether time a is later than b; never (NaT) is earliest.
if isnat(a)
    tf = false;
elseif isnat(b)
    tf = true;
else
    tf = a > b;
end
end


function tf = localSame(a, b)
tf = (isnat(a) && isnat(b)) || a == b;
end


function [k, m] = localIds(S)
if isempty(S)
    k = strings(0, 1);
    m = NaT(0, 1);
else
    k = reshape([S.Name], [], 1);
    m = reshape([S.Modified], [], 1);
end
end


function [keepMine, keepDisk] = localPick(mk, mm, dk, dm, base)
% Which of P's records (mk/mm) and which of D's (dk/dm) the merge keeps.
keepMine = true(numel(mk), 1);
keepDisk = true(numel(dk), 1);

[inDisk, loc] = ismember(mk, dk);
for i = reshape(find(inDisk), 1, [])
    j = loc(i);
    if localLater(dm(j), mm(i))
        keepMine(i) = false;
    else
        keepDisk(j) = false;
    end
end

[inBase, bloc] = ismember(mk, base.Keys);
for i = reshape(find(~inDisk & inBase), 1, [])
    if localSame(mm(i), base.Modified(bloc(i)))
        keepMine(i) = false;
    end
end

onlyDisk = ~ismember(dk, mk);
[inBase, bloc] = ismember(dk, base.Keys);
for j = reshape(find(onlyDisk & inBase), 1, [])
    if localSame(dm(j), base.Modified(bloc(j)))
        keepDisk(j) = false;
    end
end
end
