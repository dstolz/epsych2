function T = exportTable(self)
% T = exportTable(self)
% Flatten the roster to one row per subject-project pair, for writetable.
%
% The .esub file is the authoritative store; this is a readable snapshot for
% people who want the roster in a spreadsheet. It is deliberately one-way —
% nothing imports a CSV back, because a round trip through Excel silently
% mangles NaN weights and datetimes.
%
% Subjects belonging to no project still get a row, with empty project columns,
% so an export is never a way to lose an animal.
%
% Returns:
%   T - table ready for writetable.
%
% See also: writetable, epsych.SubjectRoster.toSubject
arguments
    self
end

vars = {'Subject','Species','Sex','Weight','Project','Active','LastProtocol', ...
    'LastProtocolVersion','LastBoxID','Notes','SubjectID','Created'};

if isempty(self.Subjects)
    T = cell2table(cell(0, numel(vars)), VariableNames = vars);
    return
end

rows = cell(0, numel(vars));

for i = 1:numel(self.Subjects)
    s = self.Subjects(i);

    mine = epsych.SubjectRoster.emptyMembership();
    if ~isempty(self.Memberships)
        mine = self.Memberships(strcmp({self.Memberships.SubjectID}, s.SubjectID));
    end

    if isempty(mine)
        rows(end+1, :) = {s.Name, s.Species, s.Sex, s.Weight, '', ...
            ~s.Retired, '', '', NaN, s.Notes, s.SubjectID, s.Created};
        continue
    end

    for k = 1:numel(mine)
        p = self.findProject(mine(k).ProjectID);
        pName = '';
        if ~isempty(p), pName = p.Name; end

        rows(end+1, :) = {s.Name, s.Species, s.Sex, s.Weight, pName, ...
            mine(k).Active, mine(k).LastProtocol, mine(k).LastProtocolVersion, ...
            mine(k).LastBoxID, s.Notes, s.SubjectID, s.Created};
    end
end

T = cell2table(rows, VariableNames = vars);
T = sortrows(T, {'Subject','Project'});
